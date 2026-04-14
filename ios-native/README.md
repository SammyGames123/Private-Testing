# Pulse iOS (Native SwiftUI)

Native SwiftUI rebuild of Pulse, talking directly to the same Supabase
backend the Next.js web app uses. The Next.js app at the repo root keeps
serving the web build during the rewrite; once this app reaches feature
parity we delete Capacitor (`ios/`, `android/`, `capacitor.config.ts`)
and ship this as the iOS app.

## One-time setup

### 1. Create the Xcode project

1. Open Xcode → File → New → Project…
2. iOS → **App** → Next
3. Fill in:
   - **Product Name**: `Pulse`
   - **Team**: your Apple developer team
   - **Organization Identifier**: `au.com.imaginefashion`
     (this gives you the bundle ID `au.com.imaginefashion.Pulse` —
     match it to whatever your existing TestFlight/cert is using)
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None
   - Uncheck "Include Tests"
4. Click Next, then **save inside `ios-native/`**. You should end up with:

   ```
   ios-native/
     Pulse/
       Pulse.xcodeproj
       Pulse/
         PulseApp.swift          ← Xcode-generated, will be replaced
         ContentView.swift       ← Xcode-generated, will be deleted
         Assets.xcassets/
         Preview Content/
   ```

### 2. Add the Supabase Swift SDK

In Xcode: File → Add Package Dependencies… → paste

```
https://github.com/supabase/supabase-swift
```

→ Add Package → check `Supabase` → Add Package.

### 3. Drop in the source files from this folder

In Finder, open `ios-native/sources/`. You'll see:

```
sources/
  PulseApp.swift
  Services/
    SupabaseManager.swift
  Features/
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

In Xcode:

1. Select `PulseApp.swift` and `ContentView.swift` in the project
   navigator → right-click → Delete → **Move to Trash**.
2. Right-click the `Pulse` group (the inner one, with the Swift files)
   → Add Files to "Pulse"… → navigate to `ios-native/sources/` → select
   **everything inside** (the `PulseApp.swift` file plus the `Services/`
   and `Features/` folders).
3. In the dialog: ✅ "Create groups", ❌ "Copy items if needed" (so the
   files stay in source control under `ios-native/sources/`), ✅ Add to
   target "Pulse".

### 4. Paste your Supabase anon key

Open `Services/SupabaseManager.swift` and replace `PASTE_YOUR_ANON_KEY_HERE`
with the value of `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` from the
Next.js app's `.env.local`. It's a long JWT starting with `eyJ...`.

### 5. Build settings

- Project → Pulse → General → Minimum Deployments → **iOS 16.0** (or
  higher).
- Signing & Capabilities → make sure "Automatically manage signing" is
  on and your team is selected.

### 6. Run

▶︎ Run on the Simulator or your phone. You should see a black "Pulse"
sign-in screen. Use the same email/password you use for the web app —
it's the same Supabase auth tenant.

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

- `sources/PulseApp.swift` — `@main` app entry, owns `AuthState`.
- `sources/Services/` — global services (Supabase client, later: image
  cache, video pool).
- `sources/Features/<feature>/` — one folder per feature, each with its
  own views and view models. New screens go here.
