import SwiftUI

@main
struct PulseApp: App {
    @StateObject private var authState = AuthState()

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
