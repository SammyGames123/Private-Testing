import Foundation
import Supabase

enum StorageURLBuilder {
    static func transformedAvatarURL(userId: String, avatarUrlString: String?, size: Int = 128) -> URL? {
        guard let avatarUrlString, !avatarUrlString.isEmpty else { return nil }
        return URL(string: avatarUrlString)
    }
}

struct UserProfile: Identifiable, Decodable, Hashable {
    let id: String
    let email: String?
    let username: String?
    let displayName: String?
    let avatarUrlString: String?
    let bio: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case username
        case displayName = "display_name"
        case avatarUrlString = "avatar_url"
        case bio
    }

    var avatarURL: URL? {
        optimizedAvatarURL(size: 192)
    }

    func optimizedAvatarURL(size: Int = 128) -> URL? {
        StorageURLBuilder.transformedAvatarURL(
            userId: id,
            avatarUrlString: avatarUrlString,
            size: size
        )
    }

    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return username }
        if let email, !email.isEmpty { return email }
        return "Creator"
    }

    var handle: String {
        if let username, !username.isEmpty {
            return "@\(username)"
        }
        if let email, !email.isEmpty {
            return email
        }
        return "@creator"
    }

    var initial: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

enum ProfileServiceError: LocalizedError {
    case missingUsername
    case avatarUploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingUsername:
            return "Please provide a username or display name."
        case .avatarUploadFailed(let message):
            return "Avatar upload failed: \(message)"
        }
    }
}

actor FeedServiceCache {
    struct Entry<Value> {
        let value: Value
        let expirationDate: Date
    }

    private var feedByLimit: [Int: Entry<[FeedVideo]>] = [:]
    private var profileByUserId: [String: Entry<UserProfile?>] = [:]
    private var postsByUserId: [String: Entry<[FeedVideo]>] = [:]
    private var statsByUserId: [String: Entry<ProfileStats>] = [:]
    private var creatorsByKey: [String: Entry<[UserProfile]>] = [:]
    private var likedVideoIdsByUserId: [String: Entry<Set<String>>] = [:]
    private var followedCreatorIdsByUserId: [String: Entry<Set<String>>] = [:]
    private var commentsByVideoId: [String: Entry<[FeedComment]>] = [:]
    private var relatedVideosByKey: [String: Entry<[FeedVideo]>] = [:]
    private var inboxThreadsByUserId: [String: Entry<[InboxThread]>] = [:]
    private var conversationMessagesByThreadId: [String: Entry<[ConversationMessage]>] = [:]
    private var venuesEntry: Entry<[Venue]>?
    private var pulseSnapshotByKey: [String: Entry<PulseSnapshot>] = [:]
    private var activeLiveStreamsEntry: Entry<[LiveStream]>?
    private var mapMomentsEntry: Entry<[MapMoment]>?

    func feed(limit: Int) -> [FeedVideo]? {
        valueIfFresh(feedByLimit[limit])
    }

    func storeFeed(_ videos: [FeedVideo], limit: Int, ttl: TimeInterval) {
        feedByLimit[limit] = makeEntry(videos, ttl: ttl)
    }

    func profile(userId: String) -> UserProfile?? {
        guard let entry = profileByUserId[userId], entry.expirationDate > Date() else {
            return nil
        }
        return entry.value
    }

    func storeProfile(_ profile: UserProfile?, userId: String, ttl: TimeInterval) {
        profileByUserId[userId] = makeEntry(profile, ttl: ttl)
    }

    func posts(userId: String) -> [FeedVideo]? {
        valueIfFresh(postsByUserId[userId])
    }

    func storePosts(_ videos: [FeedVideo], userId: String, ttl: TimeInterval) {
        postsByUserId[userId] = makeEntry(videos, ttl: ttl)
    }

    func stats(userId: String) -> ProfileStats? {
        valueIfFresh(statsByUserId[userId])
    }

    func storeStats(_ stats: ProfileStats, userId: String, ttl: TimeInterval) {
        statsByUserId[userId] = makeEntry(stats, ttl: ttl)
    }

    func creators(key: String) -> [UserProfile]? {
        valueIfFresh(creatorsByKey[key])
    }

    func storeCreators(_ creators: [UserProfile], key: String, ttl: TimeInterval) {
        creatorsByKey[key] = makeEntry(creators, ttl: ttl)
    }

    func likedVideoIds(userId: String) -> Set<String>? {
        valueIfFresh(likedVideoIdsByUserId[userId])
    }

    func storeLikedVideoIds(_ videoIds: Set<String>, userId: String, ttl: TimeInterval) {
        likedVideoIdsByUserId[userId] = makeEntry(videoIds, ttl: ttl)
    }

    func updateLikedState(userId: String, videoId: String, isLiked: Bool, ttl: TimeInterval) {
        guard let existing = likedVideoIds(userId: userId) else { return }
        var next = existing
        if isLiked {
            next.insert(videoId)
        } else {
            next.remove(videoId)
        }
        storeLikedVideoIds(next, userId: userId, ttl: ttl)
    }

    func followedCreatorIds(userId: String) -> Set<String>? {
        valueIfFresh(followedCreatorIdsByUserId[userId])
    }

    func storeFollowedCreatorIds(_ creatorIds: Set<String>, userId: String, ttl: TimeInterval) {
        followedCreatorIdsByUserId[userId] = makeEntry(creatorIds, ttl: ttl)
    }

    func updateFollowState(userId: String, creatorId: String, isFollowing: Bool, ttl: TimeInterval) {
        guard let existing = followedCreatorIds(userId: userId) else { return }
        var next = existing
        if isFollowing {
            next.insert(creatorId)
        } else {
            next.remove(creatorId)
        }
        storeFollowedCreatorIds(next, userId: userId, ttl: ttl)
    }

    func comments(videoId: String) -> [FeedComment]? {
        valueIfFresh(commentsByVideoId[videoId])
    }

    func storeComments(_ comments: [FeedComment], videoId: String, ttl: TimeInterval) {
        commentsByVideoId[videoId] = makeEntry(comments, ttl: ttl)
    }

    func appendComment(_ comment: FeedComment, videoId: String, ttl: TimeInterval) {
        let nextComments = (comments(videoId: videoId) ?? []) + [comment]
        storeComments(nextComments, videoId: videoId, ttl: ttl)
    }

    func relatedVideos(key: String) -> [FeedVideo]? {
        valueIfFresh(relatedVideosByKey[key])
    }

    func storeRelatedVideos(_ videos: [FeedVideo], key: String, ttl: TimeInterval) {
        relatedVideosByKey[key] = makeEntry(videos, ttl: ttl)
    }

    func inboxThreads(userId: String) -> [InboxThread]? {
        valueIfFresh(inboxThreadsByUserId[userId])
    }

    func storeInboxThreads(_ threads: [InboxThread], userId: String, ttl: TimeInterval) {
        inboxThreadsByUserId[userId] = makeEntry(threads, ttl: ttl)
    }

    func conversationMessages(threadId: String) -> [ConversationMessage]? {
        valueIfFresh(conversationMessagesByThreadId[threadId])
    }

    func storeConversationMessages(_ messages: [ConversationMessage], threadId: String, ttl: TimeInterval) {
        conversationMessagesByThreadId[threadId] = makeEntry(messages, ttl: ttl)
    }

    func appendConversationMessage(_ message: ConversationMessage, threadId: String, ttl: TimeInterval) {
        let nextMessages = (conversationMessages(threadId: threadId) ?? []) + [message]
        storeConversationMessages(nextMessages, threadId: threadId, ttl: ttl)
    }

    func venues() -> [Venue]? {
        valueIfFresh(venuesEntry)
    }

    func storeVenues(_ venues: [Venue], ttl: TimeInterval) {
        venuesEntry = makeEntry(venues, ttl: ttl)
    }

    func pulseSnapshot(key: String) -> PulseSnapshot? {
        valueIfFresh(pulseSnapshotByKey[key])
    }

    func storePulseSnapshot(_ snapshot: PulseSnapshot, key: String, ttl: TimeInterval) {
        pulseSnapshotByKey[key] = makeEntry(snapshot, ttl: ttl)
    }

    func activeLiveStreams() -> [LiveStream]? {
        valueIfFresh(activeLiveStreamsEntry)
    }

    func storeActiveLiveStreams(_ streams: [LiveStream], ttl: TimeInterval) {
        activeLiveStreamsEntry = makeEntry(streams, ttl: ttl)
    }

    func mapMoments() -> [MapMoment]? {
        valueIfFresh(mapMomentsEntry)
    }

    func storeMapMoments(_ moments: [MapMoment], ttl: TimeInterval) {
        mapMomentsEntry = makeEntry(moments, ttl: ttl)
    }

    func invalidateFeed() {
        feedByLimit.removeAll()
        relatedVideosByKey.removeAll()
        mapMomentsEntry = nil
    }

    func invalidateProfile(userId: String) {
        profileByUserId[userId] = nil
        postsByUserId[userId] = nil
        statsByUserId[userId] = nil
    }

    func invalidateCreatorLists() {
        creatorsByKey.removeAll()
    }

    func invalidateComments(videoId: String) {
        commentsByVideoId[videoId] = nil
    }

    func invalidateInbox(userId: String) {
        inboxThreadsByUserId[userId] = nil
    }

    func invalidateConversation(threadId: String) {
        conversationMessagesByThreadId[threadId] = nil
    }

    func invalidatePulse() {
        venuesEntry = nil
        pulseSnapshotByKey.removeAll()
        mapMomentsEntry = nil
    }

    func invalidateLiveStreams() {
        activeLiveStreamsEntry = nil
    }

    private func valueIfFresh<Value>(_ entry: Entry<Value>?) -> Value? {
        guard let entry, entry.expirationDate > Date() else { return nil }
        return entry.value
    }

    private func makeEntry<Value>(_ value: Value, ttl: TimeInterval) -> Entry<Value> {
        Entry(value: value, expirationDate: Date().addingTimeInterval(ttl))
    }
}

/// Wrapper around the Supabase tables backing the home feed.
final class FeedService {
    static let shared = FeedService()

    private static let mapMomentCacheTTL: TimeInterval = 10

    static let feedVideoSelect = """
        id,
        title,
        caption,
        category,
        venue_id,
        playback_url,
        thumbnail_url,
        created_at,
        creator_id,
        latitude,
        longitude,
        map_visibility,
        is_pinned,
        is_archived,
        profiles:creator_id (username, display_name, avatar_url),
        venues:venue_id (
            id,
            slug,
            name,
            area,
            city,
            category,
            vibe_blurb,
            launch_priority,
            is_active,
            precinct_id,
            address,
            google_place_id,
            google_place_name,
            google_last_synced_at,
            price_level,
            nightlife_score,
            featured,
            latitude,
            longitude
        ),
        likes (count),
        comments (count)
        """
    static let profileSelect = "id, username, display_name, avatar_url, bio"
    static let creatorSearchSelect = "id, username, display_name, avatar_url, bio"
    static let commentAuthorSelect = """
        id,
        username,
        display_name,
        avatar_url
        """
    static let venueSelect = """
        id,
        slug,
        name,
        area,
        city,
        category,
        vibe_blurb,
        launch_priority,
        is_active,
        precinct_id,
        address,
        google_place_id,
        google_place_name,
        google_last_synced_at,
        price_level,
        nightlife_score,
        featured,
        latitude,
        longitude
        """
    static let checkInSelect = """
        id,
        user_id,
        venue_id,
        vibe_emoji,
        note,
        latitude,
        longitude,
        checked_out_at,
        created_at,
        profiles:user_id (
            \(FeedService.profileSelect)
        ),
        venues:venue_id (
            \(FeedService.venueSelect)
        )
        """
    static let liveStreamSelect = """
        id,
        creator_id,
        venue_id,
        title,
        status,
        provider,
        provider_stream_id,
        ingest_url,
        stream_key,
        playback_url,
        thumbnail_url,
        viewer_count,
        requires_geo_verification,
        started_at,
        ended_at,
        last_heartbeat_at,
        profiles:creator_id (
            \(FeedService.profileSelect)
        ),
        venues:venue_id (
            \(FeedService.venueSelect)
        )
        """
    static let likedVideoIdsCacheTTL: TimeInterval = 30
    static let followedCreatorIdsCacheTTL: TimeInterval = 30
    static let feedCacheTTL: TimeInterval = 20
    static let pulseCacheTTL: TimeInterval = 20
    static let profileCacheTTL: TimeInterval = 60
    static let creatorsCacheTTL: TimeInterval = 120
    static let commentsCacheTTL: TimeInterval = 20
    static let inboxCacheTTL: TimeInterval = 20
    static let conversationCacheTTL: TimeInterval = 20
    static let venueCacheTTL: TimeInterval = 600
    static let launchVenueFetchLimit = 250

    let client = SupabaseManager.shared.client
    let cache = FeedServiceCache()

    private init() {}

    // MARK: - Feed fetch

    func fetchFeed(limit: Int = 24) async throws -> [FeedVideo] {
        if let cachedVideos = await cache.feed(limit: limit) {
            return cachedVideos
        }

        // Pull a slightly larger page than `limit` so blocked-user filtering
        // doesn't leave a gap. A user with 5% of the feed blocked will still
        // see close to `limit` cards after filtering.
        let overfetchLimit = max(limit + 8, Int(Double(limit) * 1.25))

        let videos: [FeedVideo] = try await client
            .from("videos")
            .select(Self.feedVideoSelect)
            .eq("visibility", value: "public")
            .eq("is_archived", value: false)
            .order("created_at", ascending: false)
            .limit(overfetchLimit)
            .execute()
            .value

        let blocked = await SafetyService.shared.blockedUserIds
        let filteredVideos = videos
            .filter { $0.playbackURL != nil }
            .filter { !blocked.contains($0.creatorId.lowercased()) }
            .prefix(limit)
            .map { $0 }

        await cache.storeFeed(filteredVideos, limit: limit, ttl: Self.feedCacheTTL)
        return filteredVideos
    }

    func fetchCurrentProfile(userId: String) async throws -> UserProfile? {
        let normalizedUserId = userId.lowercased()
        if let cachedProfile = await cache.profile(userId: normalizedUserId) {
            return cachedProfile
        }

        let rows: [UserProfile] = try await client
            .from("profiles")
            .select(Self.profileSelect)
            .eq("id", value: normalizedUserId)
            .limit(1)
            .execute()
            .value

        let profile = rows.first
        await cache.storeProfile(profile, userId: normalizedUserId, ttl: Self.profileCacheTTL)
        return profile
    }

    func fetchPostsForCurrentUser(userId: String) async throws -> [FeedVideo] {
        let normalizedUserId = userId.lowercased()
        if let cachedVideos = await cache.posts(userId: normalizedUserId) {
            return cachedVideos
        }

        let videos: [FeedVideo] = try await client
            .from("videos")
            .select(Self.feedVideoSelect)
            .eq("creator_id", value: normalizedUserId)
            .order("is_pinned", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value

        let filteredVideos = videos.filter { $0.playbackURL != nil }
        await cache.storePosts(filteredVideos, userId: normalizedUserId, ttl: Self.profileCacheTTL)
        return filteredVideos
    }

    func updateCurrentProfile(
        userId: String,
        email: String?,
        displayName: String,
        usernameInput: String,
        bio: String,
        avatarJPEGData: Data?,
        existingAvatarUrlString: String?
    ) async throws -> UserProfile {
        let username = Self.slugifyUsername(usernameInput.isEmpty ? (displayName.isEmpty ? (email ?? "") : displayName) : usernameInput)
        guard !username.isEmpty else { throw ProfileServiceError.missingUsername }

        let avatarUrlString: String?
        if let avatarJPEGData {
            avatarUrlString = try await uploadProfileAvatar(userId: userId, jpegData: avatarJPEGData)
        } else {
            avatarUrlString = existingAvatarUrlString
        }

        struct ProfileUpdate: Encodable {
            let display_name: String
            let username: String
            let bio: String?
            let email: String?
            let avatar_url: String?
        }

        let updatedProfile: UserProfile = try await client
            .from("profiles")
            .update(
                ProfileUpdate(
                    display_name: displayName.isEmpty ? username : displayName,
                    username: username,
                    bio: bio.isEmpty ? nil : bio,
                    email: email,
                    avatar_url: avatarUrlString
                ),
                returning: .representation
            )
            .eq("id", value: userId)
            .select(Self.profileSelect)
            .single()
            .execute()
            .value

        await cache.invalidateFeed()
        await cache.invalidateProfile(userId: userId)
        await cache.invalidateCreatorLists()
        await cache.invalidateInbox(userId: userId)
        await cache.storeProfile(updatedProfile, userId: userId, ttl: Self.profileCacheTTL)
        return updatedProfile
    }

    /// Returns the set of video_ids the current user has liked. Empty
    /// set if signed out.
    func fetchMyLikedVideoIds(userId: String) async throws -> Set<String> {
        let normalizedUserId = userId.lowercased()
        if let cachedIds = await cache.likedVideoIds(userId: normalizedUserId) {
            return cachedIds
        }

        struct Row: Decodable { let video_id: String }
        let rows: [Row] = try await client
            .from("likes")
            .select("video_id")
            .eq("user_id", value: normalizedUserId)
            .execute()
            .value

        let ids = Set(rows.map(\.video_id))
        await cache.storeLikedVideoIds(ids, userId: normalizedUserId, ttl: Self.likedVideoIdsCacheTTL)
        return ids
    }

    /// Returns the set of creator_ids the current user follows.
    func fetchMyFollowedCreatorIds(userId: String) async throws -> Set<String> {
        let normalizedUserId = userId.lowercased()
        if let cachedIds = await cache.followedCreatorIds(userId: normalizedUserId) {
            return cachedIds
        }

        struct Row: Decodable { let following_id: String }
        let rows: [Row] = try await client
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: normalizedUserId)
            .execute()
            .value

        let ids = Set(rows.map(\.following_id))
        await cache.storeFollowedCreatorIds(ids, userId: normalizedUserId, ttl: Self.followedCreatorIdsCacheTTL)
        return ids
    }

    func fetchLaunchVenues(limit: Int = FeedService.launchVenueFetchLimit) async throws -> [Venue] {
        if let cachedVenues = await cache.venues() {
            return Array(cachedVenues.prefix(limit))
        }

        let rawVenues: [Venue] = try await client
            .from("venues")
            .select(Self.venueSelect)
            .eq("is_active", value: true)
            .order("launch_priority", ascending: false)
            .order("name", ascending: true)
            .limit(limit)
            .execute()
            .value

        let venues = Self.deduplicateVenues(rawVenues)
        await cache.storeVenues(venues, ttl: Self.venueCacheTTL)
        return venues
    }

    func fetchActiveLiveStreams(limit: Int = 12, forceRefresh: Bool = false) async throws -> [LiveStream] {
        if forceRefresh {
            await cache.invalidateLiveStreams()
        } else if let cachedStreams = await cache.activeLiveStreams() {
            return Array(cachedStreams.prefix(limit))
        }

        do {
            let streams: [LiveStream] = try await client
                .from("live_streams")
                .select(Self.liveStreamSelect)
                .eq("status", value: LiveStreamStatus.live.rawValue)
                .is("ended_at", value: nil)
                .order("started_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            await cache.storeActiveLiveStreams(streams, ttl: Self.pulseCacheTTL)
            return streams
        } catch {
            if Self.isMissingLiveStreamsRelation(error) {
                await cache.storeActiveLiveStreams([], ttl: Self.pulseCacheTTL)
                return []
            }
            throw error
        }
    }

    func fetchActiveLiveStream(venueId: String) async throws -> LiveStream? {
        let streams = try await fetchActiveLiveStreams(limit: 24)
        return streams.first(where: { $0.venueId == venueId && $0.isLive })
    }

    func fetchActiveLiveStream(creatorId: String) async throws -> LiveStream? {
        let normalizedCreatorId = creatorId.lowercased()
        let streams = try await fetchActiveLiveStreams(limit: 24)
        return streams.first(where: { $0.creatorId.lowercased() == normalizedCreatorId && $0.isLive })
    }

    func createLiveStream(
        userId: String,
        venueId: String?,
        title: String,
        requiresGeoVerification: Bool
    ) async throws -> LiveStream {
        struct Insert: Encodable {
            let id: String
            let creator_id: String
            let venue_id: String?
            let title: String
            let status: String
            let provider: String
            let provider_stream_id: String
            let requires_geo_verification: Bool
            let started_at: String
            let last_heartbeat_at: String
        }

        let normalizedUserId = userId.lowercased()
        let streamId = UUID().uuidString.lowercased()
        let roomName = "spilltop-live-\(streamId)"
        let nowTimestamp = Self.iso8601Timestamp(for: Date())

        do {
            try await endCreatorLiveStreams(
                userId: normalizedUserId,
                endedAt: nowTimestamp
            )

            let stream: LiveStream = try await client
                .from("live_streams")
                .insert(
                    Insert(
                        id: streamId,
                        creator_id: normalizedUserId,
                        venue_id: venueId,
                        title: title,
                        status: LiveStreamStatus.live.rawValue,
                        provider: "livekit",
                        provider_stream_id: roomName,
                        requires_geo_verification: requiresGeoVerification,
                        started_at: nowTimestamp,
                        last_heartbeat_at: nowTimestamp
                    ),
                    returning: .representation
                )
                .select(Self.liveStreamSelect)
                .single()
                .execute()
                .value

            await cache.invalidateLiveStreams()
            await cache.invalidatePulse()
            return stream
        } catch {
            if let liveError = error as? LiveStreamServiceError {
                throw liveError
            }
            if Self.isMissingLiveStreamsRelation(error) {
                throw LiveStreamServiceError.backendNotReady
            }
            throw LiveStreamServiceError.couldNotStart(error.localizedDescription)
        }
    }

    func endLiveStream(streamId: String, userId: String) async throws -> LiveStream {
        struct Update: Encodable {
            let status: String
            let ended_at: String
            let last_heartbeat_at: String
        }

        let endedAt = Self.iso8601Timestamp(for: Date())

        do {
            try await client
                .from("live_streams")
                .update(
                    Update(
                        status: LiveStreamStatus.ended.rawValue,
                        ended_at: endedAt,
                        last_heartbeat_at: endedAt
                    ),
                    returning: .minimal
                )
                .eq("id", value: streamId)
                .eq("creator_id", value: userId.lowercased())
                .is("ended_at", value: nil)
                .execute()

            guard let stream = try await fetchLiveStream(streamId: streamId, userId: userId) else {
                throw LiveStreamServiceError.couldNotEnd("The live session was not found after ending it.")
            }

            await cache.invalidateLiveStreams()
            await cache.invalidatePulse()
            return stream
        } catch {
            if let liveError = error as? LiveStreamServiceError {
                throw liveError
            }
            if Self.isMissingLiveStreamsRelation(error) {
                throw LiveStreamServiceError.backendNotReady
            }
            throw LiveStreamServiceError.couldNotEnd(error.localizedDescription)
        }
    }

    func updateLiveViewerCount(streamId: String, userId: String, viewerCount: Int) async throws {
        struct Update: Encodable {
            let viewer_count: Int
            let last_heartbeat_at: String
        }

        let normalizedViewerCount = max(viewerCount, 0)
        let heartbeatAt = Self.iso8601Timestamp(for: Date())

        do {
            try await client
                .from("live_streams")
                .update(
                    Update(
                        viewer_count: normalizedViewerCount,
                        last_heartbeat_at: heartbeatAt
                    ),
                    returning: .minimal
                )
                .eq("id", value: streamId)
                .eq("creator_id", value: userId.lowercased())
                .is("ended_at", value: nil)
                .execute()

            await cache.invalidateLiveStreams()
            await cache.invalidatePulse()
        } catch {
            if Self.isMissingLiveStreamsRelation(error) {
                throw LiveStreamServiceError.backendNotReady
            }
            throw error
        }
    }

    func fetchRecentCheckIns(limit: Int = 120, sinceHours: Double = 12) async throws -> [NightlifeCheckIn] {
        let sinceDate = Date().addingTimeInterval(-(sinceHours * 60 * 60))
        let sinceTimestamp = Self.iso8601Timestamp(for: sinceDate)

        return try await client
            .from("check_ins")
            .select(Self.checkInSelect)
            .gte("created_at", value: sinceTimestamp)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func fetchActiveCheckIn(userId: String) async throws -> NightlifeCheckIn? {
        let rows: [NightlifeCheckIn] = try await client
            .from("check_ins")
            .select(Self.checkInSelect)
            .eq("user_id", value: userId.lowercased())
            .is("checked_out_at", value: nil)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    func fetchMoments(category: String, limit: Int = 12, sinceHours: Double = 24) async throws -> [FeedVideo] {
        let sinceDate = Date().addingTimeInterval(-(sinceHours * 60 * 60))
        let sinceTimestamp = Self.iso8601Timestamp(for: sinceDate)

        let videos: [FeedVideo] = try await client
            .from("videos")
            .select(Self.feedVideoSelect)
            .eq("visibility", value: "public")
            .eq("is_archived", value: false)
            .eq("category", value: category)
            .gte("created_at", value: sinceTimestamp)
            .order("is_pinned", ascending: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return videos.filter { $0.playbackURL != nil }
    }

    func fetchMapMoments(limit: Int = 120, forceRefresh: Bool = false) async throws -> [MapMoment] {
        if !forceRefresh, let cachedMoments = await cache.mapMoments() {
            return cachedMoments
        }

        struct Params: Encodable {
            let p_limit: Int
        }

        let moments: [MapMoment] = try await client
            .rpc("list_map_moments", params: Params(p_limit: limit))
            .execute()
            .value

        await cache.storeMapMoments(moments, ttl: Self.mapMomentCacheTTL)
        return moments
    }

    func fetchVenueMoments(venueId: String, limit: Int = 18, sinceHours: Double = 36) async throws -> [FeedVideo] {
        let cacheKey = "venue-moments:\(venueId.lowercased()):\(limit):\(Int(sinceHours.rounded()))"
        if let cachedVideos = await cache.relatedVideos(key: cacheKey) {
            return cachedVideos
        }

        let sinceDate = Date().addingTimeInterval(-(sinceHours * 60 * 60))
        let sinceTimestamp = Self.iso8601Timestamp(for: sinceDate)

        let videos: [FeedVideo] = try await client
            .from("videos")
            .select(Self.feedVideoSelect)
            .eq("visibility", value: "public")
            .eq("is_archived", value: false)
            .eq("venue_id", value: venueId)
            .gte("created_at", value: sinceTimestamp)
            .order("is_pinned", ascending: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let filteredVideos = videos.filter { $0.playbackURL != nil }
        await cache.storeRelatedVideos(filteredVideos, key: cacheKey, ttl: Self.feedCacheTTL)
        return filteredVideos
    }

    func fetchPulseSnapshot(currentUserId: String?, forceRefresh: Bool = false) async throws -> PulseSnapshot {
        let cacheKey = currentUserId?.lowercased() ?? "signed-out"

        if forceRefresh {
            await cache.invalidatePulse()
        } else if let cachedSnapshot = await cache.pulseSnapshot(key: cacheKey) {
            return cachedSnapshot
        }

        async let venuesTask = fetchLaunchVenues(limit: Self.launchVenueFetchLimit)
        async let recentCheckInsTask = fetchRecentCheckIns(limit: 120, sinceHours: 12)
        async let goingOutMomentsTask = fetchMoments(category: "going-out", limit: 14, sinceHours: 24)
        async let outNowMomentsTask = fetchMoments(category: "out-now", limit: 14, sinceHours: 16)
        async let followedUserIdsTask: Set<String> = {
            guard let currentUserId else { return [] }
            return (try? await fetchMyFollowedCreatorIds(userId: currentUserId)) ?? []
        }()

        let venues = try await venuesTask
        let recentCheckIns = try await recentCheckInsTask
        let goingOutMoments = try await goingOutMomentsTask
        let outNowMoments = try await outNowMomentsTask
        let followedUserIds = await followedUserIdsTask

        let snapshot = Self.buildPulseSnapshot(
            venues: venues,
            checkIns: recentCheckIns,
            goingOutMoments: goingOutMoments,
            outNowMoments: outNowMoments,
            followedUserIds: followedUserIds
        )
        await cache.storePulseSnapshot(snapshot, key: cacheKey, ttl: Self.pulseCacheTTL)
        return snapshot
    }

    func createCheckIn(
        userId: String,
        venueId: String,
        vibeEmoji: String?,
        note: String?,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async throws -> NightlifeCheckIn {
        struct Insert: Encodable {
            let user_id: String
            let venue_id: String
            let vibe_emoji: String?
            let note: String?
            let latitude: Double?
            let longitude: Double?
        }

        let trimmedVibe = vibeEmoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUserId = userId.lowercased()

        if let activeCheckIn = try await fetchActiveCheckIn(userId: normalizedUserId),
           activeCheckIn.venueId == venueId,
           Date().timeIntervalSince(PulseRelativeTimeFormatter.date(from: activeCheckIn.createdAt)) <= 90 {
            let updatedCheckIn = try await updateActiveCheckIn(
                checkInId: activeCheckIn.id,
                userId: normalizedUserId,
                vibeEmoji: trimmedVibe?.isEmpty == true ? nil : trimmedVibe,
                note: trimmedNote?.isEmpty == true ? nil : trimmedNote,
                latitude: latitude,
                longitude: longitude
            )
            await cache.invalidatePulse()
            return updatedCheckIn
        }

        try await closeActiveCheckIns(
            userId: normalizedUserId,
            checkedOutAt: Self.iso8601Timestamp(for: Date())
        )

        let insertedCheckIn: NightlifeCheckIn = try await client
            .from("check_ins")
            .insert(
                Insert(
                    user_id: normalizedUserId,
                    venue_id: venueId,
                    vibe_emoji: trimmedVibe?.isEmpty == true ? nil : trimmedVibe,
                    note: trimmedNote?.isEmpty == true ? nil : trimmedNote,
                    latitude: latitude,
                    longitude: longitude
                ),
                returning: .representation
            )
            .select(Self.checkInSelect)
            .single()
            .execute()
            .value

        await cache.invalidatePulse()
        return insertedCheckIn
    }

    func checkoutCheckIn(checkInId: String, userId: String) async throws -> NightlifeCheckIn {
        struct CheckoutUpdate: Encodable {
            let checked_out_at: String
        }

        let checkedOutAt = Self.iso8601Timestamp(for: Date())
        let checkedIn: NightlifeCheckIn = try await client
            .from("check_ins")
            .update(
                CheckoutUpdate(checked_out_at: checkedOutAt),
                returning: .representation
            )
            .eq("id", value: checkInId)
            .eq("user_id", value: userId.lowercased())
            .is("checked_out_at", value: nil)
            .select(Self.checkInSelect)
            .single()
            .execute()
            .value

        await cache.invalidatePulse()
        return checkedIn
    }

    private func endCreatorLiveStreams(
        userId: String,
        endedAt: String
    ) async throws {
        struct Update: Encodable {
            let status: String
            let ended_at: String
            let last_heartbeat_at: String
        }

        do {
            try await client
                .from("live_streams")
                .update(
                    Update(
                        status: LiveStreamStatus.ended.rawValue,
                        ended_at: endedAt,
                        last_heartbeat_at: endedAt
                    ),
                    returning: .minimal
                )
                .eq("creator_id", value: userId.lowercased())
                .is("ended_at", value: nil)
                .execute()
        } catch {
            if Self.isMissingLiveStreamsRelation(error) {
                throw LiveStreamServiceError.backendNotReady
            }
            throw error
        }
    }

    private func fetchLiveStream(streamId: String, userId: String) async throws -> LiveStream? {
        let normalizedUserId = userId.lowercased()
        let rows: [LiveStream] = try await client
            .from("live_streams")
            .select(Self.liveStreamSelect)
            .eq("id", value: streamId)
            .eq("creator_id", value: normalizedUserId)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    private func updateActiveCheckIn(
        checkInId: String,
        userId: String,
        vibeEmoji: String?,
        note: String?,
        latitude: Double?,
        longitude: Double?
    ) async throws -> NightlifeCheckIn {
        struct CheckInUpdate: Encodable {
            let vibe_emoji: String?
            let note: String?
            let latitude: Double?
            let longitude: Double?
        }

        return try await client
            .from("check_ins")
            .update(
                CheckInUpdate(
                    vibe_emoji: vibeEmoji,
                    note: note,
                    latitude: latitude,
                    longitude: longitude
                ),
                returning: .representation
            )
            .eq("id", value: checkInId)
            .eq("user_id", value: userId)
            .is("checked_out_at", value: nil)
            .select(Self.checkInSelect)
            .single()
            .execute()
            .value
    }

    private func closeActiveCheckIns(userId: String, checkedOutAt: String) async throws {
        struct CheckoutUpdate: Encodable {
            let checked_out_at: String
        }

        try await client
            .from("check_ins")
            .update(
                CheckoutUpdate(checked_out_at: checkedOutAt),
                returning: .minimal
            )
            .eq("user_id", value: userId)
            .is("checked_out_at", value: nil)
            .execute()
    }

    // MARK: - Mutations

    func like(videoId: String, userId: String) async throws {
        struct Insert: Encodable {
            let user_id: String
            let video_id: String
        }
        try await client
            .from("likes")
            .insert(
                Insert(user_id: userId.lowercased(), video_id: videoId),
                returning: .minimal
            )
            .execute()
        await cache.updateLikedState(
            userId: userId.lowercased(),
            videoId: videoId,
            isLiked: true,
            ttl: Self.likedVideoIdsCacheTTL
        )
    }

    func unlike(videoId: String, userId: String) async throws {
        try await client
            .from("likes")
            .delete(returning: .minimal)
            .eq("user_id", value: userId.lowercased())
            .eq("video_id", value: videoId)
            .execute()
        await cache.updateLikedState(
            userId: userId.lowercased(),
            videoId: videoId,
            isLiked: false,
            ttl: Self.likedVideoIdsCacheTTL
        )
    }

    func follow(creatorId: String, followerId: String) async throws {
        struct Insert: Encodable {
            let follower_id: String
            let following_id: String
        }
        try await client
            .from("follows")
            .insert(
                Insert(follower_id: followerId.lowercased(), following_id: creatorId.lowercased()),
                returning: .minimal
            )
            .execute()
        await cache.updateFollowState(
            userId: followerId.lowercased(),
            creatorId: creatorId.lowercased(),
            isFollowing: true,
            ttl: Self.followedCreatorIdsCacheTTL
        )
    }

    func unfollow(creatorId: String, followerId: String) async throws {
        try await client
            .from("follows")
            .delete(returning: .minimal)
            .eq("follower_id", value: followerId.lowercased())
            .eq("following_id", value: creatorId.lowercased())
            .execute()
        await cache.updateFollowState(
            userId: followerId.lowercased(),
            creatorId: creatorId.lowercased(),
            isFollowing: false,
            ttl: Self.followedCreatorIdsCacheTTL
        )
    }

    func invalidatePostCaches(creatorId: String) async {
        let normalizedUserId = creatorId.lowercased()
        await cache.invalidateFeed()
        await cache.invalidateProfile(userId: normalizedUserId)
        await cache.invalidateCreatorLists()
    }

    func invalidateCommentCaches(videoId: String) async {
        await cache.invalidateFeed()
        await cache.invalidateComments(videoId: videoId)
    }

    private static func buildPulseSnapshot(
        venues: [Venue],
        checkIns: [NightlifeCheckIn],
        goingOutMoments: [FeedVideo],
        outNowMoments: [FeedVideo],
        followedUserIds: Set<String>
    ) -> PulseSnapshot {
        // Already deduplicated upstream in fetchLaunchVenues; treat input as canonical.
        let canonicalVenues = venues
        let venuesById = Dictionary(uniqueKeysWithValues: canonicalVenues.map { ($0.id, $0) })
        let canonicalVenuesByKey = Dictionary(uniqueKeysWithValues: canonicalVenues.map { (canonicalVenueKey(for: $0), $0) })
        let canonicalizedCheckIns = checkIns.compactMap { checkIn in
            canonicalizedCheckIn(
                checkIn,
                canonicalVenuesByKey: canonicalVenuesByKey,
                canonicalVenuesById: venuesById
            )
        }
        let activeCheckIns = canonicalizedCheckIns.filter(\.isActive)
        let hotVenues = buildHotVenueSummaries(
            venues: canonicalVenues,
            checkIns: activeCheckIns,
            followedUserIds: followedUserIds
        )
        let summaryByVenueId = Dictionary(uniqueKeysWithValues: hotVenues.map { ($0.venue.id, $0) })
        let feedItems = (
            buildFriendMoveItems(
                checkIns: canonicalizedCheckIns,
                followedUserIds: followedUserIds,
                venuesById: venuesById,
                summaryByVenueId: summaryByVenueId
            ) +
            buildVenuePulseItems(
                summaries: hotVenues,
                checkIns: activeCheckIns,
                followedUserIds: followedUserIds
            )
        )
            .sorted { lhs, rhs in
                PulseRelativeTimeFormatter.date(from: lhs.createdAt) > PulseRelativeTimeFormatter.date(from: rhs.createdAt)
            }

        return PulseSnapshot(
            venues: canonicalVenues,
            recentCheckIns: activeCheckIns,
            hotVenues: hotVenues,
            feedItems: Array(feedItems.prefix(8)),
            goingOutMoments: goingOutMoments,
            outNowMoments: outNowMoments,
            recommendation: buildRecommendation(from: hotVenues)
        )
    }

    private static func buildHotVenueSummaries(
        venues: [Venue],
        checkIns: [NightlifeCheckIn],
        followedUserIds: Set<String>
    ) -> [HotVenueSummary] {
        let groupedByVenue = Dictionary(grouping: checkIns, by: \.venueId)
        let now = Date()

        return venues
            .map { venue in
                let venueCheckIns = (groupedByVenue[venue.id] ?? [])
                    .sorted {
                        PulseRelativeTimeFormatter.date(from: $0.createdAt) > PulseRelativeTimeFormatter.date(from: $1.createdAt)
                    }

                let uniquePeopleCount = Set(venueCheckIns.map(\.userId)).count
                let friendCount = Set(
                    venueCheckIns
                        .filter { followedUserIds.contains($0.userId) }
                        .map(\.userId)
                ).count
                let freshCheckIns = venueCheckIns.filter {
                    now.timeIntervalSince(PulseRelativeTimeFormatter.date(from: $0.createdAt)) <= 45 * 60
                }
                let momentumCount = freshCheckIns.count
                let recentUniquePeopleCount = Set(freshCheckIns.map(\.userId)).count
                let recentFriendCount = Set(
                    freshCheckIns
                        .filter { followedUserIds.contains($0.userId) }
                        .map(\.userId)
                ).count
                let hasFreshActivity = venueCheckIns.first.map {
                    now.timeIntervalSince(PulseRelativeTimeFormatter.date(from: $0.createdAt)) <= 45 * 60
                } ?? false
                let hasLiveCrowd = momentumCount >= 3 || recentUniquePeopleCount >= 3 || recentFriendCount >= 2
                let expectedSnapshot = expectedVenueSnapshot(
                    for: venue,
                    at: now
                )

                let activityScore = venueCheckIns.reduce(0.0) { partialResult, checkIn in
                    let ageMinutes = now.timeIntervalSince(PulseRelativeTimeFormatter.date(from: checkIn.createdAt)) / 60
                    return partialResult + recencyWeight(for: ageMinutes)
                }

                let liveScore = activityScore
                    + (Double(uniquePeopleCount) * 0.9)
                    + (Double(friendCount) * 2.4)
                    + (Double(momentumCount) * 0.85)

                let liveStatus: PulseVenueStatus
                if venueCheckIns.isEmpty {
                    liveStatus = .quiet
                } else if hasFreshActivity && hasLiveCrowd {
                    liveStatus = .hot
                } else if liveScore >= 3.2 || momentumCount >= 2 || uniquePeopleCount >= 3 || friendCount >= 1 {
                    liveStatus = .building
                } else {
                    liveStatus = .quiet
                }

                let confidence: PulseVenueSignalConfidence
                if hasFreshActivity && (momentumCount >= 2 || recentUniquePeopleCount >= 2 || recentFriendCount >= 1) {
                    confidence = .live
                } else if !venueCheckIns.isEmpty {
                    confidence = .blended
                } else {
                    confidence = .expected
                }

                let status: PulseVenueStatus
                switch confidence {
                case .live:
                    status = liveStatus
                case .blended:
                    status = liveStatus.intensityRank >= expectedSnapshot.status.intensityRank
                        ? liveStatus
                        : expectedSnapshot.status
                case .expected:
                    status = expectedSnapshot.status
                }

                let score = liveScore + expectedSnapshot.score

                return HotVenueSummary(
                    venue: venue,
                    score: score,
                    status: status,
                    liveStatus: liveStatus,
                    expectedStatus: expectedSnapshot.status,
                    confidence: confidence,
                    activityCount: venueCheckIns.count,
                    uniquePeopleCount: uniquePeopleCount,
                    friendCount: friendCount,
                    momentumCount: momentumCount,
                    recentVibes: Array(orderedUnique(venueCheckIns.compactMap(\.vibeEmoji)).prefix(4)),
                    latestCheckInAt: venueCheckIns.first?.createdAt
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return (lhs.venue.launchPriority ?? 0) > (rhs.venue.launchPriority ?? 0)
                }
                return lhs.score > rhs.score
            }
    }

    private static func buildVenuePulseItems(
        summaries: [HotVenueSummary],
        checkIns: [NightlifeCheckIn],
        followedUserIds: Set<String>
    ) -> [PulseFeedItem] {
        let now = Date()
        let recentCheckIns = checkIns.filter {
            now.timeIntervalSince(PulseRelativeTimeFormatter.date(from: $0.createdAt)) <= 90 * 60
        }
        let groupedByVenue = Dictionary(grouping: recentCheckIns, by: \.venueId)

        return summaries.compactMap { summary in
            guard let venueCheckIns = groupedByVenue[summary.venue.id], !venueCheckIns.isEmpty else {
                return nil
            }

            let sortedCheckIns = venueCheckIns.sorted {
                PulseRelativeTimeFormatter.date(from: $0.createdAt) > PulseRelativeTimeFormatter.date(from: $1.createdAt)
            }
            let uniquePeopleCount = Set(sortedCheckIns.map(\.userId)).count
            let friendNames = Array(
                orderedUnique(
                    sortedCheckIns
                        .filter { followedUserIds.contains($0.userId) }
                        .map(\.userName)
                )
                .prefix(3)
            )

            let title: String
            if friendNames.count >= 2 {
                title = "\(friendNames.count) friends are at \(summary.venue.name)"
            } else if uniquePeopleCount >= 2 {
                title = "\(uniquePeopleCount) people are at \(summary.venue.name)"
            } else if let firstCheckIn = sortedCheckIns.first {
                title = "\(firstCheckIn.userName) checked in at \(summary.venue.name)"
            } else {
                title = "\(summary.venue.name) is active"
            }

            let latestTimestamp = sortedCheckIns.first?.createdAt ?? summary.latestCheckInAt ?? iso8601Timestamp(for: now)
            let subtitle: String
            if summary.friendCount > 0 {
                subtitle = "\(summary.friendCount) friends there • \(PulseRelativeTimeFormatter.string(from: latestTimestamp))"
            } else if let vibeBlurb = summary.venue.vibeBlurb, !vibeBlurb.isEmpty {
                subtitle = "\(vibeBlurb) • \(PulseRelativeTimeFormatter.string(from: latestTimestamp))"
            } else {
                subtitle = "\(summary.venue.shortLocation) • \(PulseRelativeTimeFormatter.string(from: latestTimestamp))"
            }

            return PulseFeedItem(
                id: "venue-\(summary.venue.id)",
                style: .venuePulse,
                title: title,
                subtitle: subtitle,
                badge: summary.status.nightlifeBadgeTitle,
                venue: summary.venue,
                status: summary.status,
                createdAt: latestTimestamp,
                friendNames: friendNames,
                vibeEmojis: Array(orderedUnique(sortedCheckIns.compactMap(\.vibeEmoji)).prefix(4)),
                activityCount: uniquePeopleCount
            )
        }
    }

    private static func buildFriendMoveItems(
        checkIns: [NightlifeCheckIn],
        followedUserIds: Set<String>,
        venuesById: [String: Venue],
        summaryByVenueId: [String: HotVenueSummary]
    ) -> [PulseFeedItem] {
        guard !followedUserIds.isEmpty else { return [] }

        struct MoveEvent {
            let destinationVenue: Venue
            let fromVenueName: String?
            let friendName: String
            let createdAt: String
            let vibeEmoji: String?
        }

        let followedCheckIns = checkIns.filter { followedUserIds.contains($0.userId) }
        let groupedByUser = Dictionary(grouping: followedCheckIns, by: \.userId)
        let now = Date()

        var movesByDestination: [String: [MoveEvent]] = [:]

        for userCheckIns in groupedByUser.values {
            let sortedCheckIns = userCheckIns.sorted {
                PulseRelativeTimeFormatter.date(from: $0.createdAt) > PulseRelativeTimeFormatter.date(from: $1.createdAt)
            }
            guard let latestCheckIn = sortedCheckIns.first else { continue }
            guard now.timeIntervalSince(PulseRelativeTimeFormatter.date(from: latestCheckIn.createdAt)) <= 3 * 60 * 60 else {
                continue
            }
            guard let previousVenueCheckIn = sortedCheckIns.first(where: { $0.venueId != latestCheckIn.venueId }) else {
                continue
            }
            guard let destinationVenue = venuesById[latestCheckIn.venueId] ?? latestCheckIn.venue else {
                continue
            }

            let fromVenueName = (venuesById[previousVenueCheckIn.venueId] ?? previousVenueCheckIn.venue)?.name
            let event = MoveEvent(
                destinationVenue: destinationVenue,
                fromVenueName: fromVenueName,
                friendName: latestCheckIn.userName,
                createdAt: latestCheckIn.createdAt,
                vibeEmoji: latestCheckIn.vibeEmoji
            )
            movesByDestination[destinationVenue.id, default: []].append(event)
        }

        return movesByDestination.values
            .compactMap { moveEvents in
                guard let destinationVenue = moveEvents.first?.destinationVenue else { return nil }

                let friendNames = Array(orderedUnique(moveEvents.map(\.friendName)).prefix(3))
                guard !friendNames.isEmpty else { return nil }

                let latestTimestamp = moveEvents
                    .map(\.createdAt)
                    .max {
                        PulseRelativeTimeFormatter.date(from: $0) < PulseRelativeTimeFormatter.date(from: $1)
                    } ?? iso8601Timestamp(for: Date())
                let originNames = orderedUnique(moveEvents.compactMap(\.fromVenueName))
                let title = friendNames.count == 1
                    ? "\(friendNames[0]) moved to \(destinationVenue.name)"
                    : "\(friendNames.count) friends moved to \(destinationVenue.name)"
                let subtitle = originNames.isEmpty
                    ? "Your crew is shifting venues right now."
                    : "Moved over from \(originNames[0]) • \(PulseRelativeTimeFormatter.string(from: latestTimestamp))"

                return PulseFeedItem(
                    id: "move-\(destinationVenue.id)",
                    style: .friendMove,
                    title: title,
                    subtitle: subtitle,
                    badge: "Friends",
                    venue: destinationVenue,
                    status: summaryByVenueId[destinationVenue.id]?.status,
                    createdAt: latestTimestamp,
                    friendNames: friendNames,
                    vibeEmojis: Array(orderedUnique(moveEvents.compactMap(\.vibeEmoji)).prefix(3)),
                    activityCount: friendNames.count
                )
            }
            .sorted {
                PulseRelativeTimeFormatter.date(from: $0.createdAt) > PulseRelativeTimeFormatter.date(from: $1.createdAt)
            }
    }

    private static func buildRecommendation(from hotVenues: [HotVenueSummary]) -> PulseRecommendation? {
        guard let bestVenue = hotVenues.first(where: {
            $0.activityCount > 0 || $0.friendCount > 0 || $0.status != .quiet
        }) ?? hotVenues.first else {
            return nil
        }

        let title: String
        if bestVenue.friendCount > 0 {
            title = "Head to \(bestVenue.venue.name)"
        } else if bestVenue.status == .hot && bestVenue.confidence == .live {
            title = "\(bestVenue.venue.name) is busy now"
        } else if bestVenue.confidence == .expected {
            title = "\(bestVenue.venue.name) should be \(bestVenue.status.recommendationWord)"
        } else {
            title = "Start at \(bestVenue.venue.name)"
        }

        let subtitle: String
        if bestVenue.friendCount > 0 {
            subtitle = "\(bestVenue.friendCount) friends are there and the vibe is \(bestVenue.status.recommendationPhrase)."
        } else if bestVenue.momentumCount >= 3 {
            subtitle = "Momentum is building quickly in \(bestVenue.venue.area)."
        } else if bestVenue.confidence == .expected {
            subtitle = "\(bestVenue.expectedStatus.expectedHeadline) based on venue type and time tonight."
        } else if let vibeBlurb = bestVenue.venue.vibeBlurb, !vibeBlurb.isEmpty {
            subtitle = vibeBlurb
        } else {
            subtitle = "\(bestVenue.venue.shortLocation) looks best right now."
        }

        return PulseRecommendation(
            venue: bestVenue.venue,
            title: title,
            subtitle: subtitle,
            status: bestVenue.status
        )
    }

    private static func expectedVenueSnapshot(
        for venue: Venue,
        at date: Date
    ) -> (status: PulseVenueStatus, score: Double) {
        let family = expectedVenueFamily(for: venue)
        let status = expectedVenueStatus(for: family, hour: nightlifeHour(for: date))

        let score: Double
        switch status {
        case .hot:
            score = 4.0
        case .building:
            score = 2.5
        case .slowingDown:
            score = 1.25
        case .quiet:
            score = 0.25
        }

        return (status, score)
    }

    private static func deduplicateVenues(_ venues: [Venue]) -> [Venue] {
        Dictionary(grouping: venues, by: canonicalVenueKey(for:))
            .values
            .compactMap { group in
                group.sorted(by: venueDedupSort).first
            }
            .sorted { lhs, rhs in
                let leftPriority = lhs.launchPriority ?? 0
                let rightPriority = rhs.launchPriority ?? 0
                if leftPriority == rightPriority {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return leftPriority > rightPriority
            }
    }

    private static func canonicalizedCheckIn(
        _ checkIn: NightlifeCheckIn,
        canonicalVenuesByKey: [String: Venue],
        canonicalVenuesById: [String: Venue]
    ) -> NightlifeCheckIn? {
        if let venue = checkIn.venue {
            let key = canonicalVenueKey(for: venue)
            guard let canonicalVenue = canonicalVenuesByKey[key] else { return nil }
            return checkIn.canonicalized(venueId: canonicalVenue.id, venue: canonicalVenue)
        }

        guard let canonicalVenue = canonicalVenuesById[checkIn.venueId] else { return nil }
        return checkIn.canonicalized(venueId: canonicalVenue.id, venue: canonicalVenue)
    }

    private static func canonicalVenueKey(for venue: Venue) -> String {
        let slug = venue.slug.lowercased()

        if let canonicalSlug = canonicalVenueSlugAliases[slug] {
            return canonicalSlug
        }

        return slug
    }

    private static func venueDedupSort(lhs: Venue, rhs: Venue) -> Bool {
        if lhs.slug == canonicalVenueKey(for: lhs), rhs.slug != canonicalVenueKey(for: rhs) {
            return true
        }
        if rhs.slug == canonicalVenueKey(for: rhs), lhs.slug != canonicalVenueKey(for: lhs) {
            return false
        }

        let leftAddressScore = venueAddressSpecificityScore(lhs)
        let rightAddressScore = venueAddressSpecificityScore(rhs)
        if leftAddressScore != rightAddressScore {
            return leftAddressScore > rightAddressScore
        }

        if (lhs.featured ?? false) != (rhs.featured ?? false) {
            return (lhs.featured ?? false) && !(rhs.featured ?? false)
        }

        if (lhs.launchPriority ?? 0) != (rhs.launchPriority ?? 0) {
            return (lhs.launchPriority ?? 0) > (rhs.launchPriority ?? 0)
        }

        if (lhs.nightlifeScore ?? 0) != (rhs.nightlifeScore ?? 0) {
            return (lhs.nightlifeScore ?? 0) > (rhs.nightlifeScore ?? 0)
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func venueAddressSpecificityScore(_ venue: Venue) -> Int {
        let address = (venue.address ?? "").lowercased()
        if address.contains(" qld ") || address.contains("gold coast hwy") || address.contains("orchid ave") {
            return 2
        }
        if address.contains("surfers paradise")
            || address.contains("broadbeach")
            || address.contains("burleigh heads")
            || address.contains("southport")
        {
            return 1
        }
        return 0
    }

    private static let canonicalVenueSlugAliases: [String: String] = [
        "havana-rnb-nightclub": "havana-rnb",
        "the-bedroom": "bedroom-lounge-bar",
        "justin-lane-rooftop": "justin-lane",
        "the-avenue": "the-avenue-surfers",
        "retro-s": "retros",
        "retro-s-surfers-paradise": "retros",
    ]

    private static func nightlifeHour(for date: Date) -> Int {
        let calendar = Calendar.current
        var hour = calendar.component(.hour, from: date)

        if hour < 5 {
            hour += 24
        }

        return hour
    }

    private enum ExpectedVenueFamily {
        case nightclub
        case bar
        case dinnerRestaurant
    }

    private static func expectedVenueFamily(for venue: Venue) -> ExpectedVenueFamily {
        switch (venue.category ?? "").lowercased() {
        case "nightclub", "bar_club", "club_bar":
            return .nightclub
        case "restaurant_bar":
            return .dinnerRestaurant
        case "bar", "rooftop_bar", "beach_club", "pub", "live_music", "karaoke", "entertainment",
             "brewery_distillery", "nightlife_tour":
            return .bar
        default:
            return .bar
        }
    }

    private static func expectedVenueStatus(
        for family: ExpectedVenueFamily,
        hour: Int
    ) -> PulseVenueStatus {
        switch family {
        case .nightclub:
            switch hour {
            case 23..<27:
                return .hot
            case 20..<23:
                return .building
            default:
                return .quiet
            }
        case .bar:
            switch hour {
            case 20..<23:
                return .hot
            case 23..<25:
                return .slowingDown
            case 11..<20:
                return .building
            default:
                return .quiet
            }
        case .dinnerRestaurant:
            switch hour {
            case 17..<21:
                return .hot
            case 21..<23:
                return .slowingDown
            case 16..<17:
                return .building
            default:
                return .quiet
            }
        }
    }

    private static func recencyWeight(for ageMinutes: Double) -> Double {
        switch ageMinutes {
        case ..<30:
            return 2.4
        case ..<60:
            return 1.8
        case ..<120:
            return 1.1
        case ..<240:
            return 0.65
        case ..<480:
            return 0.3
        default:
            return 0.12
        }
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()

        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private static func iso8601Timestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func isMissingLiveStreamsRelation(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("live_streams")
            && (
                message.contains("does not exist")
                    || message.contains("schema cache")
                    || message.contains("could not find the table")
                    || message.contains("42p01")
            )
    }

    private static func slugifyUsername(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_]+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "^_+|_+$", with: "", options: .regularExpression)
            .prefix(24)
            .description
    }

    private func uploadProfileAvatar(userId: String, jpegData: Data) async throws -> String {
        let normalizedUserId = userId.lowercased()
        let path = "\(normalizedUserId)/avatar.jpg"

        do {
            _ = try await client.storage
                .from("avatars")
                .upload(
                    path,
                    data: jpegData,
                    options: FileOptions(
                        cacheControl: "31536000",
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )
        } catch {
            throw ProfileServiceError.avatarUploadFailed(error.localizedDescription)
        }

        let publicURL = try client.storage
            .from("avatars")
            .getPublicURL(path: path)

        var components = URLComponents(url: publicURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))")]
        return components?.url?.absoluteString ?? publicURL.absoluteString
    }
}
