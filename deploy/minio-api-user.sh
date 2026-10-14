#!/usr/bin/env bash
# Gives the API its own MinIO user, limited to the nafir-music bucket, so it
# no longer runs with the MinIO root credentials (#217). Safe to run again:
# it updates the user's secret and the policy in place.
#
#   1. Put STORAGE_ACCESS_KEY and STORAGE_SECRET_KEY (new, long, random) in .env.
#   2. With the stack running: deploy/minio-api-user.sh
#   3. docker compose up -d api   (the API now uses the new user)
#
# Rollback: remove STORAGE_ACCESS_KEY/STORAGE_SECRET_KEY from .env and run
# `docker compose up -d api`; the API falls back to the root credentials.
set -euo pipefail
cd "$(dirname "$0")"

set -a
# shellcheck disable=SC1091
. ./.env
set +a
: "${MINIO_ROOT_USER:?set MINIO_ROOT_USER in .env}"
: "${MINIO_ROOT_PASSWORD:?set MINIO_ROOT_PASSWORD in .env}"
: "${STORAGE_ACCESS_KEY:?set STORAGE_ACCESS_KEY in .env}"
: "${STORAGE_SECRET_KEY:?set STORAGE_SECRET_KEY in .env}"
if [ "$STORAGE_ACCESS_KEY" = "$MINIO_ROOT_USER" ]; then
  echo "STORAGE_ACCESS_KEY must differ from MINIO_ROOT_USER" >&2
  exit 1
fi
if [ "${#STORAGE_SECRET_KEY}" -lt 32 ]; then
  echo "STORAGE_SECRET_KEY must be at least 32 characters" >&2
  exit 1
fi

bucket=nafir-music
policy=nafir-api
# Every secret travels in the environment, never on a command line.
script='
set -e
mc alias set nafir "$MC_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
mc mb --ignore-existing "nafir/$BUCKET" >/dev/null
mc admin user add nafir "$STORAGE_ACCESS_KEY" "$STORAGE_SECRET_KEY" >/dev/null
cat > /tmp/nafir-api-policy.json
mc admin policy create nafir "$POLICY" /tmp/nafir-api-policy.json >/dev/null
mc admin policy attach nafir "$POLICY" --user "$STORAGE_ACCESS_KEY" >/dev/null 2>&1 || true
rm -f /tmp/nafir-api-policy.json
# The bucket must stay private: audio is only served through presigned URLs.
mc anonymous get "nafir/$BUCKET" | grep -q "private"
'
env_args=(-e MINIO_ROOT_USER -e MINIO_ROOT_PASSWORD -e STORAGE_ACCESS_KEY -e STORAGE_SECRET_KEY
  -e BUCKET="$bucket" -e POLICY="$policy")

# The official MinIO image ships mc; otherwise use a separate mc image on
# the stack's internal network.
if docker compose exec -T minio sh -c 'command -v mc' >/dev/null 2>&1; then
  docker compose exec -T "${env_args[@]}" -e MC_ENDPOINT=http://127.0.0.1:9000 minio \
    sh -c "$script" < minio-api-policy.json
else
  docker run --rm -i --network "${COMPOSE_PROJECT_NAME:-nafir}_internal" \
    "${env_args[@]}" -e MC_ENDPOINT=http://minio:9000 --entrypoint sh \
    "${MINIO_MC_IMAGE:-minio/mc:latest}" -c "$script" < minio-api-policy.json
fi
echo "MinIO user $STORAGE_ACCESS_KEY can now use $bucket. Run: docker compose up -d api"
