import Foundation
import Supabase

/// Follow-request plumbing for private accounts.
///
/// A follow against a public profile is a direct insert into `follows`.
/// A follow against a private profile creates a row in `follow_requests`
/// that the target approves or rejects. Both paths are wrapped by the
/// `request_follow(target)` RPC so the client doesn't need to know which
/// way to go.
enum FollowRequestOutcome: String {
    case followed
    case requested
    case alreadyFollowing = "already_following"
    case alreadyRequested = "already_requested"
}

struct FollowRequestEntry: Identifiable, Decodable {
    let id: String
    let requesterId: String
    let createdAt: String
    let requester: UserProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case requesterId = "requester_id"
        case createdAt = "created_at"
        case requester = "requester"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        requesterId = try c.decode(String.self, forKey: .requesterId)
        createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        // Supabase embedded join returns either an object or an array;
        // decode both shapes so either works.
        if let single = try? c.decodeIfPresent(UserProfile.self, forKey: .requester) {
            requester = single
        } else if let array = try? c.decodeIfPresent([UserProfile].self, forKey: .requester) {
            requester = array.first
        } else {
            requester = nil
        }
    }
}

final class FollowRequestsService {
    static let shared = FollowRequestsService()

    private let client = SupabaseManager.shared.client

    private init() {}

    /// Follow a public account, or open a pending request against a private
    /// one. The caller shouldn't branch — just interpret the outcome.
    func requestOrFollow(targetId: String) async throws -> FollowRequestOutcome {
        struct Params: Encodable { let target: String }

        let raw: String = try await client
            .rpc("request_follow", params: Params(target: targetId.lowercased()))
            .execute()
            .value

        return FollowRequestOutcome(rawValue: raw) ?? .requested
    }

    /// Cancel a pending request the caller sent. No-op if one doesn't exist.
    func cancelRequest(targetId: String) async throws {
        guard let me = await SupabaseManager.shared.currentUserId() else { return }
        _ = try await client
            .from("follow_requests")
            .delete()
            .eq("requester_id", value: me)
            .eq("target_id", value: targetId.lowercased())
            .eq("status", value: "pending")
            .execute()
    }

    /// True when the caller has a pending request against `targetId`.
    func hasPendingRequest(targetId: String) async -> Bool {
        guard let me = await SupabaseManager.shared.currentUserId() else { return false }
        do {
            struct Row: Decodable { let id: String }
            let rows: [Row] = try await client
                .from("follow_requests")
                .select("id")
                .eq("requester_id", value: me)
                .eq("target_id", value: targetId.lowercased())
                .eq("status", value: "pending")
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    /// Pending requests against the current user, newest first.
    func fetchIncomingRequests() async throws -> [FollowRequestEntry] {
        let rows: [FollowRequestEntry] = try await client
            .from("follow_requests")
            .select("""
                id,
                requester_id,
                created_at,
                requester:requester_id (
                    id, email, username, display_name, avatar_url, bio
                )
                """)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }

    func approve(requestId: String) async throws {
        struct Params: Encodable { let request_id: String }
        _ = try await client
            .rpc("approve_follow_request", params: Params(request_id: requestId))
            .execute()
    }

    func reject(requestId: String) async throws {
        struct Params: Encodable { let request_id: String }
        _ = try await client
            .rpc("reject_follow_request", params: Params(request_id: requestId))
            .execute()
    }
}
