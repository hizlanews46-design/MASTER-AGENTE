#!/usr/bin/env bash
set -euo pipefail

# auto_bootstrap.sh
# Automated end-to-end bootstrap for the Master Agent Platform on a single Ubuntu 24.04 VM.
# What it does:
#  - creates a secure .env file if missing
#  - runs infra/deploy/bootstrap.sh to install Docker & start docker-compose stack
#  - runs infra/deploy/vault_init_unseal.sh to initialize and unseal Vault (production mode)
#  - writes the Vault root token into .env (for local testing only)
#  - restarts orchestrator so it can read Vault secrets
#  - runs Alembic migrations inside orchestrator container
#  - creates an initial admin user for the orchestrator
#
# Usage: sudo ./infra/deploy/auto_bootstrap.sh
# Run as a user with sudo privileges. The script uses sudo for system installs if needed.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="$REPO_ROOT/.env"
ENV_EXAMPLE="$REPO_ROOT/.env.example"

echo "Starting auto bootstrap from repo root: $REPO_ROOT"

# 1) Create .env if not exists
if [ -f "$ENV_FILE" ]; then
  echo ".env already exists at $ENV_FILE — backing up to .env.bak"
  cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%s)"
else
  echo "Creating .env from .env.example with generated secrets"
  if [ ! -f "$ENV_EXAMPLE" ]; then
    echo "ERROR: .env.example not found at $ENV_EXAMPLE"
    exit 1
  fi
  # generate values
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
# KEYCLOAK_CLIENT_SECRET will be stored in Vault by the init script; we write it now for bootstrap convenience
KEYCLOAK_CLIENT_SECRET=${KEYCLOAK_CLIENT_SECRET}
# VAULT_TOKEN is set after vault init; left blank for now
VAULT_TOKEN=
EOF
  echo "Generated .env with secrets. Review and rotate secrets after initial bootstrap."
fi

# 2) Run the provided bootstrap.sh which installs Docker (if required) and runs docker compose up
echo "Running infra/deploy/bootstrap.sh to install Docker (if needed) and start the docker-compose stack..."
chmod +x infra/deploy/bootstrap.sh
# run bootstrap.sh (it uses sudo internally for package installs)
sudo bash infra/deploy/bootstrap.sh "$REPO_ROOT"

# 3) Initialize and unseal Vault (production mode) and write Keycloak client secret into Vault
# This script will create infra/deploy/vault-keys.json with unseal keys and root token.
echo "Initializing and unsealing Vault (production mode)..."
chmod +x infra/deploy/vault_init_unseal.sh
# Ensure environment variables KEYCLOAK_CLIENT_SECRET and KEYCLOAK_CLIENT_ID are available to the script
export KEYCLOAK_CLIENT_SECRET=$(grep '^KEYCLOAK_CLIENT_SECRET=' .env | cut -d'=' -f2- || true)
export KEYCLOAK_CLIENT_ID=$(grep '^KEYCLOAK_CLIENT_ID=' .env | cut -d'=' -f2- || true)
./infra/deploy/vault_init_unseal.sh

# 4) Read root token from infra/deploy/vault-keys.json and write to .env so orchestrator can read secrets on restart
VAULT_KEYS_FILE="infra/deploy/vault-keys.json"
if [ -f "$VAULT_KEYS_FILE" ]; then
  ROOT_TOKEN=$(jq -r '.root_token' "$VAULT_KEYS_FILE")
  if [ -n "$ROOT_TOKEN" ] && [ "$ROOT_TOKEN" != "null" ]; then
    echo "Writing VAULT_TOKEN to .env (for local testing only)"
    # replace or add VAULT_TOKEN in .env
    if grep -q '^VAULT_TOKEN=' .env; then
      sed -i "s/^VAULT_TOKEN=.*/VAULT_TOKEN=${ROOT_TOKEN}/" .env
    else
      echo "VAULT_TOKEN=${ROOT_TOKEN}" >> .env
    fi
    export VAULT_TOKEN=${ROOT_TOKEN}
  else
    echo "Warning: no root token found in $VAULT_KEYS_FILE"
  fi
else
  echo "Vault keys file not found at $VAULT_KEYS_FILE — make sure vault_init_unseal.sh succeeded"
fi

# 5) Restart orchestrator so it picks up VAULT_TOKEN and other env changes
echo "Restarting orchestrator and worker containers to pick up new environment variables..."
cd "$REPO_ROOT/infra"
docker compose restart orchestrator worker || true

# 6) Run Alembic migrations (explicitly)
echo "Running Alembic migrations inside orchestrator container..."
docker compose exec -T orchestrator alembic upgrade head || true

# 7) Create initial admin user
ADMIN_PASSWORD=$(openssl rand -hex 16)
echo "Creating initial admin user with a generated password. Username: admin. Password will be printed once."
docker compose exec -T orchestrator python tools/create_admin.py --username admin --email admin@example.com --password "${ADMIN_PASSWORD}" || true

# 8) Print summary and important next steps
cat <<EOF
Bootstrap complete (best-effort). Important notes:
- Vault unseal/init output is at: $REPO_ROOT/infra/deploy/vault-keys.json (store securely and remove when safe).
- Initial admin created: username=admin password=${ADMIN_PASSWORD}
- Services should be available on these ports (host):
  - Orchestrator API: http://localhost:8000
  - Prometheus: http://localhost:9090
  - Grafana: http://localhost:3000 (default admin password: admin)
  - RQ exporter: http://localhost:9121/metrics
  - RQ dashboard: http://localhost:9181
  - Keycloak: http://localhost:8081
  - Vault UI: http://localhost:8200 (use root token from infra/deploy/vault-keys.json)

Next recommended actions:
1) In Keycloak admin UI, create users and assign roles (architect, developer, approver, admin) or import a realm.
2) Secure Vault: create an application-specific token with limited policy and replace VAULT_TOKEN in .env with that token. Do NOT keep root token in .env for production.
3) Rotate generated secrets and remove vault-keys.json from disk after storing securely.
4) Consider removing KEYCLOAK_CLIENT_SECRET from .env (it's in Vault now) and restart services.

To inspect logs run:
  cd $REPO_ROOT/infra
  docker compose logs -f orchestrator worker keycloak vault redis postgres

EOF

exit 0
