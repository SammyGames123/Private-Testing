import Foundation

enum MediaKind {
    case video
    case image
}

/// One post in the feed. Decoded directly from the `videos` table plus
/// an embedded join on `profiles` for the creator's handle/name, and
/// PostgREST count aggregates for likes and comments.
struct FeedVideo: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let caption: String?
    let category: String?
    let playbackUrlString: String?
    let thumbnailUrlString: String?
    let createdAt: String
    let creatorId: String
    let creator: Creator?
    let likesCount: Int
    let commentsCount: Int

    struct Creator: Decodable, Hashable {
        let username: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case username
            case displayName = "display_name"
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
        case playbackUrlString = "playback_url"
        case thumbnailUrlString = "thumbnail_url"
        case createdAt = "created_at"
        case creatorId = "creator_id"
        case profiles
        case likes
        case comments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        playbackUrlString = try c.decodeIfPresent(String.self, forKey: .playbackUrlString)
        thumbnailUrlString = try c.decodeIfPresent(String.self, forKey: .thumbnailUrlString)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        creatorId = try c.decode(String.self, forKey: .creatorId)

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
}
