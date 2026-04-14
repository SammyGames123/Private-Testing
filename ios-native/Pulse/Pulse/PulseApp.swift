import SwiftUI
import AVFoundation

@main
struct PulseApp: App {
    @StateObject private var authState = AuthState()

    init() {
        // Feed playback should ignore the silent switch so videos
        // have audio like Instagram Reels / TikTok.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .moviePlayback
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authState)
                .task {
                    await authState.bootstrap()
                }
                .preferredColorScheme(.dark)
        }
    }
}
