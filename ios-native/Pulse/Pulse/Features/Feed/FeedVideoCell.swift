import SwiftUI
import AVFoundation
import AVKit

/// One full-screen slide in the vertical feed. Owns its own
/// `LoopingPlayer` so we can spin up / tear down AVPlayer as the cell
/// scrolls in and out of view — keeps decoder pressure low.
struct FeedVideoCell: View {
    let video: FeedVideo
    let isActive: Bool

    @StateObject private var player = LoopingPlayer()

    var body: some View {
        ZStack {
            Color.black

            if let avPlayer = player.player {
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

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
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
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
        }
        .task(id: video.id) {
            player.load(url: video.playbackURL)
            if isActive { player.play() }
        }
        .onChange(of: isActive) { _, active in
            if active {
                player.load(url: video.playbackURL)
                player.play()
            } else {
                player.pause()
            }
        }
        .onDisappear {
            player.tearDown()
        }
    }
}

/// Minimal AVPlayer wrapper that loops when the item hits end of
/// stream. Exposed as an ObservableObject so the cell can react to
/// the player becoming non-nil.
@MainActor
final class LoopingPlayer: ObservableObject {
    @Published private(set) var player: AVPlayer?

    private var loopObserver: NSObjectProtocol?
    private var currentURL: URL?

    func load(url: URL?) {
        guard let url else { return }
        if currentURL == url, player != nil { return }
        tearDown()

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .none
        newPlayer.automaticallyWaitsToMinimizeStalling = true

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        player = newPlayer
        currentURL = url
    }

    func play() { player?.play() }
    func pause() { player?.pause() }

    func tearDown() {
        player?.pause()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        player?.replaceCurrentItem(with: nil)
        player = nil
        currentURL = nil
    }

    deinit {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
    }
}

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
