#!/usr/bin/env bash
# Deploy send-push Edge Function, set APNs secrets, and create notifications INSERT webhook.
#
# Prerequisites:
#   export SUPABASE_ACCESS_TOKEN="sbp_..."   # https://supabase.com/dashboard/account/tokens
#   AuthKey_*.p8 present in repo root (gitignored)
#
# Usage:
#   ./scripts/deploy-push.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export HOME="${HOME_OVERRIDE:-$ROOT/.agent-home}"
mkdir -p "$HOME/.supabase"

PROJECT_REF="${SUPABASE_PROJECT_REF:-dqvguniitpahayaonvjj}"
APNS_KEY_ID="${APNS_KEY_ID:-K6F76CQ7H2}"
APNS_TEAM_ID="${APNS_TEAM_ID:-98S75SX3J9}"
APNS_BUNDLE_ID="${APNS_BUNDLE_ID:-rytecode.closet}"
P8_PATH="${APNS_P8_PATH:-$ROOT/AuthKey_${APNS_KEY_ID}.p8}"
ENV_FILE="$ROOT/scripts/.env.push"
SUPABASE_BIN="$ROOT/node_modules/.bin/supabase"

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "Missing SUPABASE_ACCESS_TOKEN."
  echo "Create one at https://supabase.com/dashboard/account/tokens and export it."
  exit 1
fi

if [[ ! -x "$SUPABASE_BIN" ]]; then
  echo "Installing supabase CLI locally..."
  npm install supabase --save-dev
fi

if [[ ! -f "$P8_PATH" ]]; then
  echo "Missing APNs key file: $P8_PATH"
  exit 1
fi

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [[ -z "${PUSH_WEBHOOK_SECRET:-}" ]]; then
  PUSH_WEBHOOK_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
  umask 077
  cat > "$ENV_FILE" <<EOF
PUSH_WEBHOOK_SECRET=$PUSH_WEBHOOK_SECRET
APNS_KEY_ID=$APNS_KEY_ID
APNS_TEAM_ID=$APNS_TEAM_ID
SUPABASE_PROJECT_REF=$PROJECT_REF
EOF
  echo "Wrote $ENV_FILE (gitignored)"
fi

echo "==> Setting Edge Function secrets"
"$SUPABASE_BIN" secrets set \
  --project-ref "$PROJECT_REF" \
  "APNS_KEY_ID=$APNS_KEY_ID" \
  "APNS_TEAM_ID=$APNS_TEAM_ID" \
  "APNS_BUNDLE_ID=$APNS_BUNDLE_ID" \
  "PUSH_WEBHOOK_SECRET=$PUSH_WEBHOOK_SECRET" \
  "APNS_AUTH_KEY=$(cat "$P8_PATH")"

echo "==> Deploying send-push"
"$SUPABASE_BIN" functions deploy send-push \
  --project-ref "$PROJECT_REF" \
  --no-verify-jwt \
  --use-api

EDGE_URL="https://${PROJECT_REF}.supabase.co/functions/v1/send-push"

echo "==> Creating / replacing notifications INSERT → send-push trigger (pg_net)"
# Management API SQL (beta). Falls back to printing SQL if unavailable.
SQL=$(cat <<EOF
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.notify_send_push_on_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS \$\$
BEGIN
  PERFORM net.http_post(
    url := '${EDGE_URL}',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-webhook-secret', '${PUSH_WEBHOOK_SECRET}'
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', to_jsonb(NEW)
    )
  );
  RETURN NEW;
END;
\$\$;

DROP TRIGGER IF EXISTS notifications_send_push ON public.notifications;
CREATE TRIGGER notifications_send_push
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_send_push_on_notification();
EOF
)

HTTP_CODE=$(curl -sS -o /tmp/supabase-sql-result.json -w "%{http_code}" \
  -X POST "https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.stdin.read()}))' <<<"$SQL")" || true)

if [[ "$HTTP_CODE" == "201" || "$HTTP_CODE" == "200" ]]; then
  echo "Webhook trigger created via Management API (HTTP $HTTP_CODE)."
else
  echo "Management API SQL returned HTTP ${HTTP_CODE:-curl-failed}."
  echo "Run this SQL in the Supabase SQL Editor:"
  echo "-----"
  echo "$SQL"
  echo "-----"
  # Also try the legacy supabase_functions.http_request style via printed SQL only.
fi

echo
echo "Done."
echo "  Function: $EDGE_URL"
echo "  Webhook secret stored in scripts/.env.push"
