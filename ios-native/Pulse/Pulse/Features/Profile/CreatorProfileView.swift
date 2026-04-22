import SwiftUI

struct CreatorProfileView: View {
    @Environment(\.dismiss) private var dismiss

    let creatorId: String
    let onFollowStateChanged: ((Bool) -> Void)?

    @StateObject private var model: CreatorProfileViewModel
    @ObservedObject private var safety = SafetyService.shared
    @State private var selectedPostsRoute: ProfilePostsRoute?
    @State private var selectedLiveStream: LiveStream?
    @State private var activeConversation: ConversationRoute?
    @State private var isShowingReport = false
    @State private var isShowingBlockConfirm = false
    @State private var isShowingUnblockConfirm = false
    @State private var safetyActionError: String?
    @State private var isPerformingSafetyAction = false

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    init(creatorId: String, onFollowStateChanged: ((Bool) -> Void)? = nil) {
        self.creatorId = creatorId
        self.onFollowStateChanged = onFollowStateChanged
        _model = StateObject(wrappedValue: CreatorProfileViewModel(creatorId: creatorId))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if model.isLoading && model.profile == nil {
                ProgressView()
                    .tint(.white)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Color.clear.frame(height: 36)

                        header

                        if let errorMessage = model.errorMessage {
                            inlineMessage(errorMessage, tint: .red)
                        }

                        statsSection
                        actionRow
                        liveSection
                        postsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 110)
                }
                .refreshable {
                    await model.load()
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .padding(.top, 14)
            .padding(.leading, 16)

            // Overflow menu — only for other users' profiles. Block/report
            // against self would be nonsensical.
            if !model.isCurrentUser, let profileId = model.profile?.id ?? Optional(creatorId) {
                HStack {
                    Spacer()
                    overflowMenu(profileId: profileId)
                }
                .padding(.top, 14)
                .padding(.trailing, 16)
            }
        }
        .task {
            await model.load()
            await safety.refreshBlockedUsers()
        }
        .fullScreenCover(item: $selectedPostsRoute) { route in
            ProfilePostsFeedView(videos: route.videos, initialVideoId: route.initialVideoId, showsPageLabel: true)
        }
        .fullScreenCover(item: $selectedLiveStream) { stream in
            LiveStreamViewerView(stream: stream, isOwner: model.isCurrentUser)
        }
        .fullScreenCover(item: $activeConversation) { route in
            ConversationView(route: route)
        }
        .sheet(isPresented: $isShowingReport) {
            ReportSheet(target: .user(creatorId), subjectLabel: model.profile?.name ?? "this user")
        }
        .confirmationDialog(
            "Block \(model.profile?.name ?? "this user")?",
            isPresented: $isShowingBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task { await performBlock() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to see your posts, check-ins, or live streams, and you won't see theirs. They won't be notified.")
        }
        .confirmationDialog(
            "Unblock \(model.profile?.name ?? "this user")?",
            isPresented: $isShowingUnblockConfirm,
            titleVisibility: .visible
        ) {
            Button("Unblock") {
                Task { await performUnblock() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll see each other's content again.")
        }
        .alert("Couldn't update", isPresented: Binding(
            get: { safetyActionError != nil },
            set: { if !$0 { safetyActionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(safetyActionError ?? "")
        }
    }

    private func overflowMenu(profileId: String) -> some View {
        Menu {
            if safety.isBlocked(profileId) {
                Button {
                    isShowingUnblockConfirm = true
                } label: {
                    Label("Unblock", systemImage: "person.crop.circle.badge.checkmark")
                }
            } else {
                Button(role: .destructive) {
                    isShowingBlockConfirm = true
                } label: {
                    Label("Block", systemImage: "hand.raised.fill")
                }
            }

            Button {
                isShowingReport = true
            } label: {
                Label("Report", systemImage: "exclamationmark.bubble")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .disabled(isPerformingSafetyAction)
    }

    private func performBlock() async {
        isPerformingSafetyAction = true
        defer { isPerformingSafetyAction = false }
        do {
            try await safety.block(userId: creatorId)
            // Close the profile — there's nothing to show once they're blocked.
            dismiss()
        } catch {
            safetyActionError = error.localizedDescription
        }
    }

    private func performUnblock() async {
        isPerformingSafetyAction = true
        defer { isPerformingSafetyAction = false }
        do {
            try await safety.unblock(userId: creatorId)
        } catch {
            safetyActionError = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            avatar

            VStack(spacing: 4) {
                Text(model.profile?.name ?? "Creator")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(model.profile?.handle ?? "@creator")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
            }

            if let bio = model.profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 96, height: 96)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )

            if let avatarURL = model.profile?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(model.profile?.initial ?? "C")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
            } else {
                Text(model.profile?.initial ?? "C")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 10) {
            statPill(value: "\(model.stats.postsCount)", title: "Posts")
            statPill(value: ProfileCountFormatter.string(for: model.stats.followersCount), title: "Followers")
            statPill(value: ProfileCountFormatter.string(for: model.stats.followingCount), title: "Following")
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if model.isCurrentUser {
            EmptyView()
        } else {
            HStack(spacing: 10) {
                Button {
                    Task {
                        if let nextState = await model.toggleFollow() {
                            onFollowStateChanged?(nextState)
                        }
                    }
                } label: {
                    Text(followButtonLabel(for: model.followState))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(followButtonForeground(for: model.followState))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(followButtonBackground(for: model.followState))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    .white.opacity(model.followState == .notFollowing ? 0 : 0.12),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        activeConversation = await model.startConversation()
                    }
                } label: {
                    Text("Message")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(model.profile == nil)
                .opacity(model.profile == nil ? 0.5 : 1)
            }
        }
    }

    @ViewBuilder
    private var liveSection: some View {
        if let activeLiveStream = model.activeLiveStream {
            LiveStreamFeatureCard(
                stream: activeLiveStream,
                primaryActionTitle: model.isCurrentUser ? "Open live" : "Watch live"
            ) {
                selectedLiveStream = activeLiveStream
            }
        }
    }

    @ViewBuilder
    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posts")
                .font(.headline)
                .foregroundStyle(.white)

            if model.isLockedByPrivacy {
                privacyLockedPlaceholder
            } else if model.videos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("No public posts yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("This creator hasn’t shared anything visible yet.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.54))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .padding(.horizontal, 24)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
            } else {
                LazyVGrid(columns: gridColumns, spacing: 4) {
                    ForEach(model.videos) { video in
                        Button {
                            selectedPostsRoute = ProfilePostsRoute(
                                videos: model.videos,
                                initialVideoId: video.id
                            )
                        } label: {
                            ProfileGridCell(video: video)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var privacyLockedPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.45))
            Text("This account is private")
                .font(.headline)
                .foregroundStyle(.white)
            Text(model.followState == .requested
                ? "Your follow request is pending. You'll see their moments once they approve it."
                : "Follow to see their moments and check-ins.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.56))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 24)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func followButtonLabel(for state: CreatorFollowState) -> String {
        switch state {
        case .following:    return "Following"
        case .requested:    return "Requested"
        case .notFollowing: return "Follow"
        }
    }

    private func followButtonForeground(for state: CreatorFollowState) -> Color {
        switch state {
        case .notFollowing: return .black
        case .following, .requested: return .white
        }
    }

    private func followButtonBackground(for state: CreatorFollowState) -> Color {
        switch state {
        case .notFollowing: return Color.white
        case .following, .requested: return Color.white.opacity(0.08)
        }
    }

    private func statPill(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func inlineMessage(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint.opacity(0.95))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
    }
}

enum CreatorFollowState {
    case notFollowing
    case requested
    case following
}

@MainActor
private final class CreatorProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var videos: [FeedVideo] = []
    @Published private(set) var activeLiveStream: LiveStream?
    @Published private(set) var stats = ProfileStats(postsCount: 0, followersCount: 0, followingCount: 0)
    @Published private(set) var followState: CreatorFollowState = .notFollowing
    @Published private(set) var isCurrentUser = false
    @Published private(set) var isLoading = false
    @Published private(set) var isTargetPrivate = false
    @Published var errorMessage: String?

    /// True when the viewer shouldn't see the creator's posts: the account
    /// is private, the viewer isn't the owner, and the viewer doesn't
    /// follow them. Used to swap the grid for a locked placeholder.
    var isLockedByPrivacy: Bool {
        isTargetPrivate && !isCurrentUser && followState != .following
    }

    /// Convenience for callers that only care about the follow/unfollow
    /// binary (e.g. the feed's follow-state callback).
    var isFollowing: Bool { followState == .following }

    private let creatorId: String
    private let service = FeedService.shared
    private var currentUserId: String?

    init(creatorId: String) {
        self.creatorId = creatorId.lowercased()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        currentUserId = await SupabaseManager.shared.currentUserId()
        isCurrentUser = currentUserId == creatorId
        let viewerId = currentUserId

        do {
            async let profileTask = service.fetchCurrentProfile(userId: creatorId)
            async let postsTask = service.fetchPostsForCurrentUser(userId: creatorId)
            async let statsTask = service.fetchProfileStats(userId: creatorId)
            async let liveTask = service.fetchActiveLiveStream(creatorId: creatorId)
            async let followingTask: Bool = {
                guard let viewerId, viewerId != creatorId else { return false }
                return (try? await service.isFollowing(currentUserId: viewerId, targetUserId: creatorId)) ?? false
            }()
            async let pendingTask: Bool = {
                guard let viewerId, viewerId != creatorId else { return false }
                return await FollowRequestsService.shared.hasPendingRequest(targetId: creatorId)
            }()
            async let privateTask: Bool = {
                (try? await ProfilePrivacyService.fetchIsPrivate(userId: creatorId)) ?? false
            }()

            profile = try await profileTask
            videos = try await postsTask
            stats = try await statsTask
            activeLiveStream = try await liveTask

            let following = await followingTask
            let pending = await pendingTask
            followState = following ? .following : (pending ? .requested : .notFollowing)
            isTargetPrivate = await privateTask
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Drives the Follow button. Returns the new "is-following" state when
    /// something relevant to follower count changed, or `nil` when the
    /// transition was request-only.
    func toggleFollow() async -> Bool? {
        guard let currentUserId, currentUserId != creatorId else { return nil }

        let previous = followState

        switch previous {
        case .following:
            // Optimistic unfollow.
            followState = .notFollowing
            stats = ProfileStats(
                postsCount: stats.postsCount,
                followersCount: max(0, stats.followersCount - 1),
                followingCount: stats.followingCount
            )
            do {
                try await service.unfollow(creatorId: creatorId, followerId: currentUserId)
                return false
            } catch {
                followState = previous
                stats = ProfileStats(
                    postsCount: stats.postsCount,
                    followersCount: stats.followersCount + 1,
                    followingCount: stats.followingCount
                )
                errorMessage = error.localizedDescription
                return nil
            }

        case .requested:
            // Cancel the pending request.
            followState = .notFollowing
            do {
                try await FollowRequestsService.shared.cancelRequest(targetId: creatorId)
                return nil
            } catch {
                followState = previous
                errorMessage = error.localizedDescription
                return nil
            }

        case .notFollowing:
            // Branches on is_private server-side.
            do {
                let outcome = try await FollowRequestsService.shared.requestOrFollow(targetId: creatorId)
                switch outcome {
                case .followed, .alreadyFollowing:
                    followState = .following
                    if outcome == .followed {
                        stats = ProfileStats(
                            postsCount: stats.postsCount,
                            followersCount: stats.followersCount + 1,
                            followingCount: stats.followingCount
                        )
                    }
                    return true
                case .requested, .alreadyRequested:
                    followState = .requested
                    return nil
                }
            } catch {
                errorMessage = error.localizedDescription
                return nil
            }
        }
    }

    func startConversation() async -> ConversationRoute? {
        guard
            let currentUserId,
            let profile,
            currentUserId != creatorId
        else {
            return nil
        }

        do {
            let result = try await service.startConversation(
                currentUserId: currentUserId,
                targetUserId: creatorId
            )
            NotificationCenter.default.post(name: .pulseInboxDidUpdate, object: nil)
            // Viewer tapped "message" from the creator's profile, so they're
            // the creator side of this thread. If the thread already existed
            // with the viewer as the recipient it'll be accepted anyway.
            return ConversationRoute(
                threadId: result.threadId,
                viewerUserId: currentUserId,
                profile: profile,
                status: result.status,
                viewerIsCreator: true
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
