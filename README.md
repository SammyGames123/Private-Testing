# PulsePlay

PulsePlay is a static social video platform prototype designed to run on GitHub Pages. It combines a TikTok-style recommendation feed with creator uploads, lightweight browser-based video playback editing, likes, comments, following/followers, and direct messages.

## What this build includes

- Personalized "For You" feed ranked from interests, follows, likes/comments, watch-category signals, and recency
- "Following" feed for accounts you follow
- Video upload flow with:
  - local file preview for the current browser session
  - persistent public video URL uploads
  - trim start/end controls
  - playback speed controls
  - visual playback filters
- Social features:
  - likes
  - comments
  - follows/followers
  - direct messages
- Browser persistence with `localStorage`
- Seeded creators, posts, and conversations so the app feels alive immediately

## GitHub Pages deployment

1. Push these files to a GitHub repository.
2. In GitHub, open `Settings -> Pages`.
3. Set the source to deploy from your main branch root.
4. Save, then wait for GitHub Pages to publish the site.

Because GitHub Pages is static hosting, this version stores data in the visitor's browser instead of a real backend database.

## Important limitation

Features like global accounts, real persistent uploads, cross-device messaging, and production-grade video processing need a backend. If you want the next version to be fully real, the usual stack would be:

- Frontend: React/Next.js
- Auth and database: Firebase or Supabase
- Video storage/transcoding: Cloudflare Stream, Mux, or AWS S3 + MediaConvert
- Feed/analytics: Postgres + event tracking + recommendation service

## Local preview

Open `index.html` directly in a browser, or serve the folder with any static server.
