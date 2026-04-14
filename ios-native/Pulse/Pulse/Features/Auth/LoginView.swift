import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authState: AuthState

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var errorMessage: String?
    @State private var isWorking = false

    enum Mode {
        case signIn
        case signUp

        var ctaTitle: String {
            self == .signIn ? "Sign in" : "Create account"
        }

        var subtitle: String {
            self == .signIn ? "Sign in to your account" : "Create your account"
        }

        var toggleLabel: String {
            self == .signIn
                ? "Don't have an account? Sign up"
                : "Already have an account? Sign in"
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Text("Pulse")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)

                Text(mode.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                VStack(spacing: 12) {
                    field(
                        placeholder: "Email",
                        text: $email,
                        isSecure: false
                    )
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    field(
                        placeholder: "Password",
                        text: $password,
                        isSecure: true
                    )
                    .textContentType(mode == .signIn ? .password : .newPassword)
                }
                .padding(.top, 12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                Button(action: submit) {
                    ZStack {
                        if isWorking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(mode.ctaTitle)
                                .font(.body.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isWorking || email.isEmpty || password.isEmpty)
                .opacity((isWorking || email.isEmpty || password.isEmpty) ? 0.5 : 1)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = mode == .signIn ? .signUp : .signIn
                        errorMessage = nil
                    }
                } label: {
                    Text(mode.toggleLabel)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 4)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func field(placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        let prompt = Text(placeholder).foregroundColor(.white.opacity(0.4))
        Group {
            if isSecure {
                SecureField("", text: text, prompt: prompt)
            } else {
                TextField("", text: text, prompt: prompt)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.white)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.1))
        )
    }

    private func submit() {
        isWorking = true
        errorMessage = nil
        let currentMode = mode
        Task {
            do {
                if currentMode == .signIn {
                    try await authState.signIn(email: email, password: password)
                } else {
                    try await authState.signUp(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
