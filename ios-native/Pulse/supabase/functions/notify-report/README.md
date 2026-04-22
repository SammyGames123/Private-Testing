# notify-report

Sends an email to the moderation inbox whenever the iOS app creates a
`content_reports` row.

The app still stores the report even if email is not configured. This
function is a review-readiness/ops layer so reports are seen quickly.

## Environment

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `RESEND_API_KEY`
- `MODERATION_EMAIL_TO` should be `support@spilltop.com`
- `MODERATION_EMAIL_FROM` should be a verified sender, ideally `Spilltop Safety <support@spilltop.com>`

## Deploy

```bash
npx supabase functions deploy notify-report --use-api
```

## Configure

```bash
npx supabase secrets set \
  RESEND_API_KEY='your-resend-api-key' \
  MODERATION_EMAIL_TO='support@spilltop.com' \
  MODERATION_EMAIL_FROM='Spilltop Safety <support@spilltop.com>'
```
