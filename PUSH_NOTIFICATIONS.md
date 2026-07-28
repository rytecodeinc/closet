# Native APNs push via Supabase Edge Functions

In-app rows in `public.notifications` remain the source of truth. This stack sends a lock-screen APNs alert whenever a notification row is inserted.

## Prerequisites

1. Apple Developer → **Identifiers** → App ID `rytecode.closet` → enable **Push Notifications**.
2. Apple Developer → **Keys** → create an **APNs** key (`.p8`). Note **Key ID** and **Team ID**.
3. Xcode → Signing & Capabilities → add **Push Notifications** (Debug: `closet/closet.entitlements`; Release/TestFlight: `closet/closetRelease.entitlements`).
4. Run SQL in Supabase:
   - `SUPABASE_DEVICE_TOKENS.sql`
   - Existing `SUPABASE_NOTIFICATIONS_TABLE.sql` + friendship/outfit/content-like notification triggers
     (`SUPABASE_FRIENDSHIP_NOTIFICATIONS.sql`, outfit suggestion notify in `SUPABASE_OUTFIT_SUGGESTIONS.sql`,
     `SUPABASE_CONTENT_LIKE_NOTIFICATIONS.sql`)
5. Deploy Edge Function and wire a Database Webhook (below).

## Deploy Edge Function

Preferred (one script — needs a personal access token):

1. Create a token at https://supabase.com/dashboard/account/tokens
2. From the repo root:

```bash
export SUPABASE_ACCESS_TOKEN="sbp_..."
./scripts/deploy-push.sh
```

This sets APNs secrets (using `AuthKey_K6F76CQ7H2.p8`), deploys `send-push`, and creates a `notifications` INSERT trigger via `pg_net` (secured with `PUSH_WEBHOOK_SECRET`).

Manual alternative:

```bash
cd "/path/to/closet"
supabase login
supabase link --project-ref dqvguniitpahayaonvjj
supabase secrets set \
  APNS_KEY_ID="K6F76CQ7H2" \
  APNS_TEAM_ID="98S75SX3J9" \
  APNS_BUNDLE_ID="rytecode.closet" \
  APNS_AUTH_KEY="$(cat AuthKey_K6F76CQ7H2.p8)"
supabase functions deploy send-push --no-verify-jwt
```

`supabase/config.toml` sets `verify_jwt = false` for this function so the Database Webhook / `pg_net` trigger can call it.

## Database Webhook

Supabase Dashboard → **Database** → **Webhooks** → Create:

| Field | Value |
|--------|--------|
| Table | `notifications` |
| Events | Insert |
| Type | Supabase Edge Functions |
| Function | `send-push` |
| HTTP Headers | `Authorization: Bearer <SERVICE_ROLE_KEY>` |

(Alternatively use the optional `SUPABASE_NOTIFICATIONS_PUSH_WEBHOOK.sql` + `pg_net` path.)

## iOS behavior

- After sign-in (production / friends enabled), the app requests notification permission and registers for APNs.
- Device token is upserted into `device_tokens` with `environment` = `sandbox` (DEBUG) or `production` (Release / TestFlight / App Store).
- The Edge Function routes each token to the matching APNs host.
- Tapping a push opens the Profile tab → Notifications list.
- Sign-out deletes this device’s token.

## Verify

1. Two devices / accounts as friends.
2. A sends a friend request (or Redress suggestion) so a `notifications` row is inserted for B.
3. B receives a lock-screen push; tap opens Notifications.
4. Check Edge Function logs if delivery fails (`BadDeviceToken` usually means sandbox vs production mismatch).

## Notes

- Simulator does not receive real APNs; use a physical device.
- Debug builds use `closet/closet.entitlements` (`aps-environment` = development) and store tokens as `sandbox`.
- Release / TestFlight use `closet/closetRelease.entitlements` (`aps-environment` = production) and store tokens as `production`.
- Do not commit `.p8` keys or the service role key.
