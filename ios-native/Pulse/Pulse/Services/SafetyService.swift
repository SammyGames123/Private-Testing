import Foundation
import Supabase

/// Block / report / privacy controls.
///
/// The blocked-ID set is cached in memory and refreshed from Supabase on
/// demand. Feed code consults `isBlocked(_:)` during decoding to hide
/// content client-side; the DB is the ultimate source of truth, and a
/// follow-up migration can tighten RLS to exclude blocked rows server-side.
///
/// Symmetric block semantics: once A blocks B, neither A nor B can see the
/// other's content. We enforce A's side client-side (we hold A's block
/// list). B's side is enforced by the RPC `is_blocked_between` — when B
/// writes a comment or DM, server-side logic can check and refuse.
@MainActor
final class SafetyService: ObservableObject {
    static let shared = SafetyService()

    @Published private(set) var blockedUserIds: Set<String> = []
    @Published private(set) var isLoaded = false

    private let client = SupabaseManager.shared.client
    private var hasFetched = false

    private init() {}

    // MARK: - Blocked IDs cache

    /// Fetch the caller's block list. Cached per session; pass
    /// `forceRefresh: true` after a mutation to repopulate.
    func refreshBlockedUsers(forceRefresh: Bool = false) async {
        if hasFetched, !forceRefresh { return }
        do {
            struct Row: Decodable { let blocked_id: String }
            let rows: [Row] = try await client
                .rpc("get_my_blocked_user_ids")
                .execute()
                .value
            blockedUserIds = Set(rows.map { $0.blocked_id.lowercased() })
            isLoaded = true
            hasFetched = true
        } catch {
            // Non-fatal: feeds still work, they just won't filter until a
            // later refresh lands. The alternative — failing feeds hard on
            // a transient RPC error — is worse UX.
            isLoaded = true
        }
    }

    /// Cheap synchronous check for feed filtering. Lowercase-compared.
    func isBlocked(_ userId: String?) -> Bool {
        guard let userId else { return false }
        return blockedUserIds.contains(userId.lowercased())
    }

    /// Sign-out or account-switch should drop the cache so the next user
    /// doesn't inherit the previous user's block list.
    func reset() {
        blockedUserIds = []
        isLoaded = false
        hasFetched = false
    }

    // MARK: - Block / unblock

    func block(userId: String) async throws {
        guard let me = await SupabaseManager.shared.currentUserId() else {
            throw SafetyError.notAuthenticated
        }
        let normalized = userId.lowercased()
        guard normalized != me.lowercased() else {
            throw SafetyError.cannotBlockSelf
        }

        struct Insert: Encodable {
            let blocker_id: String
            let blocked_id: String
        }

        _ = try await client
            .from("user_blocks")
            .insert(Insert(blocker_id: me, blocked_id: normalized))
            .execute()

        blockedUserIds.insert(normalized)
    }

    func unblock(userId: String) async throws {
        guard let me = await SupabaseManager.shared.currentUserId() else {
            throw SafetyError.notAuthenticated
        }
        let normalized = userId.lowercased()

        _ = try await client
            .from("user_blocks")
            .delete()
            .eq("blocker_id", value: me)
            .eq("blocked_id", value: normalized)
            .execute()

        blockedUserIds.remove(normalized)
    }

    /// Resolve the blocked-IDs set to a list of profiles so the settings
    /// screen can render names/avatars, not raw UUIDs.
    func fetchBlockedProfiles() async throws -> [UserProfile] {
        await refreshBlockedUsers(forceRefresh: true)
        guard !blockedUserIds.isEmpty else { return [] }

        let ids = Array(blockedUserIds)
        let profiles: [UserProfile] = try await client
            .from("profiles")
            .select("id, email, username, display_name, avatar_url, bio")
            .in("id", values: ids)
            .execute()
            .value
        return profiles
    }

    // MARK: - Report

    func report(
        target: ReportTarget,
        category: ReportCategory,
        note: String?
    ) async throws {
        guard let me = await SupabaseManager.shared.currentUserId() else {
            throw SafetyError.notAuthenticated
        }

        struct Insert: Encodable {
            let reporter_id: String
            let target_user_id: String?
            let target_video_id: String?
            let target_comment_id: String?
            let target_live_stream_id: String?
            let category: String
            let note: String?
        }

        struct InsertedReport: Decodable {
            let id: String
        }

        let row = Insert(
            reporter_id: me,
            target_user_id: target.userId,
            target_video_id: target.videoId,
            target_comment_id: target.commentId,
            target_live_stream_id: target.liveStreamId,
            category: category.rawValue,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        )

        let report: InsertedReport = try await client
            .from("content_reports")
            .insert(row, returning: .representation)
            .select("id")
            .single()
            .execute()
            .value

        Task {
            try? await ModerationNotificationService.shared.notifyReportCreated(reportId: report.id)
        }
    }

    // MARK: - Private account

    func setProfilePrivate(_ isPrivate: Bool) async throws {
        guard let me = await SupabaseManager.shared.currentUserId() else {
            throw SafetyError.notAuthenticated
        }

        struct Update: Encodable { let is_private: Bool }

        _ = try await client
            .from("profiles")
            .update(Update(is_private: isPrivate))
            .eq("id", value: me)
            .execute()
    }
}

final class ModerationNotificationService {
    static let shared = ModerationNotificationService()

    private init() {}

    func notifyReportCreated(reportId: String) async throws {
        guard let accessToken = await SupabaseManager.shared.currentAccessToken() else { return }
        guard let requestURL = makeFunctionURL(path: "notify-report") else { return }

        struct Payload: Encodable {
            let report_id: String
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(Payload(report_id: reportId))

        _ = try await URLSession.shared.data(for: request)
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
}

// MARK: - Report targets / categories

enum ReportCategory: String, CaseIterable, Identifiable {
    case spam
    case harassment
    case nudity
    case violence
    case hate
    case selfHarm = "self_harm"
    case illegal
    case impersonation
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam:          return "Spam or scam"
        case .harassment:    return "Harassment or bullying"
        case .nudity:        return "Nudity or sexual content"
        case .violence:      return "Violence or gore"
        case .hate:          return "Hate speech"
        case .selfHarm:      return "Self-harm or suicide"
        case .illegal:       return "Illegal activity"
        case .impersonation: return "Impersonation"
        case .other:         return "Something else"
        }
    }
}

/// A report can target a user, a video, a comment, or a live stream.
/// Exactly one field is non-nil.
struct ReportTarget {
    let userId: String?
    let videoId: String?
    let commentId: String?
    let liveStreamId: String?

    static func user(_ id: String) -> ReportTarget {
        ReportTarget(userId: id.lowercased(), videoId: nil, commentId: nil, liveStreamId: nil)
    }

    static func video(_ id: String) -> ReportTarget {
        ReportTarget(userId: nil, videoId: id, commentId: nil, liveStreamId: nil)
    }

    static func comment(_ id: String) -> ReportTarget {
        ReportTarget(userId: nil, videoId: nil, commentId: id, liveStreamId: nil)
    }

    static func liveStream(_ id: String) -> ReportTarget {
        ReportTarget(userId: nil, videoId: nil, commentId: nil, liveStreamId: id.lowercased())
    }
}

enum SafetyError: LocalizedError {
    case notAuthenticated
    case cannotBlockSelf

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You need to be signed in."
        case .cannotBlockSelf:  return "You can't block yourself."
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
