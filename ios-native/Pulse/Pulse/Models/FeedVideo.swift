import CoreLocation
import Foundation
import Supabase

enum MediaKind {
    case video
    case image
}

enum MapMomentVisibility: String, CaseIterable, Codable, Hashable {
    case publicMap = "public"
    case mutuals = "mutuals"
    case hidden = "hidden"

    var title: String {
        switch self {
        case .publicMap:
            return "Public map"
        case .mutuals:
            return "Mutual map"
        case .hidden:
            return "Profile only"
        }
    }

    var subtitle: String {
        switch self {
        case .publicMap:
            return "Anyone on Spilltop can see it here"
        case .mutuals:
            return "Only people you both follow"
        case .hidden:
            return "Not on the map"
        }
    }
}

/// One post in the feed. Decoded directly from the `videos` table plus
/// an embedded join on `profiles` for the creator's handle/name, and
/// PostgREST count aggregates for likes and comments.
struct FeedVideo: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let caption: String?
    let category: String?
    let venueId: String?
    let playbackUrlString: String?
    let thumbnailUrlString: String?
    let createdAt: String
    let creatorId: String
    let creator: Creator?
    let venue: Venue?
    let latitude: Double?
    let longitude: Double?
    let mapVisibility: String?
    let isPinned: Bool
    let isArchived: Bool
    let likesCount: Int
    let commentsCount: Int

    struct Creator: Decodable, Hashable {
        let username: String?
        let displayName: String?
        let avatarUrlString: String?

        enum CodingKeys: String, CodingKey {
            case username
            case displayName = "display_name"
            case avatarUrlString = "avatar_url"
        }

        var avatarURL: URL? {
            guard let avatarUrlString, !avatarUrlString.isEmpty else { return nil }
            return URL(string: avatarUrlString)
        }
    }

    struct CountRow: Decodable, Hashable {
        let count: Int
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case caption
        case category
        case venueId = "venue_id"
        case playbackUrlString = "playback_url"
        case thumbnailUrlString = "thumbnail_url"
        case createdAt = "created_at"
        case creatorId = "creator_id"
        case profiles
        case venues
        case latitude
        case longitude
        case mapVisibility = "map_visibility"
        case isPinned = "is_pinned"
        case isArchived = "is_archived"
        case likes
        case comments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        venueId = try c.decodeIfPresent(String.self, forKey: .venueId)
        playbackUrlString = try c.decodeIfPresent(String.self, forKey: .playbackUrlString)
        thumbnailUrlString = try c.decodeIfPresent(String.self, forKey: .thumbnailUrlString)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        creatorId = try c.decode(String.self, forKey: .creatorId)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        mapVisibility = try c.decodeIfPresent(String.self, forKey: .mapVisibility)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false

        // PostgREST returns an embedded many-to-one join as a single
        // object, but some response shapes serialize it as a
        // one-element array. Tolerate both.
        if let single = try? c.decodeIfPresent(Creator.self, forKey: .profiles) {
            creator = single
        } else if let array = try? c.decodeIfPresent([Creator].self, forKey: .profiles) {
            creator = array.first
        } else {
            creator = nil
        }

        if let singleVenue = try? c.decodeIfPresent(Venue.self, forKey: .venues) {
            venue = singleVenue
        } else if let venueArray = try? c.decodeIfPresent([Venue].self, forKey: .venues) {
            venue = venueArray.first
        } else {
            venue = nil
        }

        // `likes(count)` / `comments(count)` comes back as
        // `[{"count": N}]`. Take the first row.
        likesCount = (try? c.decodeIfPresent([CountRow].self, forKey: .likes))?.first?.count ?? 0
        commentsCount = (try? c.decodeIfPresent([CountRow].self, forKey: .comments))?.first?.count ?? 0
    }

    var playbackURL: URL? {
        guard let playbackUrlString, !playbackUrlString.isEmpty else { return nil }
        return URL(string: playbackUrlString)
    }

    var thumbnailURL: URL? {
        guard let thumbnailUrlString, !thumbnailUrlString.isEmpty else { return nil }
        return URL(string: thumbnailUrlString)
    }

    var mapCoordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func optimizedThumbnailURL(width: Int, height: Int? = nil, quality: Int = 72) -> URL? {
        guard let storagePath = Self.storagePath(fromPublicURLString: thumbnailUrlString, bucketId: "videos") else {
            return thumbnailURL
        }

        return try? SupabaseManager.shared.client.storage
            .from("videos")
            .getPublicURL(
                path: storagePath,
                options: TransformOptions(
                    width: width,
                    height: height,
                    resize: "cover",
                    quality: quality,
                    format: "webp"
                )
            )
    }

    func optimizedPlaybackImageURL(
        width: Int,
        height: Int? = nil,
        quality: Int = 82,
        resizeMode: String = "cover"
    ) -> URL? {
        guard mediaKind == .image else { return playbackURL }
        guard let storagePath = Self.storagePath(fromPublicURLString: playbackUrlString, bucketId: "videos") else {
            return playbackURL
        }

        return try? SupabaseManager.shared.client.storage
            .from("videos")
            .getPublicURL(
                path: storagePath,
                options: TransformOptions(
                    width: width,
                    height: height,
                    resize: resizeMode,
                    quality: quality,
                    format: "webp"
                )
            )
    }

    /// Some posts in the `videos` table are actually images. We infer
    /// the kind from the playback URL's file extension — same rule
    /// the web app uses in `src/lib/media.ts`.
    var mediaKind: MediaKind {
        guard let urlString = playbackUrlString else { return .video }
        let path = URL(string: urlString)?.path ?? urlString
        let cleaned = path.lowercased().split(whereSeparator: { "?#".contains($0) }).first.map(String.init) ?? path.lowercased()
        let ext = (cleaned as NSString).pathExtension
        return FeedVideo.imageExtensions.contains(ext) ? .image : .video
    }

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "svg", "heic", "heif"
    ]

    var creatorHandle: String {
        if let username = creator?.username, !username.isEmpty {
            return "@\(username)"
        }
        return "@creator"
    }

    var creatorName: String {
        if let display = creator?.displayName, !display.isEmpty { return display }
        if let username = creator?.username, !username.isEmpty { return username }
        return "Creator"
    }

    var creatorAvatarURL: URL? {
        StorageURLBuilder.transformedAvatarURL(
            userId: creatorId,
            avatarUrlString: creator?.avatarUrlString,
            size: 128
        )
    }

    var creatorInitial: String {
        String(creatorName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    var venueName: String? {
        venue?.name
    }

    var venueShortLocation: String? {
        venue?.shortLocation
    }

    var momentLabel: String? {
        switch category {
        case "going-out":
            return "Pre's"
        case "out-now":
            return "Out Now"
        default:
            return nil
        }
    }

    var isOutNowMoment: Bool {
        category == "out-now"
    }

    var isGoingOutMoment: Bool {
        category == "going-out"
    }

    private static func storagePath(fromPublicURLString urlString: String?, bucketId: String) -> String? {
        guard
            let urlString,
            let url = URL(string: urlString),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let marker = "/storage/v1/object/public/\(bucketId)/"
        guard let range = components.path.range(of: marker) else { return nil }
        let path = String(components.path[range.upperBound...])
        return path.removingPercentEncoding ?? path
    }
}

struct MapMoment: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let caption: String?
    let category: String?
    let playbackUrlString: String?
    let thumbnailUrlString: String?
    let createdAt: String
    let creatorId: String
    let creatorUsername: String?
    let creatorDisplayName: String?
    let creatorAvatarUrlString: String?
    let latitude: Double
    let longitude: Double
    let mapVisibility: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case caption
        case category
        case playbackUrlString = "playback_url"
        case thumbnailUrlString = "thumbnail_url"
        case createdAt = "created_at"
        case creatorId = "creator_id"
        case creatorUsername = "creator_username"
        case creatorDisplayName = "creator_display_name"
        case creatorAvatarUrlString = "creator_avatar_url"
        case latitude
        case longitude
        case mapVisibility = "map_visibility"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var playbackURL: URL? {
        guard let playbackUrlString, !playbackUrlString.isEmpty else { return nil }
        return URL(string: playbackUrlString)
    }

    var thumbnailURL: URL? {
        guard let thumbnailUrlString, !thumbnailUrlString.isEmpty else { return nil }
        return URL(string: thumbnailUrlString)
    }

    var creatorAvatarURL: URL? {
        guard let creatorAvatarUrlString, !creatorAvatarUrlString.isEmpty else { return nil }
        return URL(string: creatorAvatarUrlString)
    }

    var creatorName: String {
        if let creatorDisplayName, !creatorDisplayName.isEmpty { return creatorDisplayName }
        if let creatorUsername, !creatorUsername.isEmpty { return creatorUsername }
        return "Someone"
    }

    var creatorHandle: String {
        if let creatorUsername, !creatorUsername.isEmpty {
            return "@\(creatorUsername)"
        }
        return "@creator"
    }

    var creatorInitial: String {
        String(creatorName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    var relativeTimestamp: String {
        PulseRelativeTimeFormatter.string(from: createdAt)
    }

    var visibility: MapMomentVisibility {
        MapMomentVisibility(rawValue: mapVisibility) ?? .publicMap
    }

    var mediaKind: MediaKind {
        guard let urlString = playbackUrlString else { return .video }
        let path = URL(string: urlString)?.path ?? urlString
        let cleaned = path.lowercased().split(whereSeparator: { "?#".contains($0) }).first.map(String.init) ?? path.lowercased()
        let ext = (cleaned as NSString).pathExtension
        return Self.imageExtensions.contains(ext) ? .image : .video
    }

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "svg", "heic", "heif"
    ]
}
