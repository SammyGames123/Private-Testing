import Foundation
import Supabase

/// Configuration for the Supabase backend. These values match the ones
/// used by the Next.js web app in `.env.local`. The anon key is a
/// public token gated by Row Level Security, so it's safe to ship in
/// client code.
enum SupabaseConfig {
    static let url = URL(string: "https://qrkttpwrnquptrkewdfv.supabase.co")!

    /// Mirrors `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` from the Next.js
    /// app's `.env.local`. Anon keys are public tokens gated by RLS, so
    /// shipping them in the client binary is fine.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFya3R0cHdybnF1cHRya2V3ZGZ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0MTc1NjksImV4cCI6MjA5MDk5MzU2OX0.vB2bAd-gDg4YtPYxA34M0-zKbHOogxbBIa0GwRguIAk"
}

/// Single shared Supabase client used everywhere in the app.
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }
}

extension SupabaseManager {
    func currentSession() async -> Session? {
        try? await client.auth.session
    }

    func currentAccessToken() async -> String? {
        await currentSession()?.accessToken
    }

    func currentUserId() async -> String? {
        guard let session = await currentSession() else { return nil }
        return session.user.id.uuidString.lowercased()
    }
}
