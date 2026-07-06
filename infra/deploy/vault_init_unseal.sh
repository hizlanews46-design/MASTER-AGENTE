#!/usr/bin/env bash
set -euo pipefail

# Initialize and unseal Vault running in server mode inside Docker Compose
# This script must be run on the host where docker compose is running and after the vault container is started.
# It will:
#  - run `vault operator init` once and save the output to infra/deploy/vault-keys.json
#  - unseal the vault using the unseal keys
#  - write client credentials into Vault at secret/data/keycloak

COMPOSE_DIR=${1:-$(pwd)/infra}
KEYCLOAK_CLIENT_ID=${KEYCLOAK_CLIENT_ID:-master-agent-client}
KEYCLOAK_CLIENT_SECRET=${KEYCLOAK_CLIENT_SECRET:-master-agent-secret}
VAULT_OUTPUT_FILE=${COMPOSE_DIR}/deploy/vault-keys.json

cd "$COMPOSE_DIR"

# wait for vault container
echo "Waiting for vault to be ready..."
until docker compose ps | grep -q "vault"; do
  sleep 1
  echo -n .
done

# Initialize Vault (only run if not already initialized)
if ! docker compose exec -T vault vault status -format=json | jq -r .initialized | grep -q true; then
  echo "Initializing Vault..."
  docker compose exec -T vault sh -c "vault operator init -format=json" > "$VAULT_OUTPUT_FILE"
  echo "Saved vault init output to $VAULT_OUTPUT_FILE"
else
  echo "Vault already initialized"
fi

# Read unseal keys and unseal
if [ -f "$VAULT_OUTPUT_FILE" ]; then
  echo "Unsealing Vault..."
  KEY1=$(jq -r '.unseal_keys_b64[0]' "$VAULT_OUTPUT_FILE")
  KEY2=$(jq -r '.unseal_keys_b64[1]' "$VAULT_OUTPUT_FILE")
  KEY3=$(jq -r '.unseal_keys_b64[2]' "$VAULT_OUTPUT_FILE")
  docker compose exec -T vault sh -c "vault operator unseal $KEY1"
  docker compose exec -T vault sh -c "vault operator unseal $KEY2"
  docker compose exec -T vault sh -c "vault operator unseal $KEY3"
  ROOT_TOKEN=$(jq -r '.root_token' "$VAULT_OUTPUT_FILE")
  echo "Vault unsealed. Root token available in $VAULT_OUTPUT_FILE"
else
  echo "Vault init output not found at $VAULT_OUTPUT_FILE. If Vault was initialized elsewhere, obtain its root token and keys manually."
fi

# Write Keycloak client credentials into Vault kv v2
if [ -n "$KEYCLOAK_CLIENT_SECRET" ]; then
  echo "Writing Keycloak client credentials into Vault (secret/data/keycloak)..."
  docker compose exec -T vault sh -c "vault kv put secret/keycloak client_id=$KEYCLOAK_CLIENT_ID client_secret='$KEYCLOAK_CLIENT_SECRET'"
  echo "Wrote keycloak client_id/client_secret into Vault"
else
  echo "KEYCLOAK_CLIENT_SECRET not set; skipping writing client secret into Vault"
fi

