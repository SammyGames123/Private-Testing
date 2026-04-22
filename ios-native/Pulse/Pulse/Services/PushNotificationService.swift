import Foundation
import UIKit
import UserNotifications

/// Registers the device with APNs and upserts the resulting token into
/// `device_push_tokens` so server-side senders know where to deliver.
///
/// This file is the full client-side foundation. Actually *sending* a
/// push requires an APNs key and an Edge Function — neither of which
/// ships in the app binary. Until those land, the device-token row is
/// still useful: any future mass-send tooling can read them.
@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    private let client = SupabaseManager.shared.client

    /// Last token we uploaded, so we don't thrash the DB when the OS
    /// hands us the same token on every cold launch.
    private var lastUploadedToken: String?

    override private init() {
        super.init()
    }

    /// Ask the user for permission and, if granted, register with APNs.
    /// Safe to call repeatedly — the second call no-ops if we already
    /// have authorization.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                registerForRemoteNotifications()
            }
        case .authorized, .provisional, .ephemeral:
            registerForRemoteNotifications()
        case .denied:
            return
        @unknown default:
            return
        }
    }

    private func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Called from the AppDelegate adaptor once APNs hands us a token.
    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard token != lastUploadedToken else { return }
        lastUploadedToken = token

        Task { await uploadToken(token) }
    }

    private func uploadToken(_ token: String) async {
        guard let userId = await SupabaseManager.shared.currentUserId() else { return }

        struct Upsert: Encodable {
            let user_id: String
            let token: String
            let platform: String
            let app_version: String?
            let updated_at: String
        }

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        let row = Upsert(
            user_id: userId,
            token: token,
            platform: "ios",
            app_version: appVersion,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        do {
            _ = try await client
                .from("device_push_tokens")
                .upsert(row, onConflict: "user_id,token")
                .execute()
        } catch {
            // Non-fatal — we'll retry next launch. Don't surface to UI.
            print("[PushNotificationService] Token upload failed: \(error)")
        }
    }

    /// Wipes the caller's device rows. Call on sign-out to stop pushes
    /// from following the device to the next signed-in user.
    func clearTokenForCurrentUser() async {
        guard let userId = await SupabaseManager.shared.currentUserId() else { return }
        guard let token = lastUploadedToken else { return }

        _ = try? await client
            .from("device_push_tokens")
            .delete()
            .eq("user_id", value: userId)
            .eq("token", value: token)
            .execute()

        lastUploadedToken = nil
    }
}
