# delete-account

Supabase Edge Function that lets a signed-in user delete their own account.

## What it does

1. Resolves the caller from their JWT (anon client).
2. Uses a service-role client to:
   - delete the caller's videos + thumbnails from the `videos` bucket,
   - delete the caller's avatar from the `avatars` bucket,
   - delete the `profiles` row (FK cascades handle most of the rest),
   - delete the `auth.users` row via `auth.admin.deleteUser`.

A user can only ever delete themselves — the service-role key is never
exposed to the client.

## Environment

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

Set these in the Supabase dashboard under
Edge Functions → delete-account → Secrets.

## Deploy

```bash
supabase functions deploy delete-account
```

## Client

The iOS app calls this via `AccountService.deleteMyAccount()` from the
Profile → Settings → Account sheet.
