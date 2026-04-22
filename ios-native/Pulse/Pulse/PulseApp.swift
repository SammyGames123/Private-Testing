import SwiftUI
import AVFoundation
import UIKit

/// AppDelegate adaptor exists only to catch APNs callbacks, which SwiftUI
/// doesn't expose directly. Everything else lives in the app entry point.
final class PulseAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[SpilltopApp] APNs registration failed: \(error)")
    }
}

@main
struct PulseApp: App {
    @UIApplicationDelegateAdaptor(PulseAppDelegate.self) private var appDelegate
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
