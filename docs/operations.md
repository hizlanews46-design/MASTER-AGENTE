# Add instructions to initialize Keycloak and Vault and create admin user

## Keycloak
- Keycloak is configured in infra/docker-compose.yml and listens on port 8081.
- Default admin: kcadmin / set via KEYCLOAK_ADMIN_PASSWORD in .env
- A sample realm import is provided at infra/keycloak/realm-export.json. Keycloak start-dev will load import files placed in /opt/keycloak/data/import.

## Vault
- Vault runs in dev mode for single-VM convenience and listens on port 8200.
- Configure VAULT_ROOT_TOKEN in .env to set the root token used by the init script.
- After the stack is up, run infra/deploy/bootstrap_keycloak_vault.sh to initialize secrets.

## Alembic migrations
- Alembic is included under services/orchestrator/alembic.
- The orchestrator image runs `alembic upgrade head` on startup. You can also run migrations manually:
  - docker compose exec orchestrator alembic upgrade head

## Create admin user
- Use the create_admin CLI inside orchestrator container to create an initial admin user:
  - docker compose exec orchestrator python tools/create_admin.py --username admin --email admin@example.com --password <password>
