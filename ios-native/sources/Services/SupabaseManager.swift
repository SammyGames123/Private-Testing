import Foundation
import Supabase

/// Configuration for the Supabase backend. These values match the ones
/// used by the Next.js web app in `.env.local`. The anon key is a
/// public token gated by Row Level Security, so it's safe to ship in
/// client code.
enum SupabaseConfig {
    static let url = URL(string: "https://qrkttpwrnquptrkewdfv.supabase.co")!

    /// Paste the value of `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` from
    /// `.env.local` here. It's a long JWT starting with `eyJ...`.
    static let anonKey = "PASTE_YOUR_ANON_KEY_HERE"
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
