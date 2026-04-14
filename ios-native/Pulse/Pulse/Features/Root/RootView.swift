import SwiftUI

/// Decides which top-level screen to show based on auth state.
struct RootView: View {
    @EnvironmentObject private var authState: AuthState

    var body: some View {
        Group {
            if authState.isLoading {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            } else if authState.session != nil {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}
