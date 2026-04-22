# Spilltop LiveKit Setup

Spilltop now uses self-hosted LiveKit for live rooms instead of the placeholder provider flow.

## 1. Run LiveKit locally for development

Install LiveKit and start the dev server:

```bash
brew update && brew install livekit
livekit-server --dev --bind 0.0.0.0
```

The default development credentials are:

- API key: `devkey`
- API secret: `secret`

If you're testing on a physical iPhone, use your Mac's LAN IP for the websocket URL, for example:

```text
ws://192.168.1.10:7880
```

## 2. Configure Supabase function secrets

```bash
supabase secrets set \
  LIVEKIT_WS_URL=ws://192.168.1.10:7880 \
  LIVEKIT_API_KEY=devkey \
  LIVEKIT_API_SECRET=secret
```

For production, switch to your `wss://livekit.your-domain.com` endpoint and production API credentials.

## 3. Deploy the token broker

```bash
supabase functions deploy livekit-session
```

## 4. Regenerate the Xcode project

```bash
xcodegen generate
```

## 5. Build and test

- Host starts a Spilltop live stream
- The app creates a `live_streams` row with provider `livekit`
- Host joins room `spilltop-live-<stream-id>` as publisher
- Viewers join the same room as subscribers

## Notes

- Rooms are created automatically by LiveKit when the first participant joins.
- Spilltop keeps the `live_streams` row as the product-level source of truth, while LiveKit handles realtime media transport.
- `viewer_count` is still app-level metadata and is not yet synced from LiveKit room participants.
