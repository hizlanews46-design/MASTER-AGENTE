#!/usr/bin/env bash
set -euo pipefail

# Initialize Vault: requires docker-compose stack to be up
# This script will write initial secrets to Vault using the root token from .env or default 'root'.
VAULT_ADDR=${VAULT_ADDR:-http://127.0.0.1:8200}
ROOT_TOKEN=${VAULT_ROOT_TOKEN:-root}
KEYCLOAK_CLIENT_ID=${KEYCLOAK_CLIENT_ID:-master-agent-client}
KEYCLOAK_CLIENT_SECRET=${KEYCLOAK_CLIENT_SECRET:-master-agent-secret}

export VAULT_ADDR

echo "Waiting for Vault to be ready..."
until curl -s ${VAULT_ADDR}/v1/sys/health | grep -q initialized; do
  sleep 1
  echo -n .
done

echo "Vault is responding. Using root token to write secrets."

# Write database credentials and MinIO creds
curl --header "X-Vault-Token: ${ROOT_TOKEN}" --request POST --data '{"data": {"username": "ma_user", "password": "ma_pass", "db": "master_agent"}}' ${VAULT_ADDR}/v1/secret/data/postgres
curl --header "X-Vault-Token: ${ROOT_TOKEN}" --request POST --data '{"data": {"MINIO_ROOT_USER": "minioadmin", "MINIO_ROOT_PASSWORD": "minioadmin"}}' ${VAULT_ADDR}/v1/secret/data/minio

# Store KEYCLOAK admin credentials and client credentials
curl --header "X-Vault-Token: ${ROOT_TOKEN}" --request POST --data '{"data": {"KEYCLOAK_ADMIN": "kcadmin", "KEYCLOAK_ADMIN_PASSWORD": "'${KEYCLOAK_ADMIN_PASSWORD}'", "client_id": "'${KEYCLOAK_CLIENT_ID}'", "client_secret": "'${KEYCLOAK_CLIENT_SECRET}'"}}' ${VAULT_ADDR}/v1/secret/data/keycloak

echo "Vault initialization complete. Secrets written to secret/data/* paths."
