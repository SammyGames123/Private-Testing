import SwiftUI
import AVFoundation
import UIKit

/// Full-bleed looping video background. Silent, seam-free loop (AVPlayerLooper
/// avoids the black flash you get from restarting a single AVPlayer), and uses
/// the `.ambient` audio session with `.mixWithOthers` so it never interrupts
/// whatever the user is already listening to.
///
/// If the named resource isn't bundled, the view quietly falls back to black
/// so the rest of the screen still renders — useful during development.
struct LoopingVideoBackground: UIViewRepresentable {
    let resourceName: String
    let resourceExtension: String

    func makeUIView(context: Context) -> LoopingVideoUIView {
        LoopingVideoUIView(resourceName: resourceName, resourceExtension: resourceExtension)
    }

    func updateUIView(_ uiView: LoopingVideoUIView, context: Context) {}
}

final class LoopingVideoUIView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()

    init(resourceName: String, resourceExtension: String) {
        super.init(frame: .zero)
        backgroundColor = .black
        configure(resourceName: resourceName, resourceExtension: resourceExtension)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(resourceName: String, resourceExtension: String) {
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension
        ) else {
            return
        }

        // `.ambient` + `.mixWithOthers` keeps whatever music the user is
        // already playing audible. This is a background mood video — it must
        // never steal the audio session.
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none

        // Looper owns the seamless wrap-around; keep a strong reference or it
        // deallocates and the loop stops after one play-through.
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        player = queuePlayer

        playerLayer.player = queuePlayer
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)

        queuePlayer.play()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleForeground() {
        player?.play()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        player?.pause()
    }
}
