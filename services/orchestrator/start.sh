#!/usr/bin/env bash
set -euo pipefail

# Run Alembic upgrade head and then start the application
cd /app
if [ -f /app/alembic.ini ]; then
  echo "Running alembic upgrade head..."
  alembic upgrade head || true
fi

# Start the app
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
