#!/usr/bin/env bash
# Pulls the latest main branch and restarts the stack. Run on the server from the repository clone.
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "deploy/.env is missing; copy .env.example and fill in real values first." >&2
  exit 1
fi

git fetch --prune origin main
git checkout main
git reset --hard origin/main

docker compose up -d --build --remove-orphans
docker image prune -f

domain="$(grep -E '^SOT_DOMAIN=' .env | cut -d= -f2-)"
for attempt in $(seq 1 30); do
  if curl -fsS "https://${domain}/api/v1/health"; then
    echo
    echo "Deployed $(git rev-parse --short HEAD) to https://${domain}"
    exit 0
  fi
  sleep 5
done

echo "Health check failed for https://${domain}/api/v1/health" >&2
docker compose ps
docker compose logs --tail=100 api
exit 1
