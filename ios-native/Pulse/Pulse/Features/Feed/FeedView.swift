import AVFoundation
import SwiftUI
import UIKit

private enum FeedPageItem: Identifiable, Hashable {
    case video(FeedVideo)
    case live(LiveStream)

    var id: String {
        switch self {
        case .video(let video):
            return "video-\(video.id)"
        case .live(let stream):
            return "live-\(stream.id)"
        }
    }
}

struct FeedView: View {
    @StateObject private var model = FeedViewModel()
    @StateObject private var pool = FeedPlayerPool()
    @State private var activeFeedItemId: String?
    @State private var selectedCommentVideo: FeedVideo?
    @State private var selectedCreatorRoute: FeedCreatorRoute?
    @State private var selectedLiveStream: LiveStream?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                feedContent(in: geo)

                VStack(spacing: 12) {
                    headerBlock

                    if !model.liveStreams.isEmpty {
                        liveNowStrip
                    }

                    if let errorMessage = model.errorMessage {
                        inlineMessage(errorMessage, tint: .red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, topSafeAreaInset + 10)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .task {
            await model.loadIfNeeded()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await model.load(forceRefresh: true)
            }
        }
        .onChange(of: feedItems) { oldValue, newValue in
            guard !oldValue.isEmpty || !newValue.isEmpty else { return }

            if newValue.isEmpty {
                activeFeedItemId = nil
                pool.tearDownAll()
                return
            }

            guard let activeFeedItemId else {
                resumeFeed()
                return
            }

            if !newValue.contains(where: { $0.id == activeFeedItemId }) {
                resumeFeed()
                return
            }

            syncPool(to: activeFeedItemId)
        }
        .onChange(of: activeFeedItemId) { _, newValue in
            guard let newValue else { return }
            syncPool(to: newValue)
        }
        .onChange(of: selectedLiveStream) { _, newValue in
            if newValue != nil {
                pool.suspendPlayback()
            } else {
                pool.resumePlayback()
                resumeFeed()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseDidCreatePost)) { _ in
            Task {
                await model.load(forceRefresh: true)
            }
        }
        .sheet(item: $selectedCommentVideo) { video in
            CommentsSheet(video: video) {
                model.registerCommentCreated(for: video.id)
            }
        }
        .fullScreenCover(item: $selectedCreatorRoute) { route in
            CreatorProfileView(creatorId: route.creatorId) { isFollowing in
                model.setFollowing(creatorId: route.creatorId, isFollowing: isFollowing)
            }
        }
        .fullScreenCover(item: $selectedLiveStream) { stream in
            LiveStreamViewerView(stream: stream, isOwner: model.isLiveOwner(stream))
        }
        .onDisappear {
            pool.tearDownAll()
        }
    }

    @ViewBuilder
    private func feedContent(in geo: GeometryProxy) -> some View {
        if model.isLoading && feedItems.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if feedItems.isEmpty {
            emptyState
                .padding(.horizontal, 24)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(feedItems) { item in
                        switch item {
                        case .video(let video):
                            FeedVideoCell(
                                video: video,
                                pool: pool,
                                model: model,
                                onShowComments: {
                                    selectedCommentVideo = video
                                },
                                onShowCreator: {
                                    selectedCreatorRoute = FeedCreatorRoute(creatorId: video.creatorId)
                                }
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(item.id)

                        case .live(let stream):
                            FeedLiveStreamPage(
                                stream: stream,
                                onOpenLive: {
                                    selectedLiveStream = stream
                                },
                                onShowCreator: {
                                    selectedCreatorRoute = FeedCreatorRoute(creatorId: stream.creatorId)
                                }
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(item.id)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeFeedItemId)
            .scrollIndicators(.hidden)
            .refreshable {
                await model.load(forceRefresh: true)
            }
            .onAppear {
                resumeFeed()
            }
        }
    }

    private var headerBlock: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Spilltop")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            if let speedLabel = pool.activePlaybackSpeedLabel {
                PlaybackSpeedBadge(text: speedLabel)
            }

            PulseInboxLaunchButton()
        }
    }

    private var liveNowStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.liveStreams) { stream in
                        Button {
                            selectedLiveStream = stream
                        } label: {
                            LiveStreamStripCard(stream: stream)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))

            Text("No posts yet")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Recent moments from people around you will land here.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feedItems: [FeedPageItem] {
        buildFeedItems(videos: model.videos, liveStreams: model.liveStreams)
    }

    private func resumeFeed() {
        guard !feedItems.isEmpty else {
            activeFeedItemId = nil
            pool.tearDownAll()
            return
        }

        let targetId: String
        if let activeFeedItemId, feedItems.contains(where: { $0.id == activeFeedItemId }) {
            targetId = activeFeedItemId
        } else if let firstItemId = feedItems.first?.id {
            targetId = firstItemId
        } else {
            return
        }

        activeFeedItemId = targetId
        syncPool(to: targetId)
    }

    private func syncPool(to itemId: String) {
        guard selectedLiveStream == nil else { return }
        guard let item = feedItems.first(where: { $0.id == itemId }) else { return }

        switch item {
        case .video(let video):
            pool.resumePlayback()
            guard let index = model.videos.firstIndex(where: { $0.id == video.id }) else { return }
            pool.syncActiveWindow(videos: model.videos, activeIndex: index)

        case .live:
            pool.suspendPlayback()
        }
    }

    private func buildFeedItems(videos: [FeedVideo], liveStreams: [LiveStream]) -> [FeedPageItem] {
        guard !liveStreams.isEmpty else {
            return videos.map(FeedPageItem.video)
        }

        let liveInterval = 4
        var items: [FeedPageItem] = []
        var nextLiveIndex = 0

        for (index, video) in videos.enumerated() {
            items.append(.video(video))

            let shouldInsertLive = nextLiveIndex < liveStreams.count && (index + 1) % liveInterval == 0
            if shouldInsertLive {
                items.append(.live(liveStreams[nextLiveIndex]))
                nextLiveIndex += 1
            }
        }

        while nextLiveIndex < liveStreams.count {
            items.append(.live(liveStreams[nextLiveIndex]))
            nextLiveIndex += 1
        }

        return items
    }

    private var topSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }

    private func inlineMessage(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint.opacity(0.98))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
    }
}

fileprivate struct FeedCreatorRoute: Identifiable {
    let id = UUID()
    let creatorId: String
}

private struct FeedLiveStreamPage: View {
    let stream: LiveStream
    let onOpenLive: () -> Void
    let onShowCreator: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backgroundVisual

            LinearGradient(
                colors: [.black.opacity(0.08), .clear, .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                Spacer()

                HStack(spacing: 10) {
                    PulseLiveBadge(title: stream.liveBadgeTitle)

                    Label("\(stream.viewerCount)", systemImage: "eye.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.28))
                        .clipShape(Capsule())
                }

                Button(action: onShowCreator) {
                    HStack(spacing: 12) {
                        creatorAvatar

                        VStack(alignment: .leading, spacing: 4) {
                            Text(stream.creatorHandle)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)

                            Text(stream.title)
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Text(stream.contextSubtitle)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button(action: onOpenLive) {
                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.body.weight(.bold))

                        Text("Watch Live")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 112)
        }
    }

    @ViewBuilder
    private var backgroundVisual: some View {
        if let thumbnailURL = stream.thumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                default:
                    placeholderBackground
                }
            }
        } else {
            placeholderBackground
        }
    }

    private var placeholderBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.24, green: 0.08, blue: 0.36),
                Color(red: 0.08, green: 0.03, blue: 0.12),
                Color.black,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var creatorAvatar: some View {
        Circle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 54, height: 54)
            .overlay {
                if let avatarURL = stream.creatorAvatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            Text(stream.creatorInitial)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .clipShape(Circle())
                } else {
                    Text(stream.creatorInitial)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

struct PulseMomentCard: View {
    let video: FeedVideo

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ProfileGridThumbnail(video: video)

            LinearGradient(
                colors: [.clear, .black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let momentLabel = video.momentLabel {
                        Text(momentLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(categoryTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(categoryTint.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    if video.mediaKind == .video {
                        Image(systemName: "play.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(video.creatorHandle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))

                    if video.isOutNowMoment, let venueName = video.venueName {
                        Text(venueName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.purple.opacity(0.92))
                            .lineLimit(1)
                    }

                    Text(PulseRelativeTimeFormatter.string(from: video.createdAt))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.56))
                }
            }
            .padding(12)
        }
        .frame(width: 186, height: 286)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var categoryBadge: String {
        video.momentLabel ?? "Moment"
    }

    private var categoryTint: Color {
        switch video.category {
        case "going-out":
            return Color.purple.opacity(0.95)
        case "out-now":
            return Color.orange
        default:
            return Color.white.opacity(0.8)
        }
    }
}

struct PulseFeedCard: View {
    let item: PulseFeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.badge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(badgeTint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(badgeTint.opacity(0.14))
                            .clipShape(Capsule())

                        if item.style == .friendMove {
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    Text(item.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.64))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    if !item.vibeEmojis.isEmpty {
                        Text(item.vibeEmojis.joined(separator: " "))
                            .font(.title3)
                    }

                    Text(PulseRelativeTimeFormatter.string(from: item.createdAt))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.54))
                }
            }

            if let venue = item.venue {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(badgeTint)

                    Text(venue.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("•")
                        .foregroundStyle(.white.opacity(0.24))

                    Text(venue.shortLocation)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var badgeTint: Color {
        switch item.status {
        case .hot:
            return Color.orange
        case .building:
            return Color.purple
        case .slowingDown:
            return Color(red: 1.0, green: 0.76, blue: 0.3)
        case .quiet, .none:
            return Color.white.opacity(0.72)
        }
    }
}

struct PulseStatusBadge: View {
    let status: PulseVenueStatus

    var body: some View {
        Text(status.nightlifeBadgeTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch status {
        case .hot:
            return Color.orange
        case .building:
            return Color.purple.opacity(0.95)
        case .slowingDown:
            return Color(red: 1.0, green: 0.82, blue: 0.42)
        case .quiet:
            return .white.opacity(0.75)
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .hot:
            return Color.orange.opacity(0.14)
        case .building:
            return Color.purple.opacity(0.18)
        case .slowingDown:
            return Color(red: 1.0, green: 0.76, blue: 0.3).opacity(0.16)
        case .quiet:
            return Color.white.opacity(0.08)
        }
    }
}

struct PulseSignalConfidenceBadge: View {
    let confidence: PulseVenueSignalConfidence

    var body: some View {
        Text(confidence.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch confidence {
        case .live:
            return Color.green.opacity(0.95)
        case .blended:
            return Color(red: 0.46, green: 0.78, blue: 1.0)
        case .expected:
            return .white.opacity(0.78)
        }
    }

    private var backgroundColor: Color {
        switch confidence {
        case .live:
            return Color.green.opacity(0.14)
        case .blended:
            return Color(red: 0.25, green: 0.47, blue: 0.92).opacity(0.16)
        case .expected:
            return Color.white.opacity(0.08)
        }
    }
}

struct PulseVenueDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let summary: HotVenueSummary
    let recentCheckIns: [NightlifeCheckIn]
    let distanceLabel: String?

    @State private var venueMoments: [FeedVideo] = []
    @State private var isLoadingMoments = false
    @State private var momentErrorMessage: String?
    @State private var activeLiveStream: LiveStream?
    @State private var selectedPostsRoute: ProfilePostsRoute?
    @State private var selectedCreatorRoute: FeedCreatorRoute?
    @State private var selectedLiveStream: LiveStream?
    @State private var followedUserIds = Set<String>()
    @State private var currentUserId: String?

    private let service = FeedService.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 34)

                    heroSection
                    actionBlock
                    liveNowSection
                    tonightOverview
                    peopleHereSection
                    momentsSection
                    recentActivity
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)

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
        }
        .task(id: summary.id) {
            async let momentsTask: Void = loadVenueMoments()
            async let followsTask: Void = loadFollowedUsers()
            async let liveTask: Void = loadActiveLiveStream()
            _ = await (momentsTask, followsTask, liveTask)
        }
        .fullScreenCover(item: $selectedPostsRoute) { route in
            ProfilePostsFeedView(
                videos: route.videos,
                initialVideoId: route.initialVideoId,
                showsPageLabel: false
            )
        }
        .fullScreenCover(item: $selectedCreatorRoute) { route in
            CreatorProfileView(creatorId: route.creatorId)
        }
        .fullScreenCover(item: $selectedLiveStream) { stream in
            LiveStreamViewerView(
                stream: stream,
                isOwner: currentUserId?.lowercased() == stream.creatorId.lowercased()
            )
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    PulseStatusBadge(status: summary.status)
                    PulseSignalConfidenceBadge(confidence: summary.confidence)

                    if summary.venue.featured == true {
                        heroMetaPill(title: "Featured", systemImage: "star.fill")
                    }
                }

                Spacer()

                Text(scoreLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(summary.venue.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)

                Text(summary.venue.shortLocation)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))

                if let address = summary.venue.resolvedAddress, !address.isEmpty {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineSpacing(2)
                }
            }

            HStack(spacing: 8) {
                if let distanceLabel, !distanceLabel.isEmpty {
                    heroMetaPill(title: distanceLabel, systemImage: "location.fill")
                }

                if let nightlifeScore = summary.venue.nightlifeScore {
                    heroMetaPill(title: "\(nightlifeScore)/10", systemImage: "flame.fill")
                }

                if let priceLabel = summary.venue.priceLevelLabel {
                    heroMetaPill(title: priceLabel, systemImage: "dollarsign.circle.fill")
                }
            }

            if !summary.recentVibes.isEmpty {
                Text(summary.recentVibes.joined(separator: " "))
                    .font(.title3.weight(.semibold))
            }

            Text(heroSubtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))

            if !uniqueRecentCheckIns.isEmpty {
                venuePresenceSummary
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.08, blue: 0.27),
                            Color(red: 0.08, green: 0.05, blue: 0.15),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var actionBlock: some View {
        VStack(spacing: 10) {
            if summary.venue.resolvedAddress != nil {
                primaryActionButton(title: "Go Here", systemImage: "figure.walk") {
                    openVenueInMaps()
                }
            }

            HStack(spacing: 10) {
                actionButton(title: "Check in", systemImage: "location.fill") {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .pulseOpenCreate,
                        object: PulseCreateRoute(mode: "check-in", venueId: summary.venue.id)
                    )
                }

                actionButton(title: "Post moment", systemImage: "sparkles") {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .pulseOpenCreate,
                        object: PulseCreateRoute(mode: "moment", venueId: summary.venue.id)
                    )
                }
            }

            HStack(spacing: 10) {
                actionButton(title: "Go live", systemImage: "dot.radiowaves.left.and.right") {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .pulseOpenCreate,
                        object: PulseCreateRoute(mode: "live", venueId: summary.venue.id)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var liveNowSection: some View {
        if let activeLiveStream {
            LiveStreamFeatureCard(
                stream: activeLiveStream,
                primaryActionTitle: "Watch live"
            ) {
                selectedLiveStream = activeLiveStream
            }
        }
    }

    private var venuePresenceSummary: some View {
        HStack(spacing: 12) {
            PulseAvatarStack(checkIns: uniqueRecentCheckIns, maxVisible: 4, avatarSize: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(livePresenceLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(scoreLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer()
        }
        .padding(.top, 2)
    }

    private var tonightOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tonight")
                .font(.headline)
                .foregroundStyle(.white)

            Text(tonightSubtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.58))

            HStack(spacing: 10) {
                statTile(title: "Check-ins", value: "\(summary.activityCount)")
                statTile(title: "People", value: "\(summary.uniquePeopleCount)")
                statTile(title: "Friends", value: "\(summary.friendCount)")
            }
        }
    }

    @ViewBuilder
    private var peopleHereSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !friendCheckIns.isEmpty {
                presenceSection(
                    title: "Your crew",
                    subtitle: "Friends already at this venue tonight.",
                    checkIns: friendCheckIns
                )
            }

            presenceSection(
                title: friendCheckIns.isEmpty ? "Who's here now" : "Everyone else here",
                subtitle: friendCheckIns.isEmpty ? "Live check-ins happening at this venue right now." : "Other people currently checked in here.",
                checkIns: friendCheckIns.isEmpty ? uniqueRecentCheckIns : otherCheckIns
            )
        }
    }

    @ViewBuilder
    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tonight's moments")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                if !venueMoments.isEmpty {
                    Text("\(venueMoments.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            if let momentErrorMessage {
                Text(momentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
            } else if isLoadingMoments && venueMoments.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else if venueMoments.isEmpty {
                Text("No moments from this venue yet tonight.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.56))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(venueMoments) { video in
                            Button {
                                selectedPostsRoute = ProfilePostsRoute(
                                    videos: venueMoments,
                                    initialVideoId: video.id
                                )
                            } label: {
                                PulseMomentCard(video: video)
                                    .frame(width: 170)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tonight's check-ins")
                .font(.headline)
                .foregroundStyle(.white)

            if recentCheckIns.isEmpty {
                Text("No one has checked in here yet tonight.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.56))
            } else {
                ForEach(Array(recentCheckIns.prefix(12))) { checkIn in
                    checkInRow(checkIn)
                }
            }
        }
    }

    @ViewBuilder
    private func presenceSection(title: String, subtitle: String, checkIns: [NightlifeCheckIn]) -> some View {
        if !checkIns.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.52))
                }

                ForEach(checkIns) { checkIn in
                    checkInRow(checkIn, emphasizesPresence: true)
                }
            }
        }
    }

    private func checkInRow(_ checkIn: NightlifeCheckIn, emphasizesPresence: Bool = false) -> some View {
        Button {
            selectedCreatorRoute = FeedCreatorRoute(creatorId: checkIn.userId)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                avatar(for: checkIn)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(checkIn.userName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(checkIn.user?.handle ?? "@creator")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    if let note = checkIn.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.74))
                    } else {
                        Text("Checked in \(checkIn.vibeEmoji ?? "📍")")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    HStack(spacing: 8) {
                        if checkIn.isActive {
                            Label("Here now", systemImage: "dot.radiowaves.left.and.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.green.opacity(0.95))
                        }

                        Text("Checked in \(checkIn.relativeTimestamp)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.46))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    if let vibe = checkIn.vibeEmoji, !vibe.isEmpty {
                        Text(vibe)
                            .font(.title3)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(14)
            .background(emphasizesPresence ? Color.white.opacity(0.07) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func avatar(for checkIn: NightlifeCheckIn) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 42, height: 42)

            if let avatarURL = checkIn.user?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(checkIn.userInitial)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .id(avatarURL.absoluteString)
                .frame(width: 42, height: 42)
                .clipShape(Circle())
            } else {
                Text(checkIn.userInitial)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    private func primaryActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func heroMetaPill(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(.white)

            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var scoreLine: String {
        if summary.confidence == .expected {
            return summary.confidence.explanation
        }

        if let latestCheckInAt = summary.latestCheckInAt {
            return "Updated \(PulseRelativeTimeFormatter.string(from: latestCheckInAt))"
        }
        return summary.confidence.explanation
    }

    private var heroSubtitle: String {
        if !friendCheckIns.isEmpty {
            return "\(friendCheckIns.count) friend\(friendCheckIns.count == 1 ? "" : "s") already here. Good next stop if you want instant energy."
        }

        if summary.confidence == .expected {
            return "\(summary.expectedStatus.expectedHeadline) based on venue type and the time tonight."
        }

        if summary.confidence == .blended {
            return "A few Spilltop signals are landing here and this venue usually gets \(summary.expectedStatus.expectedPhrase)."
        }

        if summary.status == .hot {
            return "Busy right now with strong activity and fresh check-ins."
        }

        if summary.status == .building {
            return "Momentum is building here tonight."
        }

        if summary.status == .slowingDown {
            return "This spot is easing off and starting to wind down."
        }

        if let vibeBlurb = summary.venue.vibeBlurb, !vibeBlurb.isEmpty {
            return vibeBlurb
        }

        return "A solid venue to keep on your radar tonight."
    }

    private var uniqueRecentCheckIns: [NightlifeCheckIn] {
        var seen = Set<String>()
        return recentCheckIns.filter { seen.insert($0.userId).inserted }
    }

    private var friendCheckIns: [NightlifeCheckIn] {
        uniqueRecentCheckIns.filter { followedUserIds.contains($0.userId.lowercased()) }
    }

    private var otherCheckIns: [NightlifeCheckIn] {
        uniqueRecentCheckIns.filter { !followedUserIds.contains($0.userId.lowercased()) }
    }

    private var livePresenceLine: String {
        if !friendCheckIns.isEmpty {
            let friends = friendCheckIns.count
            let others = max(0, uniqueRecentCheckIns.count - friends)
            if others > 0 {
                return "\(friends) friend\(friends == 1 ? "" : "s") and \(others) others here now"
            }
            return "\(friends) friend\(friends == 1 ? "" : "s") here now"
        }

        let total = uniqueRecentCheckIns.count
        return "\(total) people here now"
    }

    private var tonightSubtitle: String {
        if !friendCheckIns.isEmpty {
            return livePresenceLine
        }

        if summary.confidence == .expected {
            return "\(summary.expectedStatus.expectedHeadline). \(summary.confidence.explanation)"
        }

        if summary.confidence == .blended {
            return "\(summary.currentCrowdLine) • \(summary.crowdMetaLine)"
        }

        if summary.activityCount > 0 {
            return "\(summary.activityCount) check-in\(summary.activityCount == 1 ? "" : "s") landed here tonight."
        }

        return "Waiting on the first check-in of the night."
    }

    private func loadVenueMoments() async {
        isLoadingMoments = true
        momentErrorMessage = nil
        defer { isLoadingMoments = false }

        do {
            venueMoments = try await service.fetchVenueMoments(
                venueId: summary.venue.id,
                limit: 18,
                sinceHours: 18
            )
        } catch is CancellationError {
            momentErrorMessage = nil
        } catch {
            momentErrorMessage = error.localizedDescription
        }
    }

    private func loadFollowedUsers() async {
        guard let currentUserId = await SupabaseManager.shared.currentUserId() else {
            self.currentUserId = nil
            followedUserIds = []
            return
        }

        self.currentUserId = currentUserId

        do {
            followedUserIds = try await service.fetchMyFollowedCreatorIds(userId: currentUserId)
        } catch {
            followedUserIds = []
        }
    }

    private func loadActiveLiveStream() async {
        do {
            activeLiveStream = try await service.fetchActiveLiveStream(venueId: summary.venue.id)
        } catch {
            activeLiveStream = nil
        }
    }

    private func openVenueInMaps() {
        guard let destination = summary.venue.resolvedAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !destination.isEmpty,
            let encodedDestination = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "http://maps.apple.com/?daddr=\(encodedDestination)&dirflg=w") else {
            return
        }

        UIApplication.shared.open(url)
    }
}

struct PulseAvatarStack: View {
    let checkIns: [NightlifeCheckIn]
    let maxVisible: Int
    let avatarSize: CGFloat

    init(checkIns: [NightlifeCheckIn], maxVisible: Int = 3, avatarSize: CGFloat = 30) {
        self.checkIns = checkIns
        self.maxVisible = maxVisible
        self.avatarSize = avatarSize
    }

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(checkIns.prefix(maxVisible))) { checkIn in
                avatar(for: checkIn)
            }
        }
        .padding(.trailing, checkIns.count > 1 ? 10 : 0)
    }

    private func avatar(for checkIn: NightlifeCheckIn) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.88))
                .frame(width: avatarSize, height: avatarSize)

            if let avatarURL = checkIn.user?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(checkIn.userInitial)
                            .font(.system(size: avatarSize * 0.34, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
            } else {
                Text(checkIn.userInitial)
                    .font(.system(size: avatarSize * 0.34, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .overlay(
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }
}

struct PulseLiveBadge: View {
    let title: String

    init(title: String = "LIVE") {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.red.opacity(0.9))
        .clipShape(Capsule())
    }
}

struct LiveStreamStripCard: View {
    let stream: LiveStream

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 58, height: 58)
                    .overlay {
                        if let avatarURL = stream.creatorAvatarURL {
                            AsyncImage(url: avatarURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                default:
                                    Text(stream.creatorInitial)
                                        .font(.headline.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .clipShape(Circle())
                        } else {
                            Text(stream.creatorInitial)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 5, height: 5)

                    Text("Live")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.94))
                .clipShape(Capsule())
                .offset(x: 4, y: 7)
            }

            Text(stream.creatorName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 74)
                .multilineTextAlignment(.center)
        }
        .frame(width: 76)
    }
}

struct LiveStreamFeatureCard: View {
    let stream: LiveStream
    let primaryActionTitle: String
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                PulseLiveBadge(title: stream.liveBadgeTitle)

                Spacer()

                Text(stream.relativeStartedAt)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(stream.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text(stream.creatorHandle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))

                    if stream.isGettingReadyStream {
                        Text("• Getting ready")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                    } else if let venueName = stream.venueName {
                        Text("• \(venueName)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }

                Text(stream.playbackStateTitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.68))
            }

            HStack(spacing: 10) {
                metricPill(systemImage: "eye.fill", value: "\(stream.viewerCount)", title: "Viewers")

                if stream.isGettingReadyStream {
                    metricPill(systemImage: "house.fill", value: "Home", title: "Setup")
                } else if let venueLocation = stream.venueShortLocation {
                    metricPill(systemImage: "location.fill", value: venueLocation, title: "Venue")
                }
            }

            Button(action: onPrimaryAction) {
                Label(primaryActionTitle, systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.08, blue: 0.31),
                            Color(red: 0.08, green: 0.04, blue: 0.15),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func metricPill(systemImage: String, value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(value, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct LiveStreamViewerView: View {
    @Environment(\.dismiss) private var dismiss

    let stream: LiveStream
    let isOwner: Bool
    let onEnded: (() -> Void)?

    @State private var currentStream: LiveStream
    @State private var player: AVPlayer?
    @State private var isEnding = false
    @State private var errorMessage: String?
    @State private var selectedCreatorRoute: FeedCreatorRoute?

    private let service = FeedService.shared

    init(stream: LiveStream, isOwner: Bool = false, onEnded: (() -> Void)? = nil) {
        self.stream = stream
        self.isOwner = isOwner
        self.onEnded = onEnded
        _currentStream = State(initialValue: stream)
    }

    var body: some View {
        Group {
            if currentStream.isLiveKitStream {
                PulseLiveKitRoomView(
                    stream: currentStream,
                    isOwner: isOwner,
                    onEnded: onEnded
                )
            } else {
                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()

                    mediaLayer

                    LinearGradient(
                        colors: [.black.opacity(0.85), .clear, .black.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    topBar

                    VStack(alignment: .leading, spacing: 16) {
                        Spacer()

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.95))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.red.opacity(0.28), lineWidth: 1)
                                )
                        }

                        detailsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 38)
                }
            }
        }
        .task(id: currentStream.playbackUrlString) {
            configurePlayerIfNeeded()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .fullScreenCover(item: $selectedCreatorRoute) { route in
            CreatorProfileView(creatorId: route.creatorId)
        }
        .interactiveDismissDisabled(isOwner && currentStream.isLive)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if !(isOwner && currentStream.isLive) {
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
            } else {
                PulseLiveBadge(title: currentStream.liveBadgeTitle)
            }

            Spacer()

            if isOwner && currentStream.isLive {
                Button {
                    Task {
                        await endStream()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isEnding {
                            ProgressView()
                                .tint(.black)
                        }

                        Text(isEnding ? "Ending..." : "End Live")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isEnding)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    @ViewBuilder
    private var mediaLayer: some View {
        if let player {
            PlayerLayerView(player: player)
                .ignoresSafeArea()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.23, green: 0.09, blue: 0.34),
                        Color(red: 0.08, green: 0.03, blue: 0.12),
                        Color.black,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 14) {
                    Image(systemName: currentStream.isLive ? "dot.radiowaves.left.and.right" : "play.slash.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))

                    Text(currentStream.playbackStateTitle)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(placeholderDescription)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(.top, 70)
            }
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(currentStream.relativeStartedAt)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Text(currentStream.title)
                .font(.title2.bold())
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                if isOwner {
                    Text(currentStream.creatorHandle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.84))
                } else {
                    Button {
                        selectedCreatorRoute = FeedCreatorRoute(creatorId: currentStream.creatorId)
                    } label: {
                        Text(currentStream.creatorHandle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.84))
                    }
                    .buttonStyle(.plain)
                }

                if currentStream.isGettingReadyStream {
                    Text("• Getting ready")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                } else if let venueName = currentStream.venueName {
                    Text("• \(venueName)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            HStack(spacing: 10) {
                detailPill(systemImage: "eye.fill", title: "\(currentStream.viewerCount) watching")

                if currentStream.isGettingReadyStream {
                    detailPill(systemImage: "house.fill", title: "Getting ready")
                } else if let venueLocation = currentStream.venueShortLocation {
                    detailPill(systemImage: "location.fill", title: venueLocation)
                }

                if let provider = currentStream.provider, !provider.isEmpty {
                    detailPill(systemImage: "dot.radiowaves.left.and.right", title: provider.capitalized)
                }
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func detailPill(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
    }

    private var placeholderDescription: String {
        if currentStream.playbackURL != nil {
            return "Connecting to the live playback..."
        }
        if currentStream.isLive {
            return "This live session doesn't have a playback URL yet."
        }
        return "This live session is no longer broadcasting."
    }

    private func configurePlayerIfNeeded() {
        guard let playbackURL = currentStream.playbackURL else {
            player?.pause()
            player = nil
            return
        }

        let nextPlayer = AVPlayer(url: playbackURL)
        nextPlayer.automaticallyWaitsToMinimizeStalling = true
        nextPlayer.play()
        player = nextPlayer
    }

    private func endStream() async {
        guard !isEnding else { return }
        isEnding = true
        errorMessage = nil
        defer { isEnding = false }

        guard let currentUserId = await SupabaseManager.shared.currentUserId() else {
            errorMessage = "You need to be signed in to end this live."
            return
        }

        do {
            currentStream = try await service.endLiveStream(
                streamId: currentStream.id,
                userId: currentUserId
            )
            NotificationCenter.default.post(name: .pulseDidCreatePost, object: nil)
            onEnded?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
