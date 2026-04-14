import Foundation
import Supabase

/// Thin wrapper around the Supabase videos table for the home feed.
/// First cut: public, non-archived videos ordered by recency, no
/// ranking. We'll port the web app's scoring logic once the basics
/// work on device.
final class FeedService {
    static let shared = FeedService()

    private let client = SupabaseManager.shared.client

    private init() {}

    func fetchFeed(limit: Int = 24) async throws -> [FeedVideo] {
        let videos: [FeedVideo] = try await client
            .from("videos")
            .select("""
                id,
                title,
                caption,
                category,
                playback_url,
                thumbnail_url,
                created_at,
                creator_id,
                profiles:creator_id (username, display_name)
                """)
            .eq("visibility", value: "public")
            .eq("is_archived", value: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        // Drop rows without a playable URL so we don't show dead cells.
        return videos.filter { $0.playbackURL != nil }
    }
}
