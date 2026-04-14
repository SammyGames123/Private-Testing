import Foundation
import Supabase

/// Observable wrapper around the Supabase auth session. The whole
/// app reads from this to decide which root view to show.
@MainActor
final class AuthState: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = true

    private let client = SupabaseManager.shared.client

    /// Called once on app launch. Restores any persisted session and
    /// then keeps `session` in sync with auth state changes.
    func bootstrap() async {
        do {
            session = try await client.auth.session
        } catch {
            session = nil
        }
        isLoading = false

        for await (event, newSession) in client.auth.authStateChanges {
            _ = event
            session = newSession
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(
            email: email,
            password: password
        )
        self.session = session
    }

    func signUp(email: String, password: String) async throws {
        let response = try await client.auth.signUp(
            email: email,
            password: password
        )
        session = response.session
    }

    func signOut() async {
        try? await client.auth.signOut()
        session = nil
    }
}
