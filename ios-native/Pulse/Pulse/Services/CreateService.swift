import Foundation
import Supabase

/// Inputs for building a new post.
struct CreatePostRequest {
    let title: String
    let caption: String?
    let tagsInput: String?
    let mediaData: Data
    /// e.g. "video/mp4", "image/jpeg"
    let contentType: String
    /// e.g. "mp4", "jpg"
    let fileExtension: String
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
        // 1. Who am I?
        let session = try await client.auth.session
        let userId = session.user.id.uuidString

        // 2. Upload the media to the videos bucket.
        let path = Self.buildObjectPath(userId: userId, fileExtension: request.fileExtension)
        _ = try await client.storage
            .from("videos")
            .upload(
                path,
                data: request.mediaData,
                options: FileOptions(contentType: request.contentType, upsert: false)
            )

        // 3. Get the public URL for playback.
        let publicURL = try client.storage
            .from("videos")
            .getPublicURL(path: path)

        // 4. Insert the videos row.
        struct VideoInsert: Encodable {
            let creator_id: String
            let title: String
            let caption: String?
            let playback_url: String
            let storage_path: String
            let visibility: String
        }

        struct InsertedVideo: Decodable {
            let id: String
        }

        let insert = VideoInsert(
            creator_id: userId,
            title: request.title,
            caption: request.caption?.isEmpty == true ? nil : request.caption,
            playback_url: publicURL.absoluteString,
            storage_path: path,
            visibility: "public"
        )

        let inserted: InsertedVideo = try await client
            .from("videos")
            .insert(insert, returning: .representation)
            .select("id")
            .single()
            .execute()
            .value

        // 5. Insert any tags.
        let tags = Self.parseTags(request.tagsInput)
        if !tags.isEmpty {
            struct TagInsert: Encodable {
                let video_id: String
                let tag: String
            }
            let tagRows = tags.map { TagInsert(video_id: inserted.id, tag: $0) }
            try await client
                .from("video_tags")
                .insert(tagRows)
                .execute()
        }
    }

    // MARK: - Helpers

    private static func buildObjectPath(userId: String, fileExtension: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let ext = fileExtension.isEmpty ? "bin" : fileExtension
        return "\(userId)/\(timestamp)-post.\(ext)"
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
}

/// Broadcast so the feed knows to refresh after a new post lands.
extension Notification.Name {
    static let pulseDidCreatePost = Notification.Name("pulse.didCreatePost")
}
