import Foundation

/// Result of the camera flow OR the photo-library picker. The upload
/// step reads from this uniformly.
enum CapturedMedia {
    /// JPEG bytes from `AVCapturePhoto.fileDataRepresentation()` or
    /// the library picker.
    case photo(Data)
    /// Temp file URL from `AVCaptureMovieFileOutput`, OR a location
    /// we wrote library-picked bytes to.
    case video(URL)

    var kind: MediaKind {
        switch self {
        case .photo: return .image
        case .video: return .video
        }
    }

    var contentType: String {
        switch self {
        case .photo: return "image/jpeg"
        case .video: return "video/quicktime"
        }
    }

    var fileExtension: String {
        switch self {
        case .photo: return "jpg"
        case .video: return "mov"
        }
    }

    func loadData() throws -> Data {
        switch self {
        case .photo(let data):
            return data
        case .video(let url):
            return try Data(contentsOf: url)
        }
    }

    /// Drop any temp files we own (video only). Call this when the
    /// user discards a capture or successfully posts.
    func cleanup() {
        if case .video(let url) = self {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
