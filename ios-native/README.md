# Pulse iOS (Native SwiftUI)

Native SwiftUI rebuild of Pulse, talking directly to the same Supabase
backend the Next.js web app uses. The Next.js app at the repo root keeps
serving the web build during the rewrite; once this app reaches feature
parity we delete Capacitor (`ios/`, `android/`, `capacitor.config.ts`)
and ship this as the iOS app.

The Xcode project is **not** committed — it's generated from
`Pulse/project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen),
so adding a new Swift file is just "drop it in the right folder and
re-run `xcodegen generate`."

## One-time setup

```sh
# 1. Install XcodeGen (one-off, machine-wide)
brew install xcodegen

# 2. Generate the .xcodeproj from project.yml
cd ios-native/Pulse
xcodegen generate

# 3. Open it in Xcode
open Pulse.xcodeproj
```

In Xcode the first time:

1. **Signing & Capabilities** → pick your Apple developer team.
   Bundle ID is already `au.com.imaginefashion.pulse` — match it to the
   one your existing TestFlight/cert is using.
2. ▶︎ Run on the Simulator or your phone. You should see a black "Pulse"
   sign-in screen. Use the same email/password you use for the web app —
   it's the same Supabase auth tenant.

The Supabase Swift SDK is declared as an SPM dependency in
`project.yml`, so Xcode will resolve it automatically on first open.
The Supabase URL and anon key are baked into
`Pulse/Pulse/Services/SupabaseManager.swift` (anon keys are public
tokens gated by Row Level Security, safe to commit).

## Re-generating after adding files

Any time you add, rename, or delete a Swift file:

```sh
cd ios-native/Pulse
xcodegen generate
```

XcodeGen re-walks `Pulse/Pulse/` and rewrites the `.xcodeproj`. Commit
the new `.swift` files; the `.xcodeproj` itself is gitignored.

## Status

- [x] Auth (login + signup)
- [ ] Feed (TikTok-style vertical scroll, AVPlayer-backed)
- [ ] Profile + my-posts grid
- [ ] Camera + upload
- [ ] Comments / likes / follows
- [ ] Edit profile
- [ ] Messages
- [ ] Polish + native push

## Folder layout

```
ios-native/
  README.md              ← you are here
  .gitignore
  Pulse/
    project.yml          ← XcodeGen manifest (source of truth)
    Pulse.xcodeproj/     ← generated, gitignored
    Pulse/
      PulseApp.swift             ← @main app entry, owns AuthState
      Info.plist                 ← generated from project.yml, gitignored
      Assets.xcassets/
      Preview Content/
      Services/                  ← global services (Supabase client, etc.)
        SupabaseManager.swift
      Features/                  ← one folder per feature
        Auth/
          AuthState.swift
          LoginView.swift
        Root/
          RootView.swift
        Main/
          MainTabView.swift
        Feed/
          FeedView.swift
        Profile/
          ProfileView.swift
```

New screens go under `Features/<feature>/`. Re-run `xcodegen generate`
after adding files and Xcode will pick them up.
