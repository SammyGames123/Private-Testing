import SwiftUI
import AVFoundation

/// One full-screen slide in the vertical feed. The AVPlayer is owned
/// by `FeedPlayerPool` — the cell just reads whatever's assigned to
/// its video id. Everything below is thin presentation + callbacks.
struct FeedVideoCell: View {
    let video: FeedVideo
    @ObservedObject var pool: FeedPlayerPool
    @ObservedObject var model: FeedViewModel
    let onShowComments: () -> Void
    let onShowCreator: () -> Void

    @State private var shareItems: [Any] = []
    @State private var isShowingShareSheet = false
    @State private var isShowingInAppShareSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Media fills the whole cell and bleeds into the safe
            // area, so images/video go edge-to-edge behind the tab
            // bar.
            Color.black
                .overlay { mediaLayer }
                .clipped()
                .ignoresSafeArea()

            // Legibility gradient, anchored to the bottom of the cell.
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 280)
            .allowsHitTesting(false)
            .ignoresSafeArea()

            if video.mediaKind == .video {
                PlaybackGestureOverlay(
                    onTogglePlayback: { pool.togglePlayback(for: video.id) },
                    onBeginFastForwardHold: { pool.beginFastForwardHold(for: video.id) },
                    onEndFastForwardHold: { pool.endFastForwardHold(for: video.id) },
                    onToggleLockedFastForward: { pool.toggleLockedDoubleSpeed(for: video.id) }
                )

                if pool.isPaused(videoId: video.id) {
                    PlaybackPausedIndicator()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }

            // Chrome stays inside the safe area so it sits ABOVE the
            // tab bar regardless of whether the media is image or
            // video.
            // FeedView ignores safe area so the cell spans the whole
            // screen including behind the tab bar. Pad enough to
            // clear a standard 49pt tab bar + 34pt home indicator
            // safe area + breathing room.
            HStack(alignment: .bottom) {
                bottomCopy
                Spacer(minLength: 12)
                rightRail
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $isShowingShareSheet) {
            PulseActivitySheet(activityItems: shareItems)
        }
        .sheet(isPresented: $isShowingInAppShareSheet) {
            ShareMomentSheet(video: video) {
                presentExternalShareSheet()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
    }

    @ViewBuilder
    private var mediaLayer: some View {
        if video.mediaKind == .image {
            ResilientFeedImageView(
                primaryURL: video.optimizedPlaybackImageURL(width: 1440, quality: 84),
                fallbackURL: video.playbackURL,
                contentMode: .fit
            )
        } else if let avPlayer = pool.player(for: video.id) {
            PlayerLayerView(player: avPlayer)
        } else if let thumb = video.optimizedThumbnailURL(width: 960, height: 1706, quality: 74) {
            AsyncImage(url: thumb) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.black
            }
        }
    }

    // MARK: - Bottom copy

    private var bottomCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let momentLabel = video.momentLabel {
                momentBadge(title: momentLabel)
            }

            Button(action: onShowCreator) {
                Text(video.creatorHandle)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Text(video.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)

            if video.isOutNowMoment, let venueName = video.venueName {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.purple.opacity(0.94))

                    Text(venueName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    if let venueShortLocation = video.venueShortLocation {
                        Text("• \(venueShortLocation)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.56))
                    }
                }
            }

            if let caption = video.caption, !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
    }

    private func momentBadge(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(video.isOutNowMoment ? Color.orange : Color.purple.opacity(0.94))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (video.isOutNowMoment ? Color.orange : Color.purple)
                    .opacity(0.16)
            )
            .clipShape(Capsule())
    }

    // MARK: - Right rail

    private var rightRail: some View {
        VStack(spacing: 18) {
            creatorAvatar
            railButton(
                system: model.isLiked(video) ? "heart.fill" : "heart",
                tint: model.isLiked(video) ? .red : .white,
                count: model.likeCount(for: video),
                action: { model.toggleLike(video) }
            )
            railButton(
                system: "bubble.right.fill",
                tint: .white,
                count: model.commentCount(for: video),
                action: onShowComments
            )
            railButton(
                system: "paperplane.fill",
                tint: .white,
                action: presentInAppShareSheet
            )
        }
    }

    private var creatorAvatar: some View {
        let following = model.isFollowing(video.creatorId)
        let canFollow = model.canFollow(creatorId: video.creatorId)
        return ZStack(alignment: .bottom) {
            Button(action: onShowCreator) {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay {
                        if let avatarURL = video.creatorAvatarURL {
                            AsyncImage(url: avatarURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                default:
                                    Text(video.creatorInitial)
                                        .font(.headline.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .clipShape(Circle())
                        } else {
                            Text(video.creatorInitial)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay(
                        Circle().stroke(.white.opacity(0.6), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if canFollow && !following {
                Button {
                    model.toggleFollow(creatorId: video.creatorId)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .offset(y: 10)
            }
        }
        .padding(.bottom, canFollow && !following ? 10 : 0)
    }

    private func railButton(
        system: String,
        tint: Color,
        count: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: count == nil ? 0 : 4) {
                Image(systemName: system)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(tint)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)

                if let count {
                    Text(Self.format(count: count))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Primary share action — opens the in-app picker first. The user can
    /// pivot to the system share sheet from inside that picker, which
    /// calls back into `presentExternalShareSheet`.
    private func presentInAppShareSheet() {
        isShowingInAppShareSheet = true
    }

    /// Native iOS share sheet (Instagram, Messages, Facebook, etc.). Kept
    /// as a fallback off the in-app picker. Preserves the original
    /// payload format so nothing about the external-share UX changes.
    private func presentExternalShareSheet() {
        var items: [Any] = ["\(video.creatorHandle) on Spilltop\n\(video.title)"]

        if let caption = video.caption, !caption.isEmpty {
            items[0] = "\(items[0])\n\(caption)"
        }

        if let playbackURL = video.playbackURL {
            items.append(playbackURL)
        }

        shareItems = items
        isShowingShareSheet = true
    }

    private static func format(count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - AVPlayerLayer host

/// UIView-backed AVPlayerLayer so we get `.resizeAspectFill` without
/// AVPlayerViewController's system chrome.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct ResilientFeedImageView: View {
    let primaryURL: URL?
    let secondaryURL: URL?
    let fallbackURL: URL?
    let contentMode: ContentMode

    @State private var image: UIImage?

    init(primaryURL: URL?, secondaryURL: URL? = nil, fallbackURL: URL?, contentMode: ContentMode = .fill) {
        self.primaryURL = primaryURL
        self.secondaryURL = secondaryURL
        self.fallbackURL = fallbackURL
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: taskIdentifier) {
            image = await Self.loadImage(
                primaryURL: primaryURL,
                secondaryURL: secondaryURL,
                fallbackURL: fallbackURL
            )
        }
    }

    private var taskIdentifier: String {
        "\(primaryURL?.absoluteString ?? "none")|\(secondaryURL?.absoluteString ?? "none")|\(fallbackURL?.absoluteString ?? "none")"
    }

    private static func loadImage(primaryURL: URL?, fallbackURL: URL?) async -> UIImage? {
        await loadImage(primaryURL: primaryURL, secondaryURL: nil, fallbackURL: fallbackURL)
    }

    private static func loadImage(primaryURL: URL?, secondaryURL: URL?, fallbackURL: URL?) async -> UIImage? {
        for candidateURL in [primaryURL, secondaryURL, fallbackURL] {
            guard let candidateURL else { continue }
            if let image = await loadImage(from: candidateURL) {
                return image
            }
        }
        return nil
    }

    private static func loadImage(from url: URL) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

struct PlaybackGestureOverlay: View {
    let onTogglePlayback: () -> Void
    let onBeginFastForwardHold: () -> Void
    let onEndFastForwardHold: () -> Void
    let onToggleLockedFastForward: () -> Void

    @State private var fastForwardTouchStartedAt: Date?
    @State private var isFastForwardHoldActive = false
    @State private var didToggleLockInCurrentGesture = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTogglePlayback)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.2, maximumDistance: 24)
                            .onEnded { _ in
                                onTogglePlayback()
                            }
                    )

                HStack {
                    fastForwardZone(geometry: geometry, alignment: .leading)
                    Spacer(minLength: 0)
                    fastForwardZone(geometry: geometry, alignment: .trailing)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func fastForwardZone(geometry: GeometryProxy, alignment: HorizontalAlignment) -> some View {
        Color.clear
            .frame(
                width: min(max(geometry.size.width * 0.18, 78), 96),
                height: min(max(geometry.size.height * 0.22, 150), 220)
            )
            .contentShape(Rectangle())
            .padding(alignment == .leading ? .leading : .trailing, 4)
            .offset(y: -geometry.size.height * 0.08)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if fastForwardTouchStartedAt == nil {
                            fastForwardTouchStartedAt = Date()
                        }

                        if !isFastForwardHoldActive,
                           let fastForwardTouchStartedAt,
                           Date().timeIntervalSince(fastForwardTouchStartedAt) >= 0.12 {
                            isFastForwardHoldActive = true
                            onBeginFastForwardHold()
                        }

                        if isFastForwardHoldActive,
                           value.translation.height >= 72,
                           !didToggleLockInCurrentGesture {
                            didToggleLockInCurrentGesture = true
                            onToggleLockedFastForward()
                        }
                    }
                    .onEnded { _ in
                        if isFastForwardHoldActive {
                            onEndFastForwardHold()
                        }
                        resetFastForwardGestureState()
                    }
            )
    }

    private func resetFastForwardGestureState() {
        fastForwardTouchStartedAt = nil
        isFastForwardHoldActive = false
        didToggleLockInCurrentGesture = false
    }
}

struct PlaybackPausedIndicator: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 74, height: 74)
            .background(Color.black.opacity(0.42))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
    }
}

struct PlaybackSpeedBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "forward.fill")
                .font(.caption.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.45))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct PulseActivitySheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
