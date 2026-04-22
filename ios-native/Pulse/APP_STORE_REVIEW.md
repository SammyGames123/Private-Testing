# Spilltop App Review Notes

Use this as the source for TestFlight Beta App Review notes and the later
App Store review notes.

## TestFlight

- Internal testing does not require TestFlight App Review.
- External testing requires TestFlight App Review for the first build of the
  version.
- Provide a demo account with posted sample content, or tell Apple how to
  create an account and test posting.

## Safety And UGC

Spilltop contains user-generated photos, videos, live streams, comments, and
direct messages. Current safeguards:

- Users can report posts, comments, live streams, profiles, and general
  problems.
- Reports are stored in `public.content_reports`.
- The app attempts to call `notify-report` after a report is created so the
  moderation inbox is emailed quickly.
- Users can block accounts from profiles and manage blocked accounts in
  Settings.
- Text submitted in post titles, captions, tags, comments, and live chat is
  checked by `ContentPolicy` before posting.
- Users can delete their account in Profile > Settings > Account.
- Terms, Privacy Policy, and Community Guidelines are linked from Settings.

## Required Before External Review

- Deploy `supabase/functions/notify-report`.
- Set `MODERATION_EMAIL_TO` to `support@spilltop.com`.
- Set the TestFlight Feedback Email in App Store Connect to `support@spilltop.com`.
- Confirm the Terms, Privacy Policy, and Community Guidelines links are live
  and branded for Spilltop.
- Create an App Review demo account and include credentials in review notes.

## Suggested Review Notes

Spilltop is a nightlife social app where users share short-lived location-based
moments on a map, post photos/videos, live stream, comment, message, follow,
and block/report users.

Moderation and safety:
Users can report offensive posts, comments, live streams, and profiles.
Reports are stored server-side and forwarded to the moderation email inbox for
review. Users can block abusive accounts. Basic text filtering is applied to
post titles, captions, tags, comments, and live chat before content is posted.
Community Guidelines, Terms, Privacy Policy, and account deletion are available
in Profile > Settings.

Test flow:
1. Sign in with the provided demo account.
2. Open Live to view the feed.
3. Open Map to view 24-hour map moments.
4. Use Post to create a photo/video moment.
5. Open another user's profile to test Report and Block.
6. Open Profile > Settings to test account deletion, blocked accounts,
   privacy, support/reporting, and legal links.
