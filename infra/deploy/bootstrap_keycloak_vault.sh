#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script to import Keycloak realm and initialize Vault secrets
COMPOSE_DIR=${1:-$(pwd)/infra}
cd "$COMPOSE_DIR"

echo "Waiting for Keycloak to be ready on port 8081..."
until curl -s http://localhost:8081/; do
  sleep 1
  echo -n .
done

echo "Keycloak appears up. Importing realm (if not auto-imported)..."
# If Keycloak didn't auto-import, you can import via kcadm, but start-dev often imports data under /opt/keycloak/data/import

# Initialize Vault secrets
if docker compose ps | grep vault >/dev/null 2>&1; then
  echo "Initializing Vault secrets..."
  # run init_vault.sh inside host (it uses Vault HTTP API)
  ./deploy/init_vault.sh
else
  echo "Vault container not found. Skipping Vault init."
fi

echo "Bootstrap complete."
