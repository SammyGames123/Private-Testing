# PulsePlay Next

This is the real `Next.js` foundation for PulsePlay, a social video platform with short-form uploads, creator feeds, comments, follows, messaging, and a recommendation system.

## Current status

- `Next.js` app scaffolded
- Product-style homepage replacing the default starter
- Demo feed, creators, inbox, and roadmap sections in place
- Ready for backend integration

## Run locally

Use `npm.cmd` in PowerShell if script execution blocks `npm`.

```powershell
npm.cmd run dev
```

Then open [http://localhost:3000](http://localhost:3000).

## Recommended stack

- Frontend: `Next.js`
- Auth/database/realtime: `Supabase`
- Video hosting/transcoding: `Mux` or `Cloudflare Stream`
- Hosting: `Vercel`
- Analytics and ranking inputs: `Postgres` event tables

## First implementation steps

1. Add Supabase and environment variables.
2. Run [schema.sql](C:/Users/sammy/CodeXPLayGround/pulseplay-next/supabase/schema.sql) in the Supabase SQL Editor.
3. Replace demo data with server-fetched data.
4. Add authentication and onboarding.
5. Build the upload flow against your chosen video provider.
6. Start the recommendation feed with a simple score from follows, watch time, likes, comments, and recency.

## Suggested tables

- `profiles`
- `videos`
- `video_tags`
- `follows`
- `likes`
- `comments`
- `message_threads`
- `messages`
- `watch_events`

## Next commands

```powershell
npm.cmd run dev
npm.cmd run lint
npm.cmd run build
```

## What to build next

- Authentication pages
- Real feed queries
- Upload studio
- Profile pages
- Comment and like mutations
- Follow system
- Inbox UI backed by realtime subscriptions

## Supabase setup

1. Open your Supabase project.
2. Go to `SQL Editor`.
3. Paste in [schema.sql](C:/Users/sammy/CodeXPLayGround/pulseplay-next/supabase/schema.sql).
4. Run it once.
5. Refresh `/dashboard` in the app.

That schema creates:

- `profiles`
- `videos`
- `video_tags`
- `follows`
- `likes`
- `comments`
- `watch_events`
- `message_threads`
- `thread_participants`
- `messages`

It also adds row-level security policies and a trigger that creates a `profiles` row automatically for every new auth user.
