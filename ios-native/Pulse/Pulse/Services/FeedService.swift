import Foundation
import Supabase

/// Wrapper around the Supabase tables backing the home feed.
final class FeedService {
    static let shared = FeedService()

    private let client = SupabaseManager.shared.client

    private init() {}

    // MARK: - Feed fetch

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
                profiles:creator_id (username, display_name),
                likes (count),
                comments (count)
                """)
            .eq("visibility", value: "public")
            .eq("is_archived", value: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return videos.filter { $0.playbackURL != nil }
    }

    /// Returns the set of video_ids the current user has liked. Empty
    /// set if signed out.
    func fetchMyLikedVideoIds(userId: String) async throws -> Set<String> {
        struct Row: Decodable { let video_id: String }
        let rows: [Row] = try await client
            .from("likes")
            .select("video_id")
            .eq("user_id", value: userId)
            .execute()
            .value
        return Set(rows.map(\.video_id))
    }

    /// Returns the set of creator_ids the current user follows.
    func fetchMyFollowedCreatorIds(userId: String) async throws -> Set<String> {
        struct Row: Decodable { let following_id: String }
        let rows: [Row] = try await client
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: userId)
            .execute()
            .value
        return Set(rows.map(\.following_id))
    }

    // MARK: - Mutations

    func like(videoId: String, userId: String) async throws {
        struct Insert: Encodable {
            let user_id: String
            let video_id: String
        }
        try await client
            .from("likes")
            .insert(Insert(user_id: userId, video_id: videoId))
            .execute()
    }

    func unlike(videoId: String, userId: String) async throws {
        try await client
            .from("likes")
            .delete()
            .eq("user_id", value: userId)
            .eq("video_id", value: videoId)
            .execute()
    }

    func follow(creatorId: String, followerId: String) async throws {
        struct Insert: Encodable {
            let follower_id: String
            let following_id: String
        }
        try await client
            .from("follows")
            .insert(Insert(follower_id: followerId, following_id: creatorId))
            .execute()
    }

    func unfollow(creatorId: String, followerId: String) async throws {
        try await client
            .from("follows")
            .delete()
            .eq("follower_id", value: followerId)
            .eq("following_id", value: creatorId)
            .execute()
    }
}
