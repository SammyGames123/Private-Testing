import Foundation

enum LiveKitParticipantRole: String, Codable, Hashable {
    case publisher
    case subscriber
}

struct LiveKitSessionDescriptor: Decodable, Hashable {
    let wsURLString: String
    let token: String
    let roomName: String
    let participantIdentity: String
    let participantName: String?
    let role: LiveKitParticipantRole

    enum CodingKeys: String, CodingKey {
        case wsURLString = "ws_url"
        case token
        case roomName = "room_name"
        case participantIdentity = "participant_identity"
        case participantName = "participant_name"
        case role
    }

    var wsURL: String {
        wsURLString
    }
}

enum LiveKitServiceError: LocalizedError {
    case missingAuthSession
    case malformedFunctionsURL
    case invalidResponse
    case backendNotConfigured(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthSession:
            return "You need to be signed in before joining a live room."
        case .malformedFunctionsURL:
            return "LiveKit session endpoint isn't configured correctly."
        case .invalidResponse:
            return "LiveKit returned an invalid session response."
        case .backendNotConfigured(let message):
            return message
        case .requestFailed(let message):
            return message
        }
    }
}

final class LiveKitService {
    static let shared = LiveKitService()

    private init() {}

    func fetchSession(for stream: LiveStream, as role: LiveKitParticipantRole) async throws -> LiveKitSessionDescriptor {
        guard let accessToken = await SupabaseManager.shared.currentAccessToken() else {
            throw LiveKitServiceError.missingAuthSession
        }

        guard let requestURL = makeFunctionURL(path: "livekit-session") else {
            throw LiveKitServiceError.malformedFunctionsURL
        }

        struct RequestBody: Encodable {
            let stream_id: String
            let role: String
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                stream_id: stream.id,
                role: role.rawValue
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiveKitServiceError.invalidResponse
        }

        if (200..<300).contains(httpResponse.statusCode) {
            do {
                return try JSONDecoder().decode(LiveKitSessionDescriptor.self, from: data)
            } catch {
                throw LiveKitServiceError.invalidResponse
            }
        }

        let message = errorMessage(from: data)
        if httpResponse.statusCode == 500 || httpResponse.statusCode == 501 {
            throw LiveKitServiceError.backendNotConfigured(message)
        }
        throw LiveKitServiceError.requestFailed(message)
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

        return "LiveKit session request failed."
    }
}
