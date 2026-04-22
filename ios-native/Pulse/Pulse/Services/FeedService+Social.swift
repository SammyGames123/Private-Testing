import Foundation
import Supabase

enum PostManagementError: LocalizedError {
    case missingTitle

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "Please add a title before saving this post."
        }
    }
}

enum SocialInputError: LocalizedError {
    case emptyComment
    case emptyMessage

    var errorDescription: String? {
        switch self {
        case .emptyComment:
            return "Please add a comment first."
        case .emptyMessage:
            return "Please add a message first."
        }
    }
}

extension FeedService {
    func fetchProfileStats(userId: String) async throws -> ProfileStats {
        let normalizedUserId = userId.lowercased()
        if let cachedStats = await cache.stats(userId: normalizedUserId) {
            return cachedStats
        }

        async let postsResponse = client
            .from("videos")
            .select("id", head: true, count: CountOption.exact)
            .eq("creator_id", value: normalizedUserId)
            .execute()

        async let followersResponse = client
            .from("follows")
            .select("follower_id", head: true, count: CountOption.exact)
            .eq("following_id", value: normalizedUserId)
            .execute()

        async let followingResponse = client
            .from("follows")
            .select("following_id", head: true, count: CountOption.exact)
            .eq("follower_id", value: normalizedUserId)
            .execute()

        let postsCount = try await postsResponse.count ?? 0
        let followersCount = try await followersResponse.count ?? 0
        let followingCount = try await followingResponse.count ?? 0

        let stats = ProfileStats(
            postsCount: postsCount,
            followersCount: followersCount,
            followingCount: followingCount
        )
        await cache.storeStats(stats, userId: normalizedUserId, ttl: Self.profileCacheTTL)
        return stats
    }

    func fetchComments(videoId: String) async throws -> [FeedComment] {
        let blockedIds = await SafetyService.shared.blockedUserIds

        if let cachedComments = await cache.comments(videoId: videoId) {
            return Self.filterBlockedComments(cachedComments, blockedIds: blockedIds)
        }

        let comments: [FeedComment] = try await client
            .from("comments")
            .select("""
                id,
                user_id,
                video_id,
                body,
                created_at,
                profiles:user_id (
                    \(Self.commentAuthorSelect)
                )
                """)
            .eq("video_id", value: videoId)
            .order("created_at", ascending: true)
            .execute()
            .value

        await cache.storeComments(comments, videoId: videoId, ttl: Self.commentsCacheTTL)
        return Self.filterBlockedComments(comments, blockedIds: blockedIds)
    }

    private static func filterBlockedComments(
        _ comments: [FeedComment],
        blockedIds: Set<String>
    ) -> [FeedComment] {
        guard !blockedIds.isEmpty else { return comments }
        return comments.filter { !blockedIds.contains($0.userId.lowercased()) }
    }

    func addComment(videoId: String, userId: String, body: String) async throws -> FeedComment {
        struct Insert: Encodable {
            let user_id: String
            let video_id: String
            let body: String
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { throw SocialInputError.emptyComment }
        try ContentPolicy.validateUserText(trimmedBody)

        let insertedComment: FeedComment = try await client
            .from("comments")
            .insert(
                Insert(
                    user_id: userId.lowercased(),
                    video_id: videoId,
                    body: trimmedBody
                ),
                returning: .representation
            )
            .select("""
                id,
                user_id,
                video_id,
                body,
                created_at,
                profiles:user_id (
                    \(Self.commentAuthorSelect)
                )
                """)
            .single()
            .execute()
            .value

        await cache.appendComment(insertedComment, videoId: videoId, ttl: Self.commentsCacheTTL)
        await cache.invalidateFeed()
        return insertedComment
    }

    func fetchTags(videoId: String) async throws -> [String] {
        struct TagRow: Decodable {
            let tag: String
        }

        let rows: [TagRow] = try await client
            .from("video_tags")
            .select("tag")
            .eq("video_id", value: videoId)
            .order("tag", ascending: true)
            .execute()
            .value

        return rows.map(\.tag)
    }

    func updatePostDetails(
        videoId: String,
        userId: String,
        title: String,
        caption: String,
        tagsInput: String?
    ) async throws {
        struct VideoUpdate: Encodable {
            let title: String
            let caption: String?
        }

        struct TagInsert: Encodable {
            let video_id: String
            let tag: String
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw PostManagementError.missingTitle }

        let normalizedUserId = userId.lowercased()
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        try ContentPolicy.validateUserText(trimmedTitle, trimmedCaption, tagsInput)

        try await client
            .from("videos")
            .update(
                VideoUpdate(
                    title: trimmedTitle,
                    caption: trimmedCaption.isEmpty ? nil : trimmedCaption
                ),
                returning: .minimal
            )
            .eq("id", value: videoId)
            .eq("creator_id", value: normalizedUserId)
            .execute()

        try await client
            .from("video_tags")
            .delete(returning: .minimal)
            .eq("video_id", value: videoId)
            .execute()

        let tags = Self.parseTags(tagsInput)
        guard !tags.isEmpty else {
            await invalidatePostCaches(creatorId: normalizedUserId)
            return
        }

        try await client
            .from("video_tags")
            .insert(tags.map { TagInsert(video_id: videoId, tag: $0) }, returning: .minimal)
            .execute()

        await invalidatePostCaches(creatorId: normalizedUserId)
    }

    func updatePostPinState(videoId: String, userId: String, isPinned: Bool) async throws {
        struct Update: Encodable {
            let is_pinned: Bool
        }

        try await client
            .from("videos")
            .update(Update(is_pinned: isPinned), returning: .minimal)
            .eq("id", value: videoId)
            .eq("creator_id", value: userId.lowercased())
            .execute()

        await invalidatePostCaches(creatorId: userId)
    }

    func updatePostArchiveState(videoId: String, userId: String, isArchived: Bool) async throws {
        struct Update: Encodable {
            let is_archived: Bool
        }

        try await client
            .from("videos")
            .update(Update(is_archived: isArchived), returning: .minimal)
            .eq("id", value: videoId)
            .eq("creator_id", value: userId.lowercased())
            .execute()

        await invalidatePostCaches(creatorId: userId)
    }

    func deletePost(videoId: String, userId: String) async throws {
        struct StorageRow: Decodable {
            let storage_path: String?
            let thumbnail_url: String?
        }

        let normalizedUserId = userId.lowercased()
        let matchingVideos: [StorageRow] = try await client
            .from("videos")
            .select("storage_path, thumbnail_url")
            .eq("id", value: videoId)
            .eq("creator_id", value: normalizedUserId)
            .limit(1)
            .execute()
            .value

        try await client
            .from("videos")
            .delete(returning: .minimal)
            .eq("id", value: videoId)
            .eq("creator_id", value: normalizedUserId)
            .execute()

        if let storagePath = matchingVideos.first?.storage_path, !storagePath.isEmpty {
            _ = try? await client.storage
                .from("videos")
                .remove(paths: [storagePath])
        }

        if let thumbnailPath = Self.storagePath(fromPublicURLString: matchingVideos.first?.thumbnail_url, bucketId: "videos"), !thumbnailPath.isEmpty {
            _ = try? await client.storage
                .from("videos")
                .remove(paths: [thumbnailPath])
        }

        await invalidatePostCaches(creatorId: normalizedUserId)
    }

    func fetchCreators(
        query: String? = nil,
        excluding userId: String? = nil,
        limit: Int = 24
    ) async throws -> [UserProfile] {
        let cacheKey = creatorsCacheKey(query: query, excluding: userId, limit: limit)
        if let cachedCreators = await cache.creators(key: cacheKey) {
            return cachedCreators
        }

        let request = client
            .from("profiles")
            .select(Self.creatorSearchSelect)

        if let userId, !userId.isEmpty {
            _ = request.neq("id", value: userId.lowercased())
        }

        if let query {
            let searchTerm = Self.sanitizedSearchTerm(query)
            if !searchTerm.isEmpty {
                let pattern = "%\(searchTerm)%"
                _ = request.or(
                    "username.ilike.\(pattern),display_name.ilike.\(pattern),bio.ilike.\(pattern)"
                )
            }
        }

        let rows: [UserProfile] = try await request
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        await cache.storeCreators(rows, key: cacheKey, ttl: Self.creatorsCacheTTL)
        return rows
    }

    /// Fetches a single post by id. Used when the user taps a shared
    /// post bubble in a DM. Returns nil if the post has been deleted or
    /// is not visible to the viewer under RLS.
    func fetchVideo(id: String) async throws -> FeedVideo? {
        let rows: [FeedVideo] = try await client
            .from("videos")
            .select(Self.feedVideoSelect)
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func fetchRelatedVideos(for seedVideo: FeedVideo, limit: Int = 24) async throws -> [FeedVideo] {
        let cacheKey = relatedVideosCacheKey(seedVideoId: seedVideo.id, limit: limit)
        if let cachedVideos = await cache.relatedVideos(key: cacheKey) {
            return cachedVideos
        }

        struct TagVideoRow: Decodable {
            let video_id: String
        }

        let maxResults = max(limit, 1)
        var orderedVideos: [FeedVideo] = [seedVideo]
        var seenVideoIds = Set([seedVideo.id])

        let creatorVideos: [FeedVideo] = try await client
            .from("videos")
            .select(Self.feedVideoSelect)
            .eq("creator_id", value: seedVideo.creatorId)
            .neq("id", value: seedVideo.id)
            .eq("visibility", value: "public")
            .eq("is_archived", value: false)
            .order("is_pinned", ascending: false)
            .order("created_at", ascending: false)
            .limit(maxResults)
            .execute()
            .value

        appendUniqueVideos(from: creatorVideos, to: &orderedVideos, seenVideoIds: &seenVideoIds, maxResults: maxResults)

        let tags = try await fetchTags(videoId: seedVideo.id)
        if !tags.isEmpty, orderedVideos.count < maxResults {
            let relatedTagRows: [TagVideoRow] = try await client
                .from("video_tags")
                .select("video_id")
                .in("tag", values: tags)
                .neq("video_id", value: seedVideo.id)
                .limit(maxResults * 3)
                .execute()
                .value

            let relatedTagIds = Array(NSOrderedSet(array: relatedTagRows.map(\.video_id))) as? [String] ?? []
            if !relatedTagIds.isEmpty {
                let taggedVideos: [FeedVideo] = try await client
                    .from("videos")
                    .select(Self.feedVideoSelect)
                    .in("id", values: relatedTagIds)
                    .eq("visibility", value: "public")
                    .eq("is_archived", value: false)
                    .order("created_at", ascending: false)
                    .limit(maxResults)
                    .execute()
                    .value

                let videosById = Dictionary(uniqueKeysWithValues: taggedVideos.map { ($0.id, $0) })
                let orderedTaggedVideos = relatedTagIds.compactMap { videosById[$0] }
                appendUniqueVideos(from: orderedTaggedVideos, to: &orderedVideos, seenVideoIds: &seenVideoIds, maxResults: maxResults)
            }
        }

        if let category = seedVideo.category, !category.isEmpty, orderedVideos.count < maxResults {
            let categoryVideos: [FeedVideo] = try await client
                .from("videos")
                .select(Self.feedVideoSelect)
                .eq("category", value: category)
                .neq("id", value: seedVideo.id)
                .eq("visibility", value: "public")
                .eq("is_archived", value: false)
                .order("created_at", ascending: false)
                .limit(maxResults)
                .execute()
                .value

            appendUniqueVideos(from: categoryVideos, to: &orderedVideos, seenVideoIds: &seenVideoIds, maxResults: maxResults)
        }

        if orderedVideos.count < maxResults {
            let fallbackVideos = try await fetchFeed(limit: maxResults * 2)
            appendUniqueVideos(from: fallbackVideos, to: &orderedVideos, seenVideoIds: &seenVideoIds, maxResults: maxResults)
        }

        await cache.storeRelatedVideos(orderedVideos, key: cacheKey, ttl: Self.feedCacheTTL)
        return orderedVideos
    }

    func isFollowing(currentUserId: String, targetUserId: String) async throws -> Bool {
        let response = try await client
            .from("follows")
            .select("following_id", head: true, count: CountOption.exact)
            .eq("follower_id", value: currentUserId.lowercased())
            .eq("following_id", value: targetUserId.lowercased())
            .execute()

        return (response.count ?? 0) > 0
    }

    func fetchInboxThreads(userId: String) async throws -> [InboxThread] {
        let normalizedUserId = userId.lowercased()
        if let cachedThreads = await cache.inboxThreads(userId: normalizedUserId) {
            return cachedThreads
        }

        struct ParticipantRow: Decodable {
            let thread_id: String
            let user_id: String
        }

        struct ThreadMetaRow: Decodable {
            let id: String
            let status: String?
            let created_by: String?
        }

        struct ThreadParticipantLookupRow: Decodable {
            let threadId: String
            let userId: String
            let profile: UserProfile?

            enum CodingKeys: String, CodingKey {
                case threadId = "thread_id"
                case userId = "user_id"
                case profiles
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                threadId = try container.decode(String.self, forKey: .threadId)
                userId = try container.decode(String.self, forKey: .userId)

                if let single = try? container.decodeIfPresent(UserProfile.self, forKey: .profiles) {
                    profile = single
                } else if let array = try? container.decodeIfPresent([UserProfile].self, forKey: .profiles) {
                    profile = array.first
                } else {
                    profile = nil
                }
            }
        }

        struct MessageRow: Decodable {
            let id: String
            let thread_id: String
            let sender_id: String
            let body: String
            let created_at: String
            let shared_video_id: String?
        }

        let participantRows: [ParticipantRow] = try await client
            .from("thread_participants")
            .select("thread_id, user_id")
            .eq("user_id", value: normalizedUserId)
            .execute()
            .value

        let threadIds = Array(Set(participantRows.map(\.thread_id)))
        guard !threadIds.isEmpty else { return [] }

        async let participantsTask: [ThreadParticipantLookupRow] = client
            .from("thread_participants")
            .select("""
                thread_id,
                user_id,
                profiles:user_id (
                    \(Self.commentAuthorSelect)
                )
                """)
            .in("thread_id", values: threadIds)
            .execute()
            .value

        async let messagesTask: [MessageRow] = client
            .from("messages")
            .select("id, thread_id, sender_id, body, created_at, shared_video_id")
            .in("thread_id", values: threadIds)
            .order("created_at", ascending: true)
            .execute()
            .value

        async let threadMetaTask: [ThreadMetaRow] = client
            .from("message_threads")
            .select("id, status, created_by")
            .in("id", values: threadIds)
            .execute()
            .value

        let participants = try await participantsTask
        let messages = try await messagesTask
        let threadMeta = try await threadMetaTask

        let messagesByThread = Dictionary(grouping: messages, by: \.thread_id)
        let metaByThread = Dictionary(uniqueKeysWithValues: threadMeta.map { ($0.id, $0) })

        let threads: [InboxThread] = threadIds.compactMap { (threadId: String) -> InboxThread? in
            let threadParticipants = participants.filter { $0.threadId == threadId }
            guard
                let otherParticipant = threadParticipants.first(where: { $0.userId != normalizedUserId })
            else {
                return nil
            }

            let latestMessage = messagesByThread[threadId]?.last
            let otherProfile = otherParticipant.profile
            let meta = metaByThread[threadId]

            let latestBody: String
            if let latestMessage {
                let trimmed = latestMessage.body.trimmingCharacters(in: .whitespacesAndNewlines)
                if latestMessage.shared_video_id != nil, trimmed.isEmpty {
                    latestBody = "Shared a post"
                } else if latestMessage.shared_video_id != nil {
                    latestBody = "\u{1F4CE} \(trimmed)" // 📎 so shares stand out in the row
                } else {
                    latestBody = trimmed.isEmpty ? "No messages yet." : trimmed
                }
            } else {
                latestBody = "No messages yet."
            }

            return InboxThread(
                id: threadId,
                otherUserId: otherParticipant.userId,
                otherUserName: otherProfile?.name ?? "Creator",
                otherUserHandle: otherProfile?.handle ?? "@creator",
                otherUserAvatarUrlString: otherProfile?.avatarUrlString,
                latestMessage: latestBody,
                latestMessageAt: latestMessage?.created_at ?? ISO8601DateFormatter().string(from: Date()),
                latestMessageSenderId: latestMessage?.sender_id.lowercased(),
                status: MessageThreadStatus(rawString: meta?.status),
                createdByUserId: meta?.created_by?.lowercased()
            )
        }
        .sorted { lhs, rhs in
            Self.parseISODate(lhs.latestMessageAt) > Self.parseISODate(rhs.latestMessageAt)
        }

        await cache.storeInboxThreads(threads, userId: normalizedUserId, ttl: Self.inboxCacheTTL)
        return threads
    }

    struct StartConversationResult {
        let threadId: String
        let status: MessageThreadStatus
    }

    /// Opens or re-opens the 1:1 thread with `targetUserId`. Calls the
    /// `start_or_get_thread` RPC on the server which owns the status
    /// decision — mutual follow → `accepted`, otherwise → `pending`. The
    /// returned status reflects the thread's current state (i.e. if a
    /// previously-pending thread has since been upgraded by mutual follow,
    /// it comes back as `accepted`).
    func startConversation(
        currentUserId: String,
        targetUserId: String
    ) async throws -> StartConversationResult {
        struct Params: Encodable {
            let target_user_id: String
        }

        struct Row: Decodable {
            let thread_id: String
            let status: String
        }

        let normalizedCurrentUserId = currentUserId.lowercased()
        let normalizedTargetUserId = targetUserId.lowercased()

        let rows: [Row] = try await client
            .rpc("start_or_get_thread", params: Params(target_user_id: normalizedTargetUserId))
            .execute()
            .value

        guard let row = rows.first else {
            throw NSError(
                domain: "FeedService.startConversation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't open the conversation."]
            )
        }

        await cache.invalidateInbox(userId: normalizedCurrentUserId)
        return StartConversationResult(
            threadId: row.thread_id,
            status: MessageThreadStatus(rawString: row.status)
        )
    }

    /// Recipient-only: flips a pending thread to accepted. Idempotent on
    /// the server side, so re-running is safe.
    func acceptMessageRequest(threadId: String, viewerUserId: String) async throws {
        struct Params: Encodable {
            let p_thread_id: String
        }

        try await client
            .rpc("accept_message_request", params: Params(p_thread_id: threadId))
            .execute()

        await cache.invalidateInbox(userId: viewerUserId.lowercased())
        await cache.invalidateConversation(threadId: threadId)
    }

    /// The viewer's "shareable contacts" — mutual follows plus anyone they
    /// already have an accepted DM thread with. Used by the in-app share
    /// sheet on a feed post.
    func fetchShareableContacts() async throws -> [UserProfile] {
        let rows: [UserProfile] = try await client
            .rpc("list_shareable_contacts")
            .execute()
            .value
        return rows
    }

    /// Shares a moment to each recipient via DM. Opens/returns the thread
    /// for each (via `start_or_get_thread`), then sends a message that
    /// references the post by id. The client renders these as tappable
    /// cards rather than text. Body is the sender's optional note.
    ///
    /// Recipients here always come from `fetchShareableContacts`, so the
    /// resulting threads are accepted end-to-end.
    ///
    /// Returns the number of successful sends.
    @discardableResult
    func shareMoment(
        video: FeedVideo,
        toUserIds recipientUserIds: [String],
        note: String? = nil,
        currentUserId: String
    ) async throws -> Int {
        guard !recipientUserIds.isEmpty else { return 0 }

        let trimmedNote = note?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedCurrentUserId = currentUserId.lowercased()

        var successCount = 0
        for recipientUserId in recipientUserIds {
            do {
                let result = try await startConversation(
                    currentUserId: normalizedCurrentUserId,
                    targetUserId: recipientUserId
                )
                _ = try await sendMessage(
                    threadId: result.threadId,
                    senderId: normalizedCurrentUserId,
                    body: trimmedNote,
                    sharedVideoId: video.id
                )
                successCount += 1
            } catch {
                // One bad recipient shouldn't block the rest. The UI
                // surfaces the overall result; per-recipient failures are
                // rare (block, network glitch) and not worth interrupting
                // the send.
                continue
            }
        }

        await cache.invalidateInbox(userId: normalizedCurrentUserId)
        return successCount
    }

    /// Recipient-only: wipes the thread + messages server-side. Silent —
    /// the requester gets no notification.
    func declineMessageRequest(threadId: String, viewerUserId: String) async throws {
        struct Params: Encodable {
            let p_thread_id: String
        }

        try await client
            .rpc("decline_message_request", params: Params(p_thread_id: threadId))
            .execute()

        await cache.invalidateInbox(userId: viewerUserId.lowercased())
        await cache.invalidateConversation(threadId: threadId)
    }

    /// Select shape for DM messages, including the embedded video preview
    /// for shares. The `!shared_video_id` hint tells PostgREST to join via
    /// the FK even though `videos` isn't a direct column. The join is
    /// skipped at parse time when `shared_video_id` is null.
    static let conversationMessageSelect = """
        id,
        thread_id,
        sender_id,
        body,
        created_at,
        shared_video_id,
        videos:shared_video_id (
            id,
            title,
            caption,
            playback_url,
            thumbnail_url,
            profiles:creator_id (username, display_name, avatar_url)
        )
        """

    func fetchConversationMessages(threadId: String) async throws -> [ConversationMessage] {
        if let cachedMessages = await cache.conversationMessages(threadId: threadId) {
            return cachedMessages
        }

        let messages: [ConversationMessage] = try await client
            .from("messages")
            .select(Self.conversationMessageSelect)
            .eq("thread_id", value: threadId)
            .order("created_at", ascending: true)
            .execute()
            .value

        await cache.storeConversationMessages(messages, threadId: threadId, ttl: Self.conversationCacheTTL)
        return messages
    }

    func sendMessage(
        threadId: String,
        senderId: String,
        body: String,
        sharedVideoId: String? = nil
    ) async throws -> ConversationMessage {
        struct Insert: Encodable {
            let thread_id: String
            let sender_id: String
            let body: String
            let shared_video_id: String?
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // A message must have either a body or a shared post reference.
        guard !trimmedBody.isEmpty || sharedVideoId != nil else {
            throw SocialInputError.emptyMessage
        }

        let insertedMessage: ConversationMessage = try await client
            .from("messages")
            .insert(
                Insert(
                    thread_id: threadId,
                    sender_id: senderId.lowercased(),
                    body: trimmedBody,
                    shared_video_id: sharedVideoId
                ),
                returning: .representation
            )
            .select(Self.conversationMessageSelect)
            .single()
            .execute()
            .value

        await cache.appendConversationMessage(insertedMessage, threadId: threadId, ttl: Self.conversationCacheTTL)
        await cache.invalidateInbox(userId: senderId.lowercased())
        return insertedMessage
    }

    private static func sanitizedSearchTerm(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }

    private static func parseTags(_ input: String?) -> [String] {
        guard let input else { return [] }

        var seen = Set<String>()
        var result: [String] = []

        for raw in input.split(separator: ",") {
            let tag = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)

            if result.count >= 12 {
                break
            }
        }

        return result
    }

    private static func parseISODate(_ value: String) -> Date {
        if let date = ProfileDateFormatter.isoWithFractional.date(from: value) {
            return date
        }
        if let date = ProfileDateFormatter.iso.date(from: value) {
            return date
        }
        return .distantPast
    }

    private static func storagePath(fromPublicURLString urlString: String?, bucketId: String) -> String? {
        guard
            let urlString,
            let url = URL(string: urlString),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let marker = "/storage/v1/object/public/\(bucketId)/"
        guard let range = components.path.range(of: marker) else { return nil }
        let path = String(components.path[range.upperBound...])
        return path.removingPercentEncoding ?? path
    }

    private func creatorsCacheKey(query: String?, excluding userId: String?, limit: Int) -> String {
        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let normalizedUserId = userId?.lowercased() ?? ""
        return "\(normalizedQuery)|\(normalizedUserId)|\(limit)"
    }

    private func relatedVideosCacheKey(seedVideoId: String, limit: Int) -> String {
        "\(seedVideoId)|\(limit)"
    }

    private func appendUniqueVideos(
        from candidates: [FeedVideo],
        to results: inout [FeedVideo],
        seenVideoIds: inout Set<String>,
        maxResults: Int
    ) {
        guard results.count < maxResults else { return }

        for video in candidates {
            guard !seenVideoIds.contains(video.id) else { continue }
            seenVideoIds.insert(video.id)
            results.append(video)

            if results.count >= maxResults {
                break
            }
        }
    }
}
