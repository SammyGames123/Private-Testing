import Foundation
import AVFoundation

/// Keeps a small ring of live `AVPlayer`s for the active slide and
/// its immediate neighbours so the next video is already buffered
/// when the user flicks. Everything outside the [active-1, active+1]
/// window is torn down so the decoder budget stays bounded.
@MainActor
final class FeedPlayerPool: ObservableObject {
    private static let lockedPlaybackKey = "spilltop.lockedDoubleSpeedPlayback"

    /// Bumps every time a player is added or removed so observing
    /// cells can re-render and pick up their newly-available player.
    @Published private(set) var generation: Int = 0

    private var players: [String: AVPlayer] = [:]
    private var loopObservers: [String: NSObjectProtocol] = [:]
    private var activeVideoId: String?
    private var manuallyPausedVideoIds = Set<String>()
    private var isPlaybackSuspended = false
    @Published private(set) var lockedDoubleSpeedEnabled = UserDefaults.standard.bool(forKey: lockedPlaybackKey)
    @Published private(set) var temporarilyFastForwardingVideoId: String?

    func player(for videoId: String) -> AVPlayer? {
        players[videoId]
    }

    func isPaused(videoId: String) -> Bool {
        manuallyPausedVideoIds.contains(videoId)
    }

    func isFastForwarding(videoId: String) -> Bool {
        activeVideoId == videoId && (lockedDoubleSpeedEnabled || temporarilyFastForwardingVideoId == videoId)
    }

    var activePlaybackSpeedLabel: String? {
        guard !isPlaybackSuspended else { return nil }
        guard let activeVideoId else { return nil }
        guard isFastForwarding(videoId: activeVideoId) else { return nil }
        return lockedDoubleSpeedEnabled ? "2x Locked" : "2x"
    }

    func suspendPlayback() {
        guard !isPlaybackSuspended else { return }
        isPlaybackSuspended = true
        for (_, player) in players {
            player.pause()
        }
        generation &+= 1
    }

    func resumePlayback() {
        guard isPlaybackSuspended else { return }
        isPlaybackSuspended = false
        if let activeVideoId {
            applyPlaybackState(for: activeVideoId)
        }
        generation &+= 1
    }

    func togglePlayback(for videoId: String) {
        guard activeVideoId == videoId, players[videoId] != nil else { return }

        if manuallyPausedVideoIds.contains(videoId) {
            manuallyPausedVideoIds.remove(videoId)
        } else {
            manuallyPausedVideoIds.insert(videoId)
        }

        applyPlaybackState(for: videoId)
        generation &+= 1
    }

    func beginFastForwardHold(for videoId: String) {
        guard activeVideoId == videoId, players[videoId] != nil, !isPaused(videoId: videoId) else { return }
        temporarilyFastForwardingVideoId = videoId
        applyPlaybackState(for: videoId)
        generation &+= 1
    }

    func endFastForwardHold(for videoId: String) {
        guard temporarilyFastForwardingVideoId == videoId else { return }
        temporarilyFastForwardingVideoId = nil
        applyPlaybackState(for: videoId)
        generation &+= 1
    }

    func toggleLockedDoubleSpeed(for videoId: String) {
        guard activeVideoId == videoId, players[videoId] != nil else { return }
        lockedDoubleSpeedEnabled.toggle()
        if !lockedDoubleSpeedEnabled {
            temporarilyFastForwardingVideoId = nil
        }
        UserDefaults.standard.set(lockedDoubleSpeedEnabled, forKey: Self.lockedPlaybackKey)
        applyPlaybackState(for: videoId)
        generation &+= 1
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
        if activeVideoId != activeId {
            temporarilyFastForwardingVideoId = nil
        }
        activeVideoId = activeId
        for (id, player) in players {
            if id == activeId {
                player.seek(to: .zero)
                applyPlaybackState(for: id)
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
        activeVideoId = nil
        temporarilyFastForwardingVideoId = nil
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
        ) { [weak self, weak player] _ in
            player?.seek(to: .zero)
            Task { @MainActor [weak self] in
                self?.applyPlaybackState(for: videoId)
            }
        }
        loopObservers[videoId] = obs
        players[videoId] = player
    }

    private func applyPlaybackState(for videoId: String) {
        guard let player = players[videoId] else { return }
        guard activeVideoId == videoId else {
            player.pause()
            return
        }
        guard !isPlaybackSuspended else {
            player.pause()
            return
        }
        guard !manuallyPausedVideoIds.contains(videoId) else {
            player.pause()
            return
        }

        player.playImmediately(atRate: effectivePlaybackRate(for: videoId))
    }

    private func effectivePlaybackRate(for videoId: String) -> Float {
        isFastForwarding(videoId: videoId) ? 2.0 : 1.0
    }

    private func teardown(id: String) {
        players[id]?.pause()
        players[id]?.replaceCurrentItem(with: nil)
        manuallyPausedVideoIds.remove(id)
        if temporarilyFastForwardingVideoId == id {
            temporarilyFastForwardingVideoId = nil
        }
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
