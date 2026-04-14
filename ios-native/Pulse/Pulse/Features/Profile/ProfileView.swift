import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authState: AuthState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Profile")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                if let email = authState.session?.user.email {
                    Text(email)
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.subheadline)
                }

                Button {
                    Task { await authState.signOut() }
                } label: {
                    Text("Sign out")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.12))
                        )
                }
                .padding(.top, 8)
            }
        }
    }
}
