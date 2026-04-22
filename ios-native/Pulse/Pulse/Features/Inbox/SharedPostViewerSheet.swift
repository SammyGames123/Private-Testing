import SwiftUI
import AVFoundation
import AVKit

/// Full-screen viewer opened when the recipient taps a shared-post
/// bubble in a DM. Fetches the full `FeedVideo` on appear so the bubble
/// payload can stay small. Shows the media (AVPlayer for video,
/// `ResilientFeedImageView` for image) with a minimal dismiss + creator
/// overlay — no rail, no comments. If the post has been deleted or is
/// not visible under RLS, surfaces an "unavailable" state.
struct SharedPostViewerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let videoId: String
    /// Used as a placeholder while the full post loads, so the viewer
    /// opens with the same thumbnail/title the recipient saw in chat.
    let fallbackPreview: SharedVideoPreview?

    @StateObject private var model: Model

    init(videoId: String, fallbackPreview: SharedVideoPreview? = nil) {
        self.videoId = videoId
        self.fallbackPreview = fallbackPreview
        _model = StateObject(wrappedValue: Model(videoId: videoId))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let video = model.video {
                content(for: video)
            } else if model.isUnavailable {
                unavailableState
            } else {
                loadingState
            }

            VStack {
                header
                Spacer()
            }
        }
        .task {
            await model.load()
        }
        .onDisappear {
            model.teardown()
        }
    }

    // MARK: - Media

    @ViewBuilder
    private func content(for video: FeedVideo) -> some View {
        ZStack(alignment: .bottom) {
            Color.black
                .overlay { mediaLayer(for: video) }
                .clipped()
                .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .allowsHitTesting(false)
            .ignoresSafeArea()

            bottomCopy(for: video)
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
        }
        .onTapGesture {
            model.togglePlayback()
        }
    }

    @ViewBuilder
    private func mediaLayer(for video: FeedVideo) -> some View {
        if video.mediaKind == .image {
            ResilientFeedImageView(
                primaryURL: video.optimizedPlaybackImageURL(width: 1440, quality: 84),
                fallbackURL: video.playbackURL,
                contentMode: .fit
            )
        } else if let player = model.player {
            PlayerLayerView(player: player)
        } else if let thumbURL = video.optimizedThumbnailURL(width: 960, height: 1706, quality: 74) {
            AsyncImage(url: thumbURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.black
            }
        }
    }

    private func bottomCopy(for video: FeedVideo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                creatorAvatar(for: video)
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.creatorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(video.creatorHandle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
            }

            Text(video.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)

            if let caption = video.caption, !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(3)
            }
        }
    }

    private func creatorAvatar(for video: FeedVideo) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 36, height: 36)

            if let avatarURL = video.creatorAvatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(video.creatorInitial)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                Text(video.creatorInitial)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
        }
        .overlay(
            Circle().stroke(.white.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Shared post")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())

            Spacer()

            // Invisible spacer so the title stays centered.
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            if let fallback = fallbackPreview, let thumb = fallback.thumbnailURL {
                AsyncImage(url: thumb) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(0.35)
                } placeholder: {
                    Color.black
                }
                .ignoresSafeArea()
            }
            ProgressView()
                .tint(.white)
            Text("Loading post…")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableState: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
            Text("Post unavailable")
                .font(.headline)
                .foregroundStyle(.white)
            Text("This post has been deleted or is no longer visible.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Model

@MainActor
private final class Model: ObservableObject {
    @Published private(set) var video: FeedVideo?
    @Published private(set) var isUnavailable = false
    @Published private(set) var player: AVPlayer?

    private let videoId: String
    private let service = FeedService.shared
    private var didLoad = false

    init(videoId: String) {
        self.videoId = videoId
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        do {
            let fetched = try await service.fetchVideo(id: videoId)
            if let fetched {
                video = fetched
                preparePlayer(for: fetched)
            } else {
                isUnavailable = true
            }
        } catch {
            isUnavailable = true
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func teardown() {
        player?.pause()
        player = nil
    }

    private func preparePlayer(for video: FeedVideo) {
        guard video.mediaKind == .video, let url = video.playbackURL else {
            return
        }
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = false
        // Loop playback so the recipient can watch it through multiple times
        // without fiddling with controls.
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }
        player = newPlayer
        newPlayer.play()
    }
}
