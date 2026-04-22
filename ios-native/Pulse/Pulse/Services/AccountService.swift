import Foundation

/// Account-level mutations that don't fit cleanly on FeedService or AuthState.
///
/// Currently just account deletion, which is a privileged operation that has
/// to run behind a service-role Edge Function (we can't delete auth.users
/// from the client). The function at `supabase/functions/delete-account`
/// does the real work — this type is just the client-side caller.
enum AccountServiceError: LocalizedError {
    case missingAuthSession
    case malformedFunctionsURL
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthSession:
            return "You need to be signed in."
        case .malformedFunctionsURL:
            return "Account endpoint isn't configured correctly."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .requestFailed(let message):
            return message
        }
    }
}

final class AccountService {
    static let shared = AccountService()

    private init() {}

    /// Deletes the current user's account. On success, the caller should
    /// drop local state and route back to the auth stack — the JWT is
    /// already invalidated server-side by the time this returns.
    func deleteMyAccount() async throws {
        guard let accessToken = await SupabaseManager.shared.currentAccessToken() else {
            throw AccountServiceError.missingAuthSession
        }

        guard let requestURL = makeFunctionURL(path: "delete-account") else {
            throw AccountServiceError.malformedFunctionsURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountServiceError.invalidResponse
        }

        if (200..<300).contains(httpResponse.statusCode) {
            return
        }

        throw AccountServiceError.requestFailed(errorMessage(from: data))
    }

    private func makeFunctionURL(path: String) -> URL? {
        guard var components = URLComponents(url: SupabaseConfig.url, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return nil
        }

        let projectRef = host.components(separatedBy: ".").first ?? host
        components.host = "\(projectRef).functions.supabase.co"
        components.path = "/\(path)"
        return components.url
    }

    private func errorMessage(from data: Data) -> String {
        struct ErrorPayload: Decodable {
            let error: String?
            let message: String?
        }

        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            if let message = payload.error, !message.isEmpty {
                return message
            }
            if let message = payload.message, !message.isEmpty {
                return message
            }
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        return "We couldn't delete your account. Try again in a moment."
    }
}
