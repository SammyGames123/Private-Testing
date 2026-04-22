import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var videos: [FeedVideo] = []
    @Published private(set) var liveStreams: [LiveStream] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service = FeedService.shared
    private var currentUserId: String?
    private var likedVideoIds = Set<String>()
    private var followedCreatorIds = Set<String>()
    private var likeCounts: [String: Int] = [:]
    private var commentCounts: [String: Int] = [:]

    func loadIfNeeded() async {
        guard videos.isEmpty, !isLoading else { return }
        await load()
    }

    func load(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            currentUserId = await SupabaseManager.shared.currentUserId()

            if forceRefresh {
                await service.cache.invalidateFeed()
            }

            async let feedTask = service.fetchFeed(limit: 36)
            async let liveTask = service.fetchActiveLiveStreams(limit: 12, forceRefresh: forceRefresh)

            if let currentUserId {
                async let likedTask = service.fetchMyLikedVideoIds(userId: currentUserId)
                async let followedTask = service.fetchMyFollowedCreatorIds(userId: currentUserId)

                videos = try await feedTask
                liveStreams = try await liveTask
                likedVideoIds = try await likedTask
                followedCreatorIds = try await followedTask
            } else {
                videos = try await feedTask
                liveStreams = try await liveTask
                likedVideoIds = []
                followedCreatorIds = []
            }

            likeCounts = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, $0.likesCount) })
            commentCounts = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, $0.commentsCount) })
            errorMessage = nil
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isLiked(_ video: FeedVideo) -> Bool {
        likedVideoIds.contains(video.id)
    }

    func likeCount(for video: FeedVideo) -> Int {
        likeCounts[video.id] ?? video.likesCount
    }

    func commentCount(for video: FeedVideo) -> Int {
        commentCounts[video.id] ?? video.commentsCount
    }

    func isFollowing(_ creatorId: String) -> Bool {
        followedCreatorIds.contains(creatorId.lowercased())
    }

    func isLiveOwner(_ stream: LiveStream) -> Bool {
        currentUserId?.lowercased() == stream.creatorId.lowercased()
    }

    func canFollow(creatorId: String) -> Bool {
        guard let currentUserId else { return true }
        return currentUserId.lowercased() != creatorId.lowercased()
    }

    func setFollowing(creatorId: String, isFollowing: Bool) {
        let normalizedCreatorId = creatorId.lowercased()
        if isFollowing {
            followedCreatorIds.insert(normalizedCreatorId)
        } else {
            followedCreatorIds.remove(normalizedCreatorId)
        }
    }

    func registerCommentCreated(for videoId: String) {
        commentCounts[videoId, default: 0] += 1
    }

    func toggleLike(_ video: FeedVideo) {
        guard let currentUserId else {
            errorMessage = "You need to be signed in to like posts."
            return
        }

        let isCurrentlyLiked = likedVideoIds.contains(video.id)
        if isCurrentlyLiked {
            likedVideoIds.remove(video.id)
            likeCounts[video.id] = max(0, likeCount(for: video) - 1)
        } else {
            likedVideoIds.insert(video.id)
            likeCounts[video.id] = likeCount(for: video) + 1
        }

        Task {
            do {
                if isCurrentlyLiked {
                    try await service.unlike(videoId: video.id, userId: currentUserId)
                } else {
                    try await service.like(videoId: video.id, userId: currentUserId)
                }
                errorMessage = nil
            } catch is CancellationError {
                revertLikedState(for: video.id, wasLiked: isCurrentlyLiked, baselineCount: video.likesCount)
            } catch {
                revertLikedState(for: video.id, wasLiked: isCurrentlyLiked, baselineCount: video.likesCount)
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleFollow(creatorId: String) {
        guard let currentUserId else {
            errorMessage = "You need to be signed in to follow creators."
            return
        }

        let normalizedCreatorId = creatorId.lowercased()
        guard currentUserId.lowercased() != normalizedCreatorId else { return }

        let isCurrentlyFollowing = followedCreatorIds.contains(normalizedCreatorId)
        setFollowing(creatorId: normalizedCreatorId, isFollowing: !isCurrentlyFollowing)

        Task {
            do {
                if isCurrentlyFollowing {
                    try await service.unfollow(creatorId: normalizedCreatorId, followerId: currentUserId)
                } else {
                    try await service.follow(creatorId: normalizedCreatorId, followerId: currentUserId)
                }
                errorMessage = nil
            } catch is CancellationError {
                setFollowing(creatorId: normalizedCreatorId, isFollowing: isCurrentlyFollowing)
            } catch {
                setFollowing(creatorId: normalizedCreatorId, isFollowing: isCurrentlyFollowing)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func revertLikedState(for videoId: String, wasLiked: Bool, baselineCount: Int) {
        if wasLiked {
            likedVideoIds.insert(videoId)
        } else {
            likedVideoIds.remove(videoId)
        }
        likeCounts[videoId] = baselineCount
    }
}
