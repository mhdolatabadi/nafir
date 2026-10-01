#!/usr/bin/env bash
# Pulls one validated commit and its prebuilt images, then restarts the stack.
set -euo pipefail

revision="${1:-main}"
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "deploy/.env is missing; copy .env.example and fill in real values first." >&2
  exit 1
fi

if ! grep -qE '^NAFIR_DOMAIN=' .env; then
  echo "deploy/.env has no NAFIR_DOMAIN; see deploy/README.md." >&2
  exit 1
fi

git fetch --prune origin main
git checkout --detach "$revision"

# Images are tagged with the exact source commit. Pull everything before
# changing running containers, so a missing image leaves production untouched.
export NAFIR_IMAGE_TAG="$(git rev-parse HEAD)"
docker compose pull api web

# One-time move from the old project name ("deploy", from this folder) to
# "nafir": remove this checkout's old containers so the new ones can take
# their ports. Only containers Compose started from this very folder match;
# volumes are kept and the new containers reuse them.
old_containers="$(docker ps -aq \
  --filter label=com.docker.compose.project=deploy \
  --filter "label=com.docker.compose.project.working_dir=$(pwd)")"
if [[ -n "$old_containers" ]]; then
  echo "Replacing the containers of the old \"deploy\" project."
  docker rm -f $old_containers
fi

docker compose up -d --no-build --remove-orphans
docker image prune -f

domain="$(grep -E '^NAFIR_DOMAIN=' .env | cut -d= -f2-)"
ops_token="$(grep -E '^OPS_TOKEN=' .env | cut -d= -f2- || true)"

# Reports the bots' webhook and import queue once they have registered. A
# problem is printed but does not fail the deploy: the site itself is up.
check_bots() {
  [[ -n "$ops_token" ]] || return 0
  local report=""
  for attempt in $(seq 1 6); do
    report="$(curl -fsS -H "Authorization: Bearer ${ops_token}" "https://${domain}/api/v1/ops/bots" || true)"
    [[ "$report" == *'"healthy":true'* ]] && break
    sleep 5
  done
  echo "Bot health: ${report:-unavailable}"
  if [[ "$report" != *'"healthy":true'* ]]; then
    echo "WARNING: a bot needs attention; see deploy/README.md, Operating the bots." >&2
  fi
}
for attempt in $(seq 1 30); do
  if curl -fsS "https://${domain}/api/v1/health"; then
    echo
    echo "Deployed $(git rev-parse --short HEAD) to https://${domain}"
    check_bots
    exit 0
  fi
  sleep 5
done

echo "Health check failed for https://${domain}/api/v1/health" >&2
docker compose ps
docker compose logs --tail=100 api
exit 1
