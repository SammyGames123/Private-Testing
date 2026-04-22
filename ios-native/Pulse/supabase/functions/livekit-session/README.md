## `livekit-session`

Supabase Edge Function that mints short-lived LiveKit join tokens for Spilltop live streams.

### Required secrets

Set these in Supabase before deploying:

```bash
supabase secrets set \
  LIVEKIT_WS_URL=wss://livekit.your-domain.com \
  LIVEKIT_API_KEY=your_api_key \
  LIVEKIT_API_SECRET=your_api_secret
```

For local development with a self-hosted LiveKit server, LiveKit's official local guide uses:

- WebSocket URL: `ws://<your-lan-ip>:7880`
- API key: `devkey`
- API secret: `secret`

If you run LiveKit locally and want to reach it from a real iPhone on the same network, do not use `localhost`. Use your Mac's LAN IP and bind LiveKit to `0.0.0.0`.

Example local launch:

```bash
livekit-server --dev --bind 0.0.0.0
```

### Deploy

```bash
supabase functions deploy livekit-session
```

### Request body

```json
{
  "stream_id": "<live-stream-uuid>",
  "role": "publisher"
}
```

`role` can be `publisher` or `subscriber`.

### What it does

- Verifies the caller via Supabase auth
- Confirms the live stream exists and is still active
- Restricts publisher tokens to the stream creator
- Generates a LiveKit room token tied to the Spilltop stream room
