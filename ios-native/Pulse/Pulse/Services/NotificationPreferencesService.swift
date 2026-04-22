import Foundation

/// Mirrors the `spilltop.notif.*` `@AppStorage` toggles into the server-side
/// `notification_preferences` row so any push-sending Edge Function can
/// respect the user's preferences.
///
/// We don't read these values back here — `@AppStorage` is the local
/// source of truth for UI. This service only writes.
enum NotificationPreferencesService {
    static func upsert(
        likes: Bool,
        comments: Bool,
        follows: Bool,
        directMessages: Bool,
        liveStreams: Bool
    ) async {
        guard let userId = await SupabaseManager.shared.currentUserId() else { return }

        struct Row: Encodable {
            let user_id: String
            let likes: Bool
            let comments: Bool
            let follows: Bool
            let direct_messages: Bool
            let live_streams: Bool
            let updated_at: String
        }

        let row = Row(
            user_id: userId,
            likes: likes,
            comments: comments,
            follows: follows,
            direct_messages: directMessages,
            live_streams: liveStreams,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        _ = try? await SupabaseManager.shared.client
            .from("notification_preferences")
            .upsert(row, onConflict: "user_id")
            .execute()
    }
}
