#!/usr/bin/env bash
set -euo pipefail

# auto_bootstrap.sh (updated)
# Automated end-to-end bootstrap for the Master Agent Platform on a single Ubuntu 24.04 VM.
# Enhancements in this version:
#  - Does NOT place the Vault root token into .env
#  - Creates a limited Vault policy and token for the orchestrator and writes that token into .env
#  - Automatically creates Keycloak realm-level roles and users (admin, developer, approver)
#
# Usage: sudo ./infra/deploy/auto_bootstrap.sh
# Run as a user with sudo privileges. The script uses sudo for system installs if needed.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="$REPO_ROOT/.env"
ENV_EXAMPLE="$REPO_ROOT/.env.example"

echo "Starting auto bootstrap from repo root: $REPO_ROOT"

# Helper: wait for HTTP endpoint
wait_for_http() {
  local url="$1"; local timeout=${2:-120}
  echo "Waiting for $url to respond..."
  local start=$(date +%s)
  while true; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      echo "$url is up"
      return 0
    fi
    now=$(date +%s)
    if [ $((now-start)) -ge $timeout ]; then
      echo "Timed out waiting for $url"
      return 1
    fi
    sleep 2
  done
}

# 1) Create .env if not exists (generate strong secrets)
if [ -f "$ENV_FILE" ]; then
  echo ".env already exists at $ENV_FILE — backing up to .env.bak"
  cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%s)"
else
  echo "Creating .env from .env.example with generated secrets"
  if [ ! -f "$ENV_EXAMPLE" ]; then
    echo "ERROR: .env.example not found at $ENV_EXAMPLE"
    exit 1
  fi
  SECRET_KEY=$(openssl rand -hex 32)
  POSTGRES_PASSWORD=$(openssl rand -hex 16)
  MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
  KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -hex 16)
  N8N_PASSWORD=$(openssl rand -hex 16)
  KEYCLOAK_CLIENT_SECRET=$(openssl rand -hex 24)

  cat > "$ENV_FILE" <<EOF
SECRET_KEY=${SECRET_KEY}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}
N8N_PASSWORD=${N8N_PASSWORD}
KEYCLOAK_CLIENT_ID=master-agent-client
# (Will be written into Vault) KEYCLOAK_CLIENT_SECRET=${KEYCLOAK_CLIENT_SECRET}
# VAULT_TOKEN will be written with a least-privilege token (not root)
VAULT_TOKEN=
EOF
  echo "Generated .env with secrets. Review and rotate secrets after initial bootstrap."
fi

# 2) Run the provided bootstrap.sh which installs Docker (if required) and runs docker compose up
echo "Running infra/deploy/bootstrap.sh to install Docker (if needed) and start the docker-compose stack..."
chmod +x infra/deploy/bootstrap.sh
sudo bash infra/deploy/bootstrap.sh "$REPO_ROOT"

# 3) Initialize and unseal Vault (production mode)
echo "Initializing and unsealing Vault (production mode)..."
chmod +x infra/deploy/vault_init_unseal.sh
# Ensure KEYCLOAK_CLIENT_SECRET and KEYCLOAK_CLIENT_ID are available to the init script
export KEYCLOAK_CLIENT_SECRET=$(grep -E '^KEYCLOAK_CLIENT_SECRET=' .env | cut -d'=' -f2- || true)
export KEYCLOAK_CLIENT_ID=$(grep -E '^KEYCLOAK_CLIENT_ID=' .env | cut -d'=' -f2- || true)
./infra/deploy/vault_init_unseal.sh

VAULT_KEYS_FILE="infra/deploy/vault-keys.json"
if [ ! -f "$VAULT_KEYS_FILE" ]; then
  echo "Vault init output not found at $VAULT_KEYS_FILE — cannot continue"
  exit 1
fi

# 4) Create a least-privilege Vault policy and token for the orchestrator (do not use root token in .env)
ROOT_TOKEN=$(jq -r '.root_token' "$VAULT_KEYS_FILE")
if [ -z "$ROOT_TOKEN" ] || [ "$ROOT_TOKEN" = "null" ]; then
  echo "Cannot read root token from $VAULT_KEYS_FILE"
  exit 1
fi

echo "Writing an orchestrator Vault policy and creating a limited token..."
# Define policy: read access to the KV paths we use
ORCH_POLICY_HCL=$(cat <<'POLICY'
path "secret/data/keycloak" {
  capabilities = ["read"]
}
path "secret/data/postgres" {
  capabilities = ["read"]
}
path "secret/data/minio" {
  capabilities = ["read"]
}
POLICY
)

# Write policy into Vault using the Vault CLI inside the container
docker compose exec -T vault sh -c "vault login ${ROOT_TOKEN} >/dev/null 2>&1 && echo \"${ORCH_POLICY_HCL}\" | vault policy write orchestrator -"

# Create a token bound to the orchestrator policy
ORCH_TOKEN_JSON=$(docker compose exec -T vault sh -c "vault login ${ROOT_TOKEN} >/dev/null 2>&1 && vault token create -policy=orchestrator -format=json")
ORCH_TOKEN=$(echo "$ORCH_TOKEN_JSON" | jq -r .auth.client_token)
if [ -z "$ORCH_TOKEN" ] || [ "$ORCH_TOKEN" = "null" ]; then
  echo "Failed to create orchestrator token in Vault"
  exit 1
fi

# Persist the orchestrator token into .env (safe-ish: token is least-privilege). Do NOT persist root token.
if grep -q '^VAULT_TOKEN=' .env; then
  sed -i "s/^VAULT_TOKEN=.*/VAULT_TOKEN=${ORCH_TOKEN}/" .env
else
  echo "VAULT_TOKEN=${ORCH_TOKEN}" >> .env
fi
export VAULT_TOKEN=${ORCH_TOKEN}

# 5) Ensure Keycloak is up before creating users/roles
echo "Waiting for Keycloak to be ready on http://localhost:8081..."
if ! wait_for_http "http://localhost:8081" 120; then
  echo "Keycloak did not start in time; check docker compose logs"
  docker compose ps
  exit 1
fi

# 6) Create realm roles and users in Keycloak (admin, developer, approver)
KEYCLOAK_ADMIN_PASSWORD=$(grep '^KEYCLOAK_ADMIN_PASSWORD=' .env | cut -d'=' -f2-)
if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
  echo "KEYCLOAK_ADMIN_PASSWORD not set in .env — cannot create Keycloak users"
else
  echo "Creating Keycloak admin token (admin-cli)..."
  # Get admin token from master realm
  ADMIN_TOKEN=$(curl -s -X POST "http://localhost:8081/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=admin-cli&username=kcadmin&password=${KEYCLOAK_ADMIN_PASSWORD}&grant_type=password" | jq -r .access_token)

  if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
    echo "Failed to obtain Keycloak admin token; check KEYCLOAK_ADMIN_PASSWORD and Keycloak logs"
  else
    REALM_NAME=${KEYCLOAK_REALM:-master-agent-realm}
    echo "Ensuring realm '$REALM_NAME' exists (if provided by import it will be present)"
    # create roles
    for role in admin architect developer approver; do
      echo "Creating role: $role"
      curl -s -X POST "http://localhost:8081/admin/realms/${REALM_NAME}/roles" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H 'Content-Type: application/json' \
        -d "{\"name\": \"${role}\"}" || true
    done

    # create users with passwords and assign realm roles
    declare -A USERS
    USERS=( [admin]=admin@example.com [developer]=dev@example.com [approver]=approver@example.com )

    echo "Creating users and assigning roles"
    for username in "${!USERS[@]}"; do
      email=${USERS[$username]}
      password=$(openssl rand -hex 12)
      echo "Creating user $username (password: $password)"
      # create user
      curl -s -X POST "http://localhost:8081/admin/realms/${REALM_NAME}/users" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H 'Content-Type: application/json' \
        -d "{\"username\": \"${username}\", \"email\": \"${email}\", \"enabled\": true}" >/dev/null || true

      # obtain user id
      uid=$(curl -s -X GET "http://localhost:8081/admin/realms/${REALM_NAME}/users?username=${username}" -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.[0].id')
      if [ -z "$uid" ] || [ "$uid" = "null" ]; then
        echo "Failed to find created user $username; skipping password set"
        continue
      fi

      # set password (reset-password)
      curl -s -X PUT "http://localhost:8081/admin/realms/${REALM_NAME}/users/${uid}/reset-password" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H 'Content-Type: application/json' \
        -d "{\"type\": \"password\", \"value\": \"${password}\", \"temporary\": false}" >/dev/null || true

      # get role representation
      role_repr=$(curl -s -X GET "http://localhost:8081/admin/realms/${REALM_NAME}/roles/${username}" -H "Authorization: Bearer ${ADMIN_TOKEN}" || true)
      if [ -z "$role_repr" ] || [ "$role_repr" = "null" ]; then
        # fallback: fetch role by name
        role_repr=$(curl -s -X GET "http://localhost:8081/admin/realms/${REALM_NAME}/roles/${username}" -H "Authorization: Bearer ${ADMIN_TOKEN}" || true)
      fi

      # assign role to user (realm-level)
      # fetch role representation object properly
      role_obj=$(curl -s -X GET "http://localhost:8081/admin/realms/${REALM_NAME}/roles/${username}" -H "Authorization: Bearer ${ADMIN_TOKEN}")
      if [ -n "$role_obj" ] && [ "$role_obj" != "null" ]; then
        curl -s -X POST "http://localhost:8081/admin/realms/${REALM_NAME}/users/${uid}/role-mappings/realm" \
          -H "Authorization: Bearer ${ADMIN_TOKEN}" \
          -H 'Content-Type: application/json' \
          -d "[${role_obj}]" >/dev/null || true
        echo "Assigned realm role '${username}' to user ${username}"
      else
        echo "Role object for ${username} not found; created user but did not assign role"
      fi

      # print credentials summary (user:password)
      echo "CREATED_KEYCLOAK_USER ${username} password=${password}"
    done
  fi
fi

# 7) Restart orchestrator & worker so they pick up the new VAULT_TOKEN
echo "Restarting orchestrator and worker containers to pick up new VAULT_TOKEN..."
cd "$REPO_ROOT/infra"
docker compose restart orchestrator worker || true

# 8) Run Alembic migrations and create initial admin user for orchestrator
echo "Running Alembic migrations and creating initial orchestrator admin user..."
docker compose exec -T orchestrator alembic upgrade head || true
# create orchestrator admin with known password
ADMIN_PASSWORD=$(openssl rand -hex 12)
docker compose exec -T orchestrator python tools/create_admin.py --username admin --email admin@example.com --password "${ADMIN_PASSWORD}" || true

# 9) Summary
cat <<EOF
Auto-bootstrap finished (best-effort).
Important outputs and next steps:
 - Vault unseal/init output: $REPO_ROOT/infra/deploy/vault-keys.json (store securely)
 - A least-privilege Vault token has been created and written into .env as VAULT_TOKEN (for orchestrator use). This is NOT the root token.
 - Orchestrator admin user created: username=admin password=${ADMIN_PASSWORD}
 - Keycloak users created: admin, developer, approver (passwords printed above in CREATION logs)

Next recommended steps:
 - Move infra/deploy/vault-keys.json to secure storage and delete it from the host when you have stored keys safely.
 - Replace the VAULT_TOKEN in .env with a token with the exact policy you want (or keep as is for local testing).
 - Remove KEYCLOAK_CLIENT_SECRET from .env and rely on Vault for secret retrieval.
 - Review Keycloak users and change any generated passwords as desired.

To inspect logs:
  cd $REPO_ROOT/infra
  docker compose logs -f orchestrator worker keycloak vault redis postgres

EOF

exit 0
