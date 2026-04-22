import Combine
import Foundation
import CoreLocation
import Supabase

/// Inputs for building a new post.
struct CreatePostRequest {
    let title: String
    let caption: String?
    let category: String?
    let venueId: String?
    let tagsInput: String?
    let mediaData: Data
    let thumbnailData: Data?
    let latitude: Double?
    let longitude: Double?
    let mapVisibility: MapMomentVisibility
    /// e.g. "video/mp4", "image/jpeg"
    let contentType: String
    /// e.g. "mp4", "jpg"
    let fileExtension: String
}

enum CreateServiceError: LocalizedError {
    case mediaUploadFailed(String)
    case videoInsertFailed(String)
    case tagInsertFailed(String)
    case cooldownActive(String)

    var errorDescription: String? {
        switch self {
        case .mediaUploadFailed(let message):
            return "Upload failed: \(message)"
        case .videoInsertFailed(let message):
            return "Video saved to storage, but creating the post failed: \(message)"
        case .tagInsertFailed(let message):
            return "Post created, but tags failed to save: \(message)"
        case .cooldownActive(let message):
            return message
        }
    }
}

/// Uploads media to Supabase Storage and inserts the `videos` row
/// plus any `video_tags` rows. Mirrors the web app's
/// `/videos/new/*` flow.
@MainActor
final class CreateService {
    static let shared = CreateService()

    private let client = SupabaseManager.shared.client

    private init() {}

    func createPost(_ request: CreatePostRequest) async throws {
        try ContentPolicy.validateUserText(request.title, request.caption, request.tagsInput)

        // 1. Who am I?
        let session = try await client.auth.session
        // Storage RLS compares folder names as lowercase text, while
        // `UUID.uuidString` is uppercase in Swift by default.
        let userId = session.user.id.uuidString.lowercased()

        try await assertCanCreateVenueMoment(
            userId: userId,
            venueId: request.venueId,
            category: request.category
        )

        // 2. Upload the media to the videos bucket.
        let baseName = Self.buildObjectBaseName()
        let path = Self.buildObjectPath(userId: userId, baseName: baseName, fileExtension: request.fileExtension)
        let thumbnailPath = request.thumbnailData == nil
            ? nil
            : Self.buildThumbnailPath(userId: userId, baseName: baseName)
        do {
            _ = try await client.storage
                .from("videos")
                .upload(
                    path,
                    data: request.mediaData,
                    options: FileOptions(
                        cacheControl: "31536000",
                        contentType: request.contentType,
                        upsert: false
                    )
                )

            if let thumbnailData = request.thumbnailData, let thumbnailPath {
                _ = try await client.storage
                    .from("videos")
                    .upload(
                        thumbnailPath,
                        data: thumbnailData,
                        options: FileOptions(
                            cacheControl: "31536000",
                            contentType: "image/jpeg",
                            upsert: false
                        )
                    )
            }
        } catch {
            throw CreateServiceError.mediaUploadFailed(error.localizedDescription)
        }

        // 3. Get the public URL for playback.
        let publicURL = try client.storage
            .from("videos")
            .getPublicURL(path: path)
        let thumbnailPublicURL: URL?
        if let thumbnailPath {
            thumbnailPublicURL = try client.storage
                .from("videos")
                .getPublicURL(path: thumbnailPath)
        } else {
            thumbnailPublicURL = nil
        }

        // 4. Insert the videos row.
        struct VideoInsert: Encodable {
            let creator_id: String
            let venue_id: String?
            let title: String
            let caption: String?
            let category: String?
            let playback_url: String
            let thumbnail_url: String?
            let storage_path: String
            let visibility: String
            let latitude: Double?
            let longitude: Double?
            let map_visibility: String
        }

        struct InsertedVideo: Decodable {
            let id: String
        }

        let insert = VideoInsert(
            creator_id: userId,
            venue_id: request.venueId,
            title: request.title,
            caption: request.caption?.isEmpty == true ? nil : request.caption,
            category: request.category?.isEmpty == true ? nil : request.category,
            playback_url: publicURL.absoluteString,
            thumbnail_url: thumbnailPublicURL?.absoluteString,
            storage_path: path,
            visibility: "public",
            latitude: request.latitude,
            longitude: request.longitude,
            map_visibility: request.mapVisibility.rawValue
        )

        let inserted: InsertedVideo
        do {
            inserted = try await client
                .from("videos")
                .insert(insert, returning: .representation)
                .select("id")
                .single()
                .execute()
                .value
        } catch {
            throw CreateServiceError.videoInsertFailed(error.localizedDescription)
        }

        // 5. Insert any tags.
        let tags = Self.parseTags(request.tagsInput)
        if !tags.isEmpty {
            struct TagInsert: Encodable {
                let video_id: String
                let tag: String
            }
            let tagRows = tags.map { TagInsert(video_id: inserted.id, tag: $0) }
            do {
                try await client
                    .from("video_tags")
                    .insert(tagRows, returning: .minimal)
                    .execute()
            } catch {
                throw CreateServiceError.tagInsertFailed(error.localizedDescription)
            }
        }

        await FeedService.shared.invalidatePostCaches(creatorId: userId)
    }

    // MARK: - Helpers

    private static func buildObjectBaseName() -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(timestamp)-post"
    }

    private static func buildObjectPath(userId: String, baseName: String, fileExtension: String) -> String {
        let ext = fileExtension.isEmpty ? "bin" : fileExtension
        return "\(userId)/\(baseName).\(ext)"
    }

    private static func buildThumbnailPath(userId: String, baseName: String) -> String {
        "\(userId)/\(baseName)-thumb.jpg"
    }

    private static func parseTags(_ input: String?) -> [String] {
        guard let input else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for raw in input.split(separator: ",") {
            let tag = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)
            if result.count >= 12 { break }
        }
        return result
    }

    private func assertCanCreateVenueMoment(
        userId: String,
        venueId: String?,
        category: String?
    ) async throws {
        guard let venueId, !venueId.isEmpty else { return }
        guard let category, !category.isEmpty else { return }

        struct RecentVenueMoment: Decodable {
            let id: String
            let created_at: String
        }

        let cooldownThreshold = Self.iso8601Timestamp(for: Date().addingTimeInterval(-60))
        let recentRows: [RecentVenueMoment] = try await client
            .from("videos")
            .select("id, created_at")
            .eq("creator_id", value: userId)
            .eq("venue_id", value: venueId)
            .eq("category", value: category)
            .gte("created_at", value: cooldownThreshold)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let recentMoment = recentRows.first else { return }
        throw CreateServiceError.cooldownActive(
            "Give it a minute before posting another moment here. Last post was \(PulseRelativeTimeFormatter.string(from: recentMoment.created_at))."
        )
    }

    private static func iso8601Timestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// Broadcast so the feed knows to refresh after a new post lands.
extension Notification.Name {
    static let pulseDidCreatePost = Notification.Name("spilltop.didCreatePost")
    static let pulseOpenCreate = Notification.Name("spilltop.openCreate")
    static let pulseExitCreate = Notification.Name("spilltop.exitCreate")
    static let pulseOpenInbox = Notification.Name("spilltop.openInbox")
    static let pulseInboxDidUpdate = Notification.Name("spilltop.inboxDidUpdate")
}

enum PulseRefreshSource {
    static let profileMutation = "profile-mutation"
}

struct PulseCreateRoute {
    let mode: String
    let venueId: String?

    var normalizedMode: PulseCreateRouteMode {
        switch mode.lowercased() {
        case "moment":
            return .moment
        case "live":
            return .live
        default:
            return .checkIn
        }
    }
}

enum PulseCreateRouteMode {
    case moment
    case checkIn
    case live
}

enum PulseDistanceFormatter {
    static func compactDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return "\(Int(meters.rounded()))m"
    }

    static func proximityLabel(for meters: CLLocationDistance) -> String {
        switch meters {
        case ..<250:
            return "\(Int(meters.rounded()))m away"
        case ..<2200:
            let walkingMinutes = max(1, Int((meters / 83.0).rounded()))
            return "\(walkingMinutes) min away"
        default:
            return "\(compactDistance(meters)) away"
        }
    }
}

actor PulseVenueLocationResolver {
    static let shared = PulseVenueLocationResolver()

    private var cachedLocations: [String: CLLocation] = [:]

    func location(for venue: Venue) async throws -> CLLocation {
        if let cachedLocation = cachedLocations[venue.id] {
            return cachedLocation
        }

        guard let address = venue.resolvedAddress else {
            throw CLError(.geocodeFoundNoResult)
        }

        let placemarks = try await geocodeAddress(address)
        guard let resolvedLocation = placemarks.first?.location else {
            throw CLError(.geocodeFoundNoResult)
        }

        cachedLocations[venue.id] = resolvedLocation
        return resolvedLocation
    }

    private func geocodeAddress(_ address: String) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { continuation in
            CLGeocoder().geocodeAddressString(address) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: placemarks ?? [])
            }
        }
    }
}

final class PulseLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?

    private let manager = CLLocationManager()
    private var isContinuousTrackingEnabled = false

    override init() {
        authorizationStatus = .notDetermined
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocationAccessIfNeeded() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func refreshLocation(forceRefresh: Bool = false) {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if isContinuousTrackingEnabled {
                manager.startUpdatingLocation()
            }
            if forceRefresh || currentLocation == nil {
                manager.requestLocation()
            }
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            manager.stopUpdatingLocation()
        @unknown default:
            manager.stopUpdatingLocation()
        }
    }

    func setContinuousTrackingEnabled(_ enabled: Bool) {
        isContinuousTrackingEnabled = enabled

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if enabled {
                manager.startUpdatingLocation()
                if currentLocation == nil {
                    manager.requestLocation()
                }
            } else {
                manager.stopUpdatingLocation()
            }
        case .notDetermined:
            if enabled {
                manager.requestWhenInUseAuthorization()
            }
        case .restricted, .denied:
            manager.stopUpdatingLocation()
        @unknown default:
            manager.stopUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            if isContinuousTrackingEnabled {
                manager.startUpdatingLocation()
            }
            manager.requestLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
