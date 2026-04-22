# send-push

Edge Function that receives push requests from Postgres triggers and
fans them out to APNs. See `../../push_notifications_phase4_triggers.sql`
for the caller side.

## Environment variables

Set these with `supabase secrets set` (or in the dashboard under Edge
Functions → send-push → Secrets):

| Name | Value |
| --- | --- |
| `APNS_KEY_ID` | `6TFS2Q5UY6` (Apple Push Notification key id) |
| `APNS_TEAM_ID` | `Q65PDQX7P7` |
| `APNS_BUNDLE_ID` | `com.spilltop.app` |
| `APNS_PRIVATE_KEY` | Full contents of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines |
| `APNS_ENVIRONMENT` | `sandbox` for dev / TestFlight internal builds; `production` for App Store + TestFlight external |
| `PUSH_WEBHOOK_SECRET` | Shared secret between Postgres triggers and this function. Generate with `openssl rand -hex 32` |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically
by Supabase; you don't need to set them.

### One-liner to set everything

```sh
supabase secrets set \
  APNS_KEY_ID=6TFS2Q5UY6 \
  APNS_TEAM_ID=Q65PDQX7P7 \
  APNS_BUNDLE_ID=com.spilltop.app \
  APNS_ENVIRONMENT=sandbox \
  PUSH_WEBHOOK_SECRET="$(openssl rand -hex 32)" \
  APNS_PRIVATE_KEY="$(cat /path/to/AuthKey_6TFS2Q5UY6.p8)"
```

Note the `APNS_PRIVATE_KEY` value must preserve newlines — using
`"$(cat ...)"` does the right thing in bash/zsh.

## Deploy

```sh
supabase functions deploy send-push
```

## Wire up Postgres

After deploying, tell the database where to POST and which secret to
use. Run once per project (values must match what the function sees):

```sql
alter database postgres
  set "app.settings.push_webhook_url"
  = 'https://<PROJECT_REF>.functions.supabase.co/send-push';

alter database postgres
  set "app.settings.push_webhook_secret"
  = '<the PUSH_WEBHOOK_SECRET you generated above>';
```

Then apply `supabase/push_notifications_phase4_triggers.sql` if you
haven't already. Until both settings are present the `enqueue_push`
helper silently no-ops, so triggers never break writes.

## Environment flip for release

TestFlight external + App Store builds talk to production APNs. When
you ship a build with `aps-environment: production` in the entitlement,
flip the secret:

```sh
supabase secrets set APNS_ENVIRONMENT=production
```

Development builds from Xcode keep using `sandbox` — same key, same
function, Apple picks the host from the device token.

## Security

- The `.p8` private key you shared in chat during setup (key id
  `6TFS2Q5UY6`) should be **revoked** at
  <https://developer.apple.com/account/resources/authkeys/list> and a
  fresh key issued. Update `APNS_KEY_ID` and `APNS_PRIVATE_KEY` secrets
  afterwards.
- The webhook secret is the only thing stopping anyone on the internet
  from spamming pushes through your function. Rotate it if it ever
  leaks — update the secret **and** the database setting in the same
  window so triggers keep working.

## Smoke test

```sh
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: $PUSH_WEBHOOK_SECRET" \
  -d '{
    "user_id": "<your uuid>",
    "category": "likes",
    "title": "Test",
    "body": "Hello from send-push"
  }' \
  "https://<PROJECT_REF>.functions.supabase.co/send-push"
```

Expected response on a registered device: `{"sent":1,"failed":0,"tokens":1}`.
`{"skipped":true,"reason":"no_tokens"}` means the user has no iOS token
registered yet — launch the app, accept the permission prompt, and try
again.
