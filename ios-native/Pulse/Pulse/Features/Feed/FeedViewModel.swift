import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var videos: [FeedVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // Per-video interactive overlay state. Kept separate from the
    // immutable server snapshot so optimistic toggles don't require
    // re-creating FeedVideo values.
    @Published private(set) var likedVideoIds: Set<String> = []
    @Published private(set) var likeCounts: [String: Int] = [:]
    @Published private(set) var followedCreatorIds: Set<String> = []

    private let service = FeedService.shared
    private var currentUserId: String?

    func loadIfNeeded() async {
        guard videos.isEmpty, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let userId: String?
            if let session = try? await SupabaseManager.shared.client.auth.session {
                userId = session.user.id.uuidString
            } else {
                userId = nil
            }
            currentUserId = userId

            // Fire the three reads in parallel.
            async let videosTask = service.fetchFeed()
            async let likesTask: Set<String> = {
                if let userId {
                    return (try? await service.fetchMyLikedVideoIds(userId: userId)) ?? []
                }
                return []
            }()
            async let followsTask: Set<String> = {
                if let userId {
                    return (try? await service.fetchMyFollowedCreatorIds(userId: userId)) ?? []
                }
                return []
            }()

            let loaded = try await videosTask
            videos = loaded
            likedVideoIds = await likesTask
            followedCreatorIds = await followsTask
            likeCounts = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.likesCount) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived state

    func isLiked(_ video: FeedVideo) -> Bool {
        likedVideoIds.contains(video.id)
    }

    func likeCount(for video: FeedVideo) -> Int {
        likeCounts[video.id] ?? video.likesCount
    }

    func isFollowing(_ creatorId: String) -> Bool {
        followedCreatorIds.contains(creatorId)
    }

    // MARK: - Mutations

    func toggleLike(_ video: FeedVideo) {
        guard let userId = currentUserId else { return }
        let wasLiked = likedVideoIds.contains(video.id)

        // Optimistic update
        if wasLiked {
            likedVideoIds.remove(video.id)
            likeCounts[video.id] = max(0, (likeCounts[video.id] ?? video.likesCount) - 1)
        } else {
            likedVideoIds.insert(video.id)
            likeCounts[video.id] = (likeCounts[video.id] ?? video.likesCount) + 1
        }

        Task { [weak self, videoId = video.id, wasLiked] in
            do {
                if wasLiked {
                    try await FeedService.shared.unlike(videoId: videoId, userId: userId)
                } else {
                    try await FeedService.shared.like(videoId: videoId, userId: userId)
                }
            } catch {
                // Roll back
                guard let self else { return }
                if wasLiked {
                    self.likedVideoIds.insert(videoId)
                    self.likeCounts[videoId] = (self.likeCounts[videoId] ?? 0) + 1
                } else {
                    self.likedVideoIds.remove(videoId)
                    self.likeCounts[videoId] = max(0, (self.likeCounts[videoId] ?? 1) - 1)
                }
            }
        }
    }

    func toggleFollow(creatorId: String) {
        guard let userId = currentUserId, userId != creatorId else { return }
        let wasFollowing = followedCreatorIds.contains(creatorId)

        if wasFollowing {
            followedCreatorIds.remove(creatorId)
        } else {
            followedCreatorIds.insert(creatorId)
        }

        Task { [weak self, wasFollowing] in
            do {
                if wasFollowing {
                    try await FeedService.shared.unfollow(creatorId: creatorId, followerId: userId)
                } else {
                    try await FeedService.shared.follow(creatorId: creatorId, followerId: userId)
                }
            } catch {
                guard let self else { return }
                if wasFollowing {
                    self.followedCreatorIds.insert(creatorId)
                } else {
                    self.followedCreatorIds.remove(creatorId)
                }
            }
        }
    }
}
