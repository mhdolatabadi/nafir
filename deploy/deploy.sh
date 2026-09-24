#!/usr/bin/env bash
# Pulls the latest main branch and prebuilt images, then restarts the stack. Run on the server from the repository clone.
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "deploy/.env is missing; copy .env.example and fill in real values first." >&2
  exit 1
fi

if ! grep -qE '^NAFIR_DOMAIN=' .env; then
  echo "deploy/.env has no NAFIR_DOMAIN; rename the SOT_* variables to NAFIR_* (see deploy/README.md)." >&2
  exit 1
fi

git fetch --prune origin main
git checkout main
git reset --hard origin/main

# Images are tagged with the commit they were built from; pulling fails if the
# Images workflow has not finished for this commit yet.
export NAFIR_IMAGE_TAG="$(git rev-parse HEAD)"
docker compose pull api web
docker compose up -d --no-build --remove-orphans
docker image prune -f

domain="$(grep -E '^NAFIR_DOMAIN=' .env | cut -d= -f2-)"
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
