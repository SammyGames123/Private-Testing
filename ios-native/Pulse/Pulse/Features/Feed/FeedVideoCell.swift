import SwiftUI
import AVFoundation

/// One full-screen slide in the vertical feed. The AVPlayer is owned
/// by `FeedPlayerPool` — the cell just reads whatever's assigned to
/// its video id. Everything below is thin presentation + callbacks.
struct FeedVideoCell: View {
    let video: FeedVideo
    @ObservedObject var pool: FeedPlayerPool
    @ObservedObject var model: FeedViewModel

    var body: some View {
        ZStack {
            Color.black

            if video.mediaKind == .image, let imageURL = video.playbackURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color.black
                    case .empty:
                        Color.black
                    @unknown default:
                        Color.black
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
            } else if let avPlayer = pool.player(for: video.id) {
                PlayerLayerView(player: avPlayer)
                    .ignoresSafeArea()
            } else if let thumb = video.thumbnailURL {
                AsyncImage(url: thumb) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.black
                    }
                }
                .ignoresSafeArea()
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            HStack(alignment: .bottom) {
                bottomCopy
                Spacer(minLength: 12)
                rightRail
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    // MARK: - Bottom copy

    private var bottomCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(video.creatorHandle)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Text(video.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
            if let caption = video.caption, !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Right rail

    private var rightRail: some View {
        VStack(spacing: 22) {
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
                count: video.commentsCount,
                action: { /* comments sheet next session */ }
            )
        }
    }

    private var creatorAvatar: some View {
        let following = model.isFollowing(video.creatorId)
        return ZStack(alignment: .bottom) {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 48, height: 48)
                .overlay(
                    Text(String(video.creatorHandle.dropFirst().prefix(1)).uppercased())
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                )
                .overlay(
                    Circle().stroke(.white.opacity(0.6), lineWidth: 1)
                )

            if !following {
                Button {
                    model.toggleFollow(creatorId: video.creatorId)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .offset(y: 10)
            }
        }
        .padding(.bottom, following ? 0 : 10)
    }

    private func railButton(
        system: String,
        tint: Color,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: system)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(tint)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                Text(Self.format(count: count))
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
            }
        }
        .buttonStyle(.plain)
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
