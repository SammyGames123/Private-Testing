import CoreLocation
import Foundation

struct ProfileStats: Hashable {
    let postsCount: Int
    let followersCount: Int
    let followingCount: Int
}

struct FeedComment: Identifiable, Decodable, Hashable {
    let id: String
    let userId: String
    let videoId: String
    let body: String
    let createdAt: String
    let author: UserProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case videoId = "video_id"
        case body
        case createdAt = "created_at"
        case profiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        videoId = try container.decode(String.self, forKey: .videoId)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(String.self, forKey: .createdAt)

        if let single = try? container.decodeIfPresent(UserProfile.self, forKey: .profiles) {
            author = single
        } else if let array = try? container.decodeIfPresent([UserProfile].self, forKey: .profiles) {
            author = array.first
        } else {
            author = nil
        }
    }

    var authorName: String {
        author?.name ?? "Creator"
    }

    var authorHandle: String {
        author?.handle ?? "@creator"
    }

    var authorInitial: String {
        author?.initial ?? "C"
    }
}

enum MessageThreadStatus: String, Hashable {
    case accepted
    case pending

    init(rawString: String?) {
        switch rawString?.lowercased() {
        case "pending":
            self = .pending
        default:
            self = .accepted
        }
    }
}

struct InboxThread: Identifiable, Hashable {
    let id: String
    let otherUserId: String
    let otherUserName: String
    let otherUserHandle: String
    let otherUserAvatarUrlString: String?
    let latestMessage: String
    let latestMessageAt: String
    let latestMessageSenderId: String?
    let status: MessageThreadStatus
    /// The user who originally opened the thread. Used to tell which side is
    /// the "requester" vs. the "recipient" for pending threads — only the
    /// recipient (i.e. not the creator) can accept or decline.
    let createdByUserId: String?

    var otherUserAvatarURL: URL? {
        StorageURLBuilder.transformedAvatarURL(
            userId: otherUserId,
            avatarUrlString: otherUserAvatarUrlString,
            size: 128
        )
    }

    var isPending: Bool { status == .pending }

    /// For a pending thread the viewer is a "recipient" if they didn't start
    /// the thread. Recipients see Accept/Decline; requesters see a read-only
    /// thread with no composer.
    func isPendingRecipient(viewerUserId: String) -> Bool {
        guard status == .pending, let createdByUserId else { return false }
        return createdByUserId.lowercased() != viewerUserId.lowercased()
    }

    func isPendingRequester(viewerUserId: String) -> Bool {
        guard status == .pending, let createdByUserId else { return false }
        return createdByUserId.lowercased() == viewerUserId.lowercased()
    }
}

struct ConversationMessage: Identifiable, Decodable, Hashable {
    let id: String
    let threadId: String
    let senderId: String
    let body: String
    let createdAt: String
    /// When set, this message is a share of the referenced post and the
    /// body is an optional note from the sender (may be empty). The
    /// client renders a post card instead of the plain text bubble.
    let sharedVideo: SharedVideoPreview?

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case senderId = "sender_id"
        case body
        case createdAt = "created_at"
        case sharedVideoId = "shared_video_id"
        case videos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        threadId = try container.decode(String.self, forKey: .threadId)
        senderId = try container.decode(String.self, forKey: .senderId)
        body = (try container.decodeIfPresent(String.self, forKey: .body)) ?? ""
        createdAt = try container.decode(String.self, forKey: .createdAt)

        // The server returns the joined video either as a single object or
        // a 1-element array depending on the select shape. Tolerate both.
        let sharedVideoId = try container.decodeIfPresent(String.self, forKey: .sharedVideoId)
        if sharedVideoId != nil {
            if let single = try? container.decodeIfPresent(SharedVideoPreview.self, forKey: .videos) {
                sharedVideo = single
            } else if let array = try? container.decodeIfPresent([SharedVideoPreview].self, forKey: .videos) {
                sharedVideo = array.first
            } else {
                // FK is set but the join didn't come back (e.g. video was
                // deleted). Surface the deletion as "Post unavailable".
                sharedVideo = SharedVideoPreview.deleted(id: sharedVideoId ?? "")
            }
        } else {
            sharedVideo = nil
        }
    }

    init(
        id: String,
        threadId: String,
        senderId: String,
        body: String,
        createdAt: String,
        sharedVideo: SharedVideoPreview? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.senderId = senderId
        self.body = body
        self.createdAt = createdAt
        self.sharedVideo = sharedVideo
    }
}

/// Lightweight snapshot of a shared post, embedded on a DM. Just enough
/// to render a tappable card; opening the card fetches the full post.
struct SharedVideoPreview: Decodable, Hashable {
    let id: String
    let title: String?
    let caption: String?
    let playbackUrlString: String?
    let thumbnailUrlString: String?
    let creator: ThreadVideoCreator?
    /// True when the server returned the FK but not the row (post was
    /// deleted, or the viewer can't read it via RLS).
    let isUnavailable: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case caption
        case playbackUrlString = "playback_url"
        case thumbnailUrlString = "thumbnail_url"
        case profiles
    }

    struct ThreadVideoCreator: Decodable, Hashable {
        let username: String?
        let displayName: String?
        let avatarUrlString: String?

        enum CodingKeys: String, CodingKey {
            case username
            case displayName = "display_name"
            case avatarUrlString = "avatar_url"
        }

        var handle: String {
            if let username, !username.isEmpty { return "@\(username)" }
            return "@creator"
        }

        var name: String {
            if let displayName, !displayName.isEmpty { return displayName }
            if let username, !username.isEmpty { return username }
            return "Creator"
        }

        var avatarURL: URL? {
            guard let avatarUrlString, !avatarUrlString.isEmpty else { return nil }
            return URL(string: avatarUrlString)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        playbackUrlString = try container.decodeIfPresent(String.self, forKey: .playbackUrlString)
        thumbnailUrlString = try container.decodeIfPresent(String.self, forKey: .thumbnailUrlString)

        if let single = try? container.decodeIfPresent(ThreadVideoCreator.self, forKey: .profiles) {
            creator = single
        } else if let array = try? container.decodeIfPresent([ThreadVideoCreator].self, forKey: .profiles) {
            creator = array.first
        } else {
            creator = nil
        }
        isUnavailable = false
    }

    private init(
        id: String,
        title: String?,
        caption: String?,
        playbackUrlString: String?,
        thumbnailUrlString: String?,
        creator: ThreadVideoCreator?,
        isUnavailable: Bool
    ) {
        self.id = id
        self.title = title
        self.caption = caption
        self.playbackUrlString = playbackUrlString
        self.thumbnailUrlString = thumbnailUrlString
        self.creator = creator
        self.isUnavailable = isUnavailable
    }

    static func deleted(id: String) -> SharedVideoPreview {
        SharedVideoPreview(
            id: id,
            title: nil,
            caption: nil,
            playbackUrlString: nil,
            thumbnailUrlString: nil,
            creator: nil,
            isUnavailable: true
        )
    }

    var playbackURL: URL? {
        guard let playbackUrlString, !playbackUrlString.isEmpty else { return nil }
        return URL(string: playbackUrlString)
    }

    var thumbnailURL: URL? {
        guard let thumbnailUrlString, !thumbnailUrlString.isEmpty else { return nil }
        return URL(string: thumbnailUrlString)
    }

    var mediaKind: MediaKind {
        guard let urlString = playbackUrlString else { return .video }
        let path = URL(string: urlString)?.path ?? urlString
        let cleaned = path.lowercased().split(whereSeparator: { "?#".contains($0) }).first.map(String.init) ?? path.lowercased()
        let ext = (cleaned as NSString).pathExtension
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "svg", "heic", "heif"]
        return imageExts.contains(ext) ? .image : .video
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "Shared post"
    }
}

struct ConversationRoute: Identifiable, Hashable {
    let id: String
    let viewerUserId: String
    let otherUserId: String
    let otherUserName: String
    let otherUserHandle: String
    let otherUserAvatarUrlString: String?
    /// Pending / accepted at open time. May be mutated by the conversation
    /// view once the viewer accepts the request.
    var status: MessageThreadStatus
    /// Whether the viewer opened this thread (i.e. is the requester on a
    /// pending thread). Used to hide the composer for recipients and gate
    /// the accept button.
    let viewerIsCreator: Bool

    init(thread: InboxThread, viewerUserId: String) {
        id = thread.id
        self.viewerUserId = viewerUserId
        otherUserId = thread.otherUserId
        otherUserName = thread.otherUserName
        otherUserHandle = thread.otherUserHandle
        otherUserAvatarUrlString = thread.otherUserAvatarUrlString
        status = thread.status
        viewerIsCreator = thread.isPendingRequester(viewerUserId: viewerUserId)
            || (thread.status == .accepted
                && (thread.createdByUserId?.lowercased() == viewerUserId.lowercased()))
    }

    init(
        threadId: String,
        viewerUserId: String,
        profile: UserProfile,
        status: MessageThreadStatus = .accepted,
        viewerIsCreator: Bool = true
    ) {
        id = threadId
        self.viewerUserId = viewerUserId
        otherUserId = profile.id
        otherUserName = profile.name
        otherUserHandle = profile.handle
        otherUserAvatarUrlString = profile.avatarUrlString
        self.status = status
        self.viewerIsCreator = viewerIsCreator
    }

    var otherUserAvatarURL: URL? {
        StorageURLBuilder.transformedAvatarURL(
            userId: otherUserId,
            avatarUrlString: otherUserAvatarUrlString,
            size: 128
        )
    }

    var isPending: Bool { status == .pending }
    var viewerIsPendingRecipient: Bool { status == .pending && !viewerIsCreator }
    var viewerIsPendingRequester: Bool { status == .pending && viewerIsCreator }
}

struct Venue: Identifiable, Decodable, Hashable {
    let id: String
    let slug: String
    let name: String
    let area: String
    let city: String
    let category: String?
    let vibeBlurb: String?
    let launchPriority: Int?
    let isActive: Bool?
    let precinctId: String?
    let address: String?
    let googlePlaceId: String?
    let googlePlaceName: String?
    let googleLastSyncedAt: String?
    let priceLevel: Int?
    let nightlifeScore: Int?
    let featured: Bool?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case area
        case city
        case category
        case vibeBlurb = "vibe_blurb"
        case launchPriority = "launch_priority"
        case isActive = "is_active"
        case precinctId = "precinct_id"
        case address
        case googlePlaceId = "google_place_id"
        case googlePlaceName = "google_place_name"
        case googleLastSyncedAt = "google_last_synced_at"
        case priceLevel = "price_level"
        case nightlifeScore = "nightlife_score"
        case featured
        case latitude
        case longitude
    }

    var shortLocation: String {
        area == city ? area : "\(area), \(city)"
    }

    var resolvedAddress: String? {
        address ?? verificationAddress
    }

    var priceLevelLabel: String? {
        guard let priceLevel, priceLevel > 0 else { return nil }
        return String(repeating: "$", count: min(priceLevel, 4))
    }

    var verificationAddress: String? {
        switch slug {
        case "sincity-nightclub":
            return "22 Orchid Ave, Surfers Paradise QLD 4217, Australia"
        case "cocktails-nightclub":
            return "3-15 Orchid Ave, Surfers Paradise QLD 4217, Australia"
        case "the-avenue":
            return "3-15 Orchid Ave, Surfers Paradise QLD 4217, Australia"
        case "the-avenue-surfers":
            return "3-15 Orchid Ave, Surfers Paradise QLD 4217, Australia"
        case "bedroom-lounge-bar":
            return "26 Orchid Ave, Surfers Paradise QLD 4217, Australia"
        case "havana-rnb":
            return "26 Orchid Ave, Surfers Paradise QLD 4217, Australia"
        case "elsewhere":
            return "1/23 Cavill Ave, Surfers Paradise QLD 4217, Australia"
        case "cali-beach-club":
            return "21a Elkhorn Ave, Surfers Paradise QLD 4217, Australia"
        case "the-island-rooftop":
            return "3128 Surfers Paradise Blvd, Surfers Paradise QLD 4217, Australia"
        case "skypoint-bistro-bar":
            return "Level 77, Q1 Building, Corner of Clifford St & Surfers Paradise Blvd, Surfers Paradise QLD 4217, Australia"
        case "nineteen-at-the-star":
            return "Level 19, The Darling, 1 Casino Drive, Broadbeach QLD 4218, Australia"
        case "atrium-bar":
            return "Casino Level, The Star Gold Coast, Broadbeach Island, Broadbeach QLD 4218, Australia"
        case "retros":
            return "3/15 Orchid Ave, Surfers Paradise QLD 4217, Australia"
        case "house-of-brews":
            return "17 Orchid Ave, Surfers Paradise QLD 4217, Australia"
        case "burleigh-pavilion":
            return "3a/43 Goodwin Terrace, Burleigh Heads QLD 4220, Australia"
        case "justin-lane":
            return "1708-1710 Gold Coast Highway, Burleigh Heads QLD 4220, Australia"
        case "miami-marketta":
            return "23 Hillcrest Parade, Miami QLD 4220, Australia"
        default:
            return nil
        }
    }

    var verificationRadiusMeters: Double {
        switch slug {
        case "house-of-brews":
            return 120
        default:
            return 150
        }
    }

    var mapCoordinate: CLLocationCoordinate2D? {
        if let latitude, let longitude {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        switch slug {
        case "sincity-nightclub":
            return CLLocationCoordinate2D(latitude: -28.0007, longitude: 153.4285)
        case "cocktails-nightclub":
            return CLLocationCoordinate2D(latitude: -28.0006, longitude: 153.4282)
        case "the-avenue":
            return CLLocationCoordinate2D(latitude: -28.0006, longitude: 153.4282)
        case "the-avenue-surfers":
            return CLLocationCoordinate2D(latitude: -28.0006, longitude: 153.4282)
        case "bedroom-lounge-bar":
            return CLLocationCoordinate2D(latitude: -28.0004, longitude: 153.4285)
        case "havana-rnb":
            return CLLocationCoordinate2D(latitude: -28.0004, longitude: 153.4285)
        case "elsewhere":
            return CLLocationCoordinate2D(latitude: -28.0014, longitude: 153.4290)
        case "cali-beach-club":
            return CLLocationCoordinate2D(latitude: -28.0003, longitude: 153.4300)
        case "the-island-rooftop":
            return CLLocationCoordinate2D(latitude: -28.0020, longitude: 153.4303)
        case "skypoint-bistro-bar":
            return CLLocationCoordinate2D(latitude: -28.0061, longitude: 153.4311)
        case "nineteen-at-the-star":
            return CLLocationCoordinate2D(latitude: -28.0348, longitude: 153.4308)
        case "atrium-bar":
            return CLLocationCoordinate2D(latitude: -28.0347, longitude: 153.4307)
        case "retros":
            return CLLocationCoordinate2D(latitude: -28.0008, longitude: 153.4283)
        case "house-of-brews":
            return CLLocationCoordinate2D(latitude: -28.0009, longitude: 153.4288)
        case "burleigh-pavilion":
            return CLLocationCoordinate2D(latitude: -28.0917, longitude: 153.4541)
        case "justin-lane":
            return CLLocationCoordinate2D(latitude: -28.0910, longitude: 153.4528)
        case "miami-marketta":
            return CLLocationCoordinate2D(latitude: -28.0727, longitude: 153.4357)
        default:
            return nil
        }
    }
}

struct NightlifeCheckIn: Identifiable, Decodable, Hashable {
    let id: String
    let userId: String
    let venueId: String
    let vibeEmoji: String?
    let note: String?
    let latitude: Double?
    let longitude: Double?
    let checkedOutAt: String?
    let createdAt: String
    let user: UserProfile?
    let venue: Venue?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case venueId = "venue_id"
        case vibeEmoji = "vibe_emoji"
        case note
        case latitude
        case longitude
        case checkedOutAt = "checked_out_at"
        case createdAt = "created_at"
        case profiles
        case venues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        venueId = try container.decode(String.self, forKey: .venueId)
        vibeEmoji = try container.decodeIfPresent(String.self, forKey: .vibeEmoji)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        checkedOutAt = try container.decodeIfPresent(String.self, forKey: .checkedOutAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)

        if let singleUser = try? container.decodeIfPresent(UserProfile.self, forKey: .profiles) {
            user = singleUser
        } else if let userArray = try? container.decodeIfPresent([UserProfile].self, forKey: .profiles) {
            user = userArray.first
        } else {
            user = nil
        }

        if let singleVenue = try? container.decodeIfPresent(Venue.self, forKey: .venues) {
            venue = singleVenue
        } else if let venueArray = try? container.decodeIfPresent([Venue].self, forKey: .venues) {
            venue = venueArray.first
        } else {
            venue = nil
        }
    }

    var userName: String {
        user?.name ?? "Someone"
    }

    var userInitial: String {
        user?.initial ?? "S"
    }

    var isActive: Bool {
        checkedOutAt == nil
    }

    var relativeTimestamp: String {
        PulseRelativeTimeFormatter.string(from: createdAt)
    }
}

extension NightlifeCheckIn {
    init(
        id: String,
        userId: String,
        venueId: String,
        vibeEmoji: String?,
        note: String?,
        latitude: Double?,
        longitude: Double?,
        checkedOutAt: String?,
        createdAt: String,
        user: UserProfile?,
        venue: Venue?
    ) {
        self.id = id
        self.userId = userId
        self.venueId = venueId
        self.vibeEmoji = vibeEmoji
        self.note = note
        self.latitude = latitude
        self.longitude = longitude
        self.checkedOutAt = checkedOutAt
        self.createdAt = createdAt
        self.user = user
        self.venue = venue
    }

    func canonicalized(venueId: String, venue: Venue?) -> NightlifeCheckIn {
        NightlifeCheckIn(
            id: id,
            userId: userId,
            venueId: venueId,
            vibeEmoji: vibeEmoji,
            note: note,
            latitude: latitude,
            longitude: longitude,
            checkedOutAt: checkedOutAt,
            createdAt: createdAt,
            user: user,
            venue: venue
        )
    }
}

enum PulseVenueStatus: String, Hashable {
    case hot = "Hot"
    case building = "Building"
    case slowingDown = "Slowing Down"
    case quiet = "Quiet"

    var description: String {
        rawValue
    }

    var nightlifeBadgeTitle: String {
        switch self {
        case .hot:
            return "Hot"
        case .building:
            return "Building"
        case .slowingDown:
            return "Slowing Down"
        case .quiet:
            return "Low-Key"
        }
    }

    var recommendationPhrase: String {
        switch self {
        case .hot:
            return "busy right now"
        case .building:
            return "building right now"
        case .slowingDown:
            return "slowing down right now"
        case .quiet:
            return "low-key right now"
        }
    }

    var expectedPhrase: String {
        switch self {
        case .hot:
            return "busy around now"
        case .building:
            return "building around now"
        case .slowingDown:
            return "slowing down around now"
        case .quiet:
            return "low-key around now"
        }
    }

    var expectedHeadline: String {
        switch self {
        case .hot:
            return "Expected busy around now"
        case .building:
            return "Expected building around now"
        case .slowingDown:
            return "Expected slowing down around now"
        case .quiet:
            return "Expected low-key around now"
        }
    }

    var recommendationWord: String {
        switch self {
        case .hot:
            return "busy"
        case .building:
            return "building"
        case .slowingDown:
            return "slowing down"
        case .quiet:
            return "low-key"
        }
    }

    var intensityRank: Int {
        switch self {
        case .quiet:
            return 0
        case .slowingDown:
            return 1
        case .building:
            return 2
        case .hot:
            return 3
        }
    }
}

enum PulseVenueSignalConfidence: String, Hashable {
    case live
    case blended
    case expected

    var title: String {
        switch self {
        case .live:
            return "Live now"
        case .blended:
            return "Early signal"
        case .expected:
            return "Expected now"
        }
    }

    var explanation: String {
        switch self {
        case .live:
            return "Based on recent Spilltop activity nearby."
        case .blended:
            return "Mix of recent Spilltop activity and venue rhythm."
        case .expected:
            return "Based on venue type and time of night."
        }
    }
}

struct HotVenueSummary: Identifiable, Hashable {
    let venue: Venue
    let score: Double
    let status: PulseVenueStatus
    let liveStatus: PulseVenueStatus
    let expectedStatus: PulseVenueStatus
    let confidence: PulseVenueSignalConfidence
    let activityCount: Int
    let uniquePeopleCount: Int
    let friendCount: Int
    let momentumCount: Int
    let recentVibes: [String]
    let latestCheckInAt: String?

    var id: String { venue.id }

    var currentCrowdLine: String {
        switch confidence {
        case .live:
            if friendCount > 0 {
                return "\(friendCount) friend\(friendCount == 1 ? "" : "s") here now"
            }
            return "\(uniquePeopleCount) here now"
        case .blended:
            if uniquePeopleCount > 0 {
                return "\(uniquePeopleCount) spotted recently"
            }
            return expectedStatus.expectedHeadline
        case .expected:
            return expectedStatus.expectedHeadline
        }
    }

    var crowdMetaLine: String {
        switch confidence {
        case .live:
            var parts: [String] = [confidence.title]

            if activityCount > 0 {
                parts.append("\(activityCount) check-in\(activityCount == 1 ? "" : "s")")
            }

            if momentumCount >= 2 {
                parts.append("building fast")
            }

            return parts.joined(separator: " • ")
        case .blended:
            var parts: [String] = [confidence.title, expectedStatus.expectedPhrase]
            if activityCount > 0 {
                parts.append("\(activityCount) recent")
            }
            return parts.joined(separator: " • ")
        case .expected:
            return "\(confidence.title) • \(expectedStatus.expectedPhrase)"
        }
    }
}

enum PulseFeedItemStyle: Hashable {
    case venuePulse
    case friendMove
}

struct PulseFeedItem: Identifiable, Hashable {
    let id: String
    let style: PulseFeedItemStyle
    let title: String
    let subtitle: String
    let badge: String
    let venue: Venue?
    let status: PulseVenueStatus?
    let createdAt: String
    let friendNames: [String]
    let vibeEmojis: [String]
    let activityCount: Int
}

struct PulseRecommendation: Hashable {
    let venue: Venue
    let title: String
    let subtitle: String
    let status: PulseVenueStatus
}

struct PulseSnapshot: Hashable {
    let venues: [Venue]
    let recentCheckIns: [NightlifeCheckIn]
    let hotVenues: [HotVenueSummary]
    let feedItems: [PulseFeedItem]
    let goingOutMoments: [FeedVideo]
    let outNowMoments: [FeedVideo]
    let recommendation: PulseRecommendation?
}

enum PulseRelativeTimeFormatter {
    static func string(from isoValue: String) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = date(from: isoValue)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func date(from isoValue: String) -> Date {
        ProfileDateFormatter.isoWithFractional.date(from: isoValue)
            ?? ProfileDateFormatter.iso.date(from: isoValue)
            ?? .distantPast
    }
}

enum LiveStreamStatus: String, Decodable, Hashable {
    case setup
    case live
    case ended

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self).lowercased()) ?? ""
        self = LiveStreamStatus(rawValue: rawValue) ?? .setup
    }
}

struct LiveStream: Identifiable, Decodable, Hashable {
    let id: String
    let creatorId: String
    let venueId: String?
    let title: String
    let status: LiveStreamStatus
    let provider: String?
    let providerStreamId: String?
    let ingestUrlString: String?
    let streamKey: String?
    let playbackUrlString: String?
    let thumbnailUrlString: String?
    let viewerCount: Int
    let requiresGeoVerification: Bool
    let startedAt: String
    let endedAt: String?
    let lastHeartbeatAt: String?
    let creator: UserProfile?
    let venue: Venue?

    enum CodingKeys: String, CodingKey {
        case id
        case creatorId = "creator_id"
        case venueId = "venue_id"
        case title
        case status
        case provider
        case providerStreamId = "provider_stream_id"
        case ingestUrlString = "ingest_url"
        case streamKey = "stream_key"
        case playbackUrlString = "playback_url"
        case thumbnailUrlString = "thumbnail_url"
        case viewerCount = "viewer_count"
        case requiresGeoVerification = "requires_geo_verification"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case lastHeartbeatAt = "last_heartbeat_at"
        case profiles
        case venues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        creatorId = try container.decode(String.self, forKey: .creatorId)
        venueId = try container.decodeIfPresent(String.self, forKey: .venueId)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(LiveStreamStatus.self, forKey: .status)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerStreamId = try container.decodeIfPresent(String.self, forKey: .providerStreamId)
        ingestUrlString = try container.decodeIfPresent(String.self, forKey: .ingestUrlString)
        streamKey = try container.decodeIfPresent(String.self, forKey: .streamKey)
        playbackUrlString = try container.decodeIfPresent(String.self, forKey: .playbackUrlString)
        thumbnailUrlString = try container.decodeIfPresent(String.self, forKey: .thumbnailUrlString)
        viewerCount = try container.decodeIfPresent(Int.self, forKey: .viewerCount) ?? 0
        requiresGeoVerification = try container.decodeIfPresent(Bool.self, forKey: .requiresGeoVerification) ?? true
        startedAt = try container.decode(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
        lastHeartbeatAt = try container.decodeIfPresent(String.self, forKey: .lastHeartbeatAt)

        if let single = try? container.decodeIfPresent(UserProfile.self, forKey: .profiles) {
            creator = single
        } else if let array = try? container.decodeIfPresent([UserProfile].self, forKey: .profiles) {
            creator = array.first
        } else {
            creator = nil
        }

        if let singleVenue = try? container.decodeIfPresent(Venue.self, forKey: .venues) {
            venue = singleVenue
        } else if let venueArray = try? container.decodeIfPresent([Venue].self, forKey: .venues) {
            venue = venueArray.first
        } else {
            venue = nil
        }
    }

    var playbackURL: URL? {
        guard let playbackUrlString, !playbackUrlString.isEmpty else { return nil }
        return URL(string: playbackUrlString)
    }

    var thumbnailURL: URL? {
        guard let thumbnailUrlString, !thumbnailUrlString.isEmpty else { return nil }
        return URL(string: thumbnailUrlString)
    }

    var creatorName: String {
        creator?.name ?? "Creator"
    }

    var creatorHandle: String {
        creator?.handle ?? "@creator"
    }

    var creatorInitial: String {
        creator?.initial ?? "C"
    }

    var creatorAvatarURL: URL? {
        StorageURLBuilder.transformedAvatarURL(
            userId: creatorId,
            avatarUrlString: creator?.avatarUrlString,
            size: 128
        )
    }

    var venueName: String? {
        venue?.name
    }

    var venueShortLocation: String? {
        venue?.shortLocation
    }

    var isLiveKitStream: Bool {
        provider?.lowercased() == "livekit"
    }

    var liveKitRoomName: String {
        if let providerStreamId, !providerStreamId.isEmpty {
            return providerStreamId
        }
        return "spilltop-live-\(id.lowercased())"
    }

    var isGettingReadyStream: Bool {
        !requiresGeoVerification && venueId == nil
    }

    var contextTitle: String {
        if isGettingReadyStream {
            return "Getting Ready"
        }
        return "At Venue"
    }

    var contextSystemImage: String {
        if isGettingReadyStream {
            return "house.fill"
        }
        return "location.fill"
    }

    var contextSubtitle: String {
        if isGettingReadyStream {
            return "Streaming from home while getting ready."
        }
        if let venueName {
            return venueName
        }
        return "Verified venue stream"
    }

    var isLive: Bool {
        status == .live && endedAt == nil
    }

    var liveBadgeTitle: String {
        switch status {
        case .live:
            return "LIVE"
        case .setup:
            return "STARTING"
        case .ended:
            return "ENDED"
        }
    }

    var playbackStateTitle: String {
        if playbackURL != nil {
            return "Live now"
        }
        if isLiveKitStream && isLive {
            return "Join live room"
        }
        switch status {
        case .live:
            return "Broadcast setup pending"
        case .setup:
            return "Preparing stream"
        case .ended:
            return "Stream ended"
        }
    }

    var relativeStartedAt: String {
        PulseRelativeTimeFormatter.string(from: startedAt)
    }
}

enum LiveStreamServiceError: LocalizedError {
    case backendNotReady
    case couldNotStart(String)
    case couldNotEnd(String)

    var errorDescription: String? {
        switch self {
        case .backendNotReady:
            return "Live streaming backend isn't ready yet. Run the live_streams SQL migration first."
        case .couldNotStart(let message):
            return "Couldn't start the live session: \(message)"
        case .couldNotEnd(let message):
            return "Couldn't end the live session: \(message)"
        }
    }
}
