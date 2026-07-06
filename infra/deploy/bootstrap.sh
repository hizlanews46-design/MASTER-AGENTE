#!/usr/bin/env bash
set -euo pipefail

# Usage: ./bootstrap.sh /path/to/project
PROJECT_DIR=${1:-$(pwd)}
ENV_FILE=${PROJECT_DIR}/.env

# ensure Docker and docker-compose are installed
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not installed. Installing..."
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
fi

if ! command -v docker-compose >/dev/null 2>&1; then
  echo "Installing docker-compose..."
  sudo apt-get install -y docker-compose-plugin
fi

# create .env if not exists
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<EOF
SECRET_KEY=$(openssl rand -hex 32)
N8N_PASSWORD=$(openssl rand -hex 16)
POSTGRES_PASSWORD=ma_pass
MINIO_ROOT_PASSWORD=minioadmin
EOF
  echo "Created .env with random secrets. Review before running."
fi

# start stack
cd "$PROJECT_DIR/infra"
docker compose pull || true
docker compose up -d --remove-orphans

echo "Stack starting... use 'docker compose ps' to inspect."
