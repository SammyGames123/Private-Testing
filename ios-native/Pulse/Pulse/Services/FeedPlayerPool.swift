import Foundation
import AVFoundation

/// Keeps a small ring of live `AVPlayer`s for the active slide and
/// its immediate neighbours so the next video is already buffered
/// when the user flicks. Everything outside the [active-1, active+1]
/// window is torn down so the decoder budget stays bounded.
@MainActor
final class FeedPlayerPool: ObservableObject {
    /// Bumps every time a player is added or removed so observing
    /// cells can re-render and pick up their newly-available player.
    @Published private(set) var generation: Int = 0

    private var players: [String: AVPlayer] = [:]
    private var loopObservers: [String: NSObjectProtocol] = [:]

    func player(for videoId: String) -> AVPlayer? {
        players[videoId]
    }

    /// Ensure live players for the current active video and its ±1
    /// neighbours, tear everything else down, and play only the
    /// active slot.
    func syncActiveWindow(videos: [FeedVideo], activeIndex: Int) {
        guard !videos.isEmpty, videos.indices.contains(activeIndex) else {
            tearDownAll()
            return
        }

        let lower = max(0, activeIndex - 1)
        let upper = min(videos.count - 1, activeIndex + 1)
        let wantedIds = Set((lower...upper).map { videos[$0].id })

        // Tear down anything no longer in the window.
        for (id, _) in players where !wantedIds.contains(id) {
            teardown(id: id)
        }

        // Spin up players for everything in the window. Skip image
        // posts — AVPlayer can't render them and the cell falls back
        // to AsyncImage.
        for idx in lower...upper {
            let video = videos[idx]
            guard video.mediaKind == .video, let url = video.playbackURL else { continue }
            if players[video.id] == nil {
                makePlayer(for: video.id, url: url)
            }
        }

        // Active one plays, neighbours pause at the start so they're
        // ready to go the instant you snap onto them.
        let activeId = videos[activeIndex].id
        for (id, player) in players {
            if id == activeId {
                player.seek(to: .zero)
                player.play()
            } else {
                player.pause()
                player.seek(to: .zero)
            }
        }

        generation &+= 1
    }

    func tearDownAll() {
        for id in Array(players.keys) {
            teardown(id: id)
        }
        generation &+= 1
    }

    // MARK: - Private

    private func makePlayer(for videoId: String, url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
        player.isMuted = false

        let obs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        loopObservers[videoId] = obs
        players[videoId] = player
    }

    private func teardown(id: String) {
        players[id]?.pause()
        players[id]?.replaceCurrentItem(with: nil)
        if let obs = loopObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(obs)
        }
        players.removeValue(forKey: id)
    }

    deinit {
        for (_, obs) in loopObservers {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
