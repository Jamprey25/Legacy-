#!/usr/bin/env bash
#
# Dev/maintenance: empty the Vercel Blob store via the guarded purge route
# (POST /v1/internal/purge-blobs, see src/app.ts).
#
# ⚠️  DESTRUCTIVE: deletes EVERY blob in the store. Use only while testing.
#     NEVER run this against a store that holds real users' memories, and
#     never wire it to a cron — there is no undo.
#
# The secret must match the TARGET environment's WEBHOOK_SECRET. Production's secret
# differs from your local .env.local and Vercel won't export it, so to purge prod you
# must pass it explicitly (copy it from Vercel → Settings → Environment Variables):
#
# Usage:
#   WEBHOOK_SECRET=<prod-secret> ./scripts/purge-blobs.sh     # purge production
#   BASE_URL=http://localhost:8787 ./scripts/purge-blobs.sh   # purge local dev (uses .env.local)
#
# If WEBHOOK_SECRET is already set in the environment it is used as-is; otherwise the
# script falls back to backend/.env.local (handy for the local dev server).

set -euo pipefail

BASE_URL="${BASE_URL:-https://legacy-backend-jamprey25s-projects.vercel.app}"

SECRET="${WEBHOOK_SECRET:-}"
if [[ -z "$SECRET" ]]; then
  ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.env.local"
  if [[ -f "$ENV_FILE" ]]; then
    SECRET="$(grep -E '^WEBHOOK_SECRET=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'\'' ' )"
  fi
fi
if [[ -z "$SECRET" ]]; then
  echo "✗ No WEBHOOK_SECRET. Pass it inline: WEBHOOK_SECRET=<prod-secret> $0" >&2
  exit 1
fi

echo "⚠️  Purging ALL blobs from ${BASE_URL}"
curl -sS -X POST "${BASE_URL}/v1/internal/purge-blobs" \
  -H "x-maintenance-secret: ${SECRET}" \
  -w $'\nHTTP %{http_code}\n'
