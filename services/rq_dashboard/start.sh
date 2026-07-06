#!/usr/bin/env bash
set -euo pipefail

# Start rq-dashboard pointing to Redis service
RQ_REDIS_URL=${RQ_REDIS_URL:-redis://redis:6379}
exec rq-dashboard --redis-url "$RQ_REDIS_URL" --host 0.0.0.0 --port 9181
