import Foundation
import Supabase

/// Point-earning actions and their values. Mirrored in SQL (see
/// `supabase/leaderboard.sql` + `supabase/live_stream_reactions.sql`) —
/// keep them in sync if you tune the economy.
///
/// Going live itself isn't rewarded (that'd be gameable) — points come from
/// viewers engaging with the stream via reactions. One unique reacting
/// viewer per stream = one reaction point, regardless of how many hearts
/// they tap. Prevents a single alt-account from farming.
enum LeaderboardPoints {
    static let post = 25
    static let checkIn = 10
    static let commentReceived = 5
    static let likeReceived = 2
    static let reactionReceived = 3
}

enum LeaderboardWindow: String, CaseIterable, Identifiable {
    case last7Days
    case last30Days
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last7Days:  return "Last 7 days"
        case .last30Days: return "Last 30 days"
        case .allTime:    return "All time"
        }
    }

    /// Days passed to the Postgres function. 0 → all time.
    var windowDays: Int {
        switch self {
        case .last7Days:  return 7
        case .last30Days: return 30
        case .allTime:    return 0
        }
    }
}

/// One row on the leaderboard. Decoded from `public.get_leaderboard(...)`.
///
/// Numeric counts are decoded tolerantly: if the Postgres function hasn't been
/// migrated yet (e.g. a new column wasn't added), the missing field defaults
/// to 0 instead of failing the whole response. This avoids breaking the UI
/// during schema evolution.
struct LeaderboardEntry: Identifiable, Decodable, Hashable {
    let userId: String
    let username: String?
    let displayName: String?
    let avatarUrlString: String?
    let points: Int
    let postCount: Int
    let checkinCount: Int
    let likesReceived: Int
    let commentsReceived: Int
    let reactionsReceived: Int

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarUrlString = "avatar_url"
        case points
        case postCount = "post_count"
        case checkinCount = "checkin_count"
        case likesReceived = "likes_received"
        case commentsReceived = "comments_received"
        case reactionsReceived = "reactions_received"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrlString = try c.decodeIfPresent(String.self, forKey: .avatarUrlString)
        points = (try? c.decode(Int.self, forKey: .points)) ?? 0
        postCount = (try? c.decode(Int.self, forKey: .postCount)) ?? 0
        checkinCount = (try? c.decode(Int.self, forKey: .checkinCount)) ?? 0
        likesReceived = (try? c.decode(Int.self, forKey: .likesReceived)) ?? 0
        commentsReceived = (try? c.decode(Int.self, forKey: .commentsReceived)) ?? 0
        reactionsReceived = (try? c.decode(Int.self, forKey: .reactionsReceived)) ?? 0
    }

    var avatarURL: URL? {
        guard let avatarUrlString, !avatarUrlString.isEmpty else { return nil }
        return URL(string: avatarUrlString)
    }

    /// Human-readable display name with @username fallback, then "Anonymous".
    var resolvedDisplayName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return "@\(username)" }
        return "Anonymous"
    }

    var resolvedHandle: String? {
        guard let username, !username.isEmpty else { return nil }
        return "@\(username)"
    }
}

@MainActor
final class LeaderboardService {
    static let shared = LeaderboardService()

    private let client = SupabaseManager.shared.client

    // Simple in-memory cache keyed on window. Leaderboard is inexpensive to
    // re-fetch but people flip tabs rapidly — this avoids a round-trip per tap.
    private struct CacheEntry {
        let entries: [LeaderboardEntry]
        let fetchedAt: Date
    }
    private var cache: [LeaderboardWindow: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 30

    private init() {}

    private struct RPCParams: Encodable {
        let window_days: Int
        let limit_n: Int
    }

    /// Fetch the top N users for a given window. Returns cached results if
    /// they're < cacheTTL old unless `forceRefresh` is set.
    func fetchLeaderboard(
        window: LeaderboardWindow,
        limit: Int = 100,
        forceRefresh: Bool = false
    ) async throws -> [LeaderboardEntry] {
        if !forceRefresh,
           let cached = cache[window],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.entries
        }

        let params = RPCParams(window_days: window.windowDays, limit_n: limit)
        let response = try await client
            .rpc("get_leaderboard", params: params)
            .execute()

        let entries = try JSONDecoder().decode([LeaderboardEntry].self, from: response.data)
        cache[window] = CacheEntry(entries: entries, fetchedAt: Date())
        return entries
    }

    /// Look up where the current user sits if they aren't in the top N.
    /// Cheap: scans the already-fetched list, no extra network call.
    func rank(for userId: String, in entries: [LeaderboardEntry]) -> Int? {
        guard let index = entries.firstIndex(where: { $0.userId.lowercased() == userId.lowercased() }) else {
            return nil
        }
        return index + 1
    }

    func invalidateCache() {
        cache.removeAll()
    }
}
