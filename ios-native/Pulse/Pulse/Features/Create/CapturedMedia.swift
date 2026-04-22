import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

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

enum PhotoFilterPreset: String, CaseIterable, Identifiable {
    case original = "Original"
    case noir = "B&W"
    case warm = "Warm"
    case cool = "Cool"

    var id: String { rawValue }
}

struct MediaEdits: Equatable {
    var photoFilter: PhotoFilterPreset = .original
    var videoTrimStart: Double = 0
    var videoTrimEnd: Double?
}

struct PreparedUploadMedia {
    let data: Data
    let contentType: String
    let fileExtension: String
    let thumbnailData: Data?
    let temporaryURL: URL?
}

enum MediaEditError: LocalizedError {
    case invalidImage
    case exportUnavailable
    case unsupportedOutputType
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Couldn't process that photo."
        case .exportUnavailable:
            return "Couldn't prepare that video for upload."
        case .unsupportedOutputType:
            return "This video format isn't supported for trimming yet."
        case .exportFailed(let message):
            return message
        }
    }
}

struct EditedMedia: Equatable {
    static let minimumTrimDuration: Double = 0.5
    private static let photoUploadMaxDimension: CGFloat = 1600
    private static let thumbnailMaxDimension: CGFloat = 1080
    private static let ciContext = CIContext()

    let original: CapturedMedia
    var edits = MediaEdits()

    func cleanup() {
        original.cleanup()
    }

    func photoPreviewImage() -> UIImage? {
        guard case .photo(let data) = original else { return nil }
        return Self.renderPhoto(from: data, preset: edits.photoFilter)
    }

    func videoDuration() async -> Double {
        guard case .video(let url) = original else { return 0 }
        return await Self.loadedDuration(for: AVURLAsset(url: url))
    }

    func resolvedTrimRange(duration: Double) -> ClosedRange<Double> {
        let safeDuration = max(duration, 0)
        guard safeDuration > 0 else { return 0...0 }

        let minimum = min(Self.minimumTrimDuration, safeDuration)
        let maxStart = max(safeDuration - minimum, 0)
        let lowerBound = min(max(edits.videoTrimStart, 0), maxStart)
        let requestedUpperBound = edits.videoTrimEnd ?? safeDuration
        let upperBound = min(max(requestedUpperBound, lowerBound + minimum), safeDuration)
        return lowerBound...upperBound
    }

    func thumbnailImage(at seconds: Double? = nil) async -> UIImage? {
        guard case .video(let url) = original else { return nil }
        return await Self.generateThumbnail(for: url, at: seconds)
    }

    func timelineThumbnails(count: Int) async -> [UIImage] {
        guard case .video(let url) = original else { return [] }
        return await Self.generateTimelineThumbnails(for: url, count: count)
    }

    func prepareForUpload() async throws -> PreparedUploadMedia {
        switch original {
        case .photo(let data):
            guard let renderedData = Self.renderPhotoData(from: data, preset: edits.photoFilter) else {
                throw MediaEditError.invalidImage
            }

            let thumbnailData = Self.renderThumbnailData(from: renderedData)

            return PreparedUploadMedia(
                data: renderedData,
                contentType: original.contentType,
                fileExtension: original.fileExtension,
                thumbnailData: thumbnailData,
                temporaryURL: nil
            )

        case .video(let url):
            let asset = AVURLAsset(url: url)
            let durationTime = try await asset.load(.duration)
            let duration = max(durationTime.seconds, 0)
            let trimRange = resolvedTrimRange(duration: duration)
            let presetName = Self.preferredExportPreset(for: asset)
            let outputType = try Self.preferredOutputType(for: asset, presetName: presetName)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("spilltop-export-\(UUID().uuidString).\(Self.fileExtension(for: outputType))")
            try await Self.exportVideo(
                asset: asset,
                range: trimRange,
                presetName: presetName,
                outputType: outputType,
                to: outputURL
            )

            let thumbnailImage = await thumbnailImage(at: trimRange.lowerBound)
            let thumbnailData = thumbnailImage.flatMap(Self.renderThumbnailData(from:))

            return PreparedUploadMedia(
                data: try Data(contentsOf: outputURL),
                contentType: Self.contentType(for: outputType),
                fileExtension: Self.fileExtension(for: outputType),
                thumbnailData: thumbnailData,
                temporaryURL: outputURL
            )
        }
    }

    private static func renderPhoto(from data: Data, preset: PhotoFilterPreset) -> UIImage? {
        let originalImage = UIImage(data: data)
        guard preset != .original else { return originalImage }
        guard let originalImage,
              let inputImage = CIImage(image: originalImage),
              let outputImage = applyFilter(to: inputImage, preset: preset),
              let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return originalImage
        }

        return UIImage(cgImage: cgImage, scale: originalImage.scale, orientation: originalImage.imageOrientation)
    }

    private static func renderPhotoData(from data: Data, preset: PhotoFilterPreset) -> Data? {
        guard let image = renderPhoto(from: data, preset: preset) else { return nil }
        let optimizedImage = resizedImageIfNeeded(image, maxDimension: photoUploadMaxDimension)
        return optimizedImage.jpegData(compressionQuality: 0.84)
    }

    private static func renderThumbnailData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return renderThumbnailData(from: image)
    }

    private static func renderThumbnailData(from image: UIImage) -> Data? {
        let optimizedImage = resizedImageIfNeeded(image, maxDimension: thumbnailMaxDimension)
        return optimizedImage.jpegData(compressionQuality: 0.76)
    }

    private static func applyFilter(to image: CIImage, preset: PhotoFilterPreset) -> CIImage? {
        switch preset {
        case .original:
            return image
        case .noir:
            let filter = CIFilter.photoEffectNoir()
            filter.inputImage = image
            return filter.outputImage
        case .warm:
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = image
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 5000, y: 40)
            return filter.outputImage
        case .cool:
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = image
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 8000, y: -20)
            return filter.outputImage
        }
    }

    private static func loadedDuration(for asset: AVURLAsset) async -> Double {
        do {
            let duration = try await asset.load(.duration)
            return max(duration.seconds, 0)
        } catch {
            return 0
        }
    }

    private static func generateThumbnail(for url: URL, at seconds: Double?) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let duration = await loadedDuration(for: asset)
            let clampedSeconds = min(max(seconds ?? 0, 0), max(duration - 0.05, 0))
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1200, height: 1200)

            do {
                let cgImage = try generator.copyCGImage(
                    at: CMTime(seconds: clampedSeconds, preferredTimescale: 600),
                    actualTime: nil
                )
                return UIImage(cgImage: cgImage)
            } catch {
                return nil
            }
        }.value
    }

    private static func generateTimelineThumbnails(for url: URL, count: Int) async -> [UIImage] {
        await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let duration = await loadedDuration(for: asset)
            guard duration > 0 else { return [] }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 300, height: 300)

            let segmentCount = max(count, 1)
            let step = duration / Double(segmentCount)
            var images: [UIImage] = []

            for index in 0..<segmentCount {
                let seconds = min((Double(index) + 0.5) * step, max(duration - 0.05, 0))

                do {
                    let cgImage = try generator.copyCGImage(
                        at: CMTime(seconds: seconds, preferredTimescale: 600),
                        actualTime: nil
                    )
                    images.append(UIImage(cgImage: cgImage))
                } catch {
                    continue
                }
            }

            return images
        }.value
    }

    private static func exportVideo(
        asset: AVAsset,
        range: ClosedRange<Double>,
        presetName: String,
        outputType: AVFileType,
        to outputURL: URL
    ) async throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw MediaEditError.exportUnavailable
        }

        guard exporter.supportedFileTypes.contains(outputType) else {
            throw MediaEditError.unsupportedOutputType
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = outputType
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
            end: CMTime(seconds: range.upperBound, preferredTimescale: 600)
        )

        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(throwing: MediaEditError.exportFailed(exporter.error?.localizedDescription ?? "Video export failed."))
                case .cancelled:
                    continuation.resume(throwing: MediaEditError.exportFailed("Video export was cancelled."))
                default:
                    continuation.resume(throwing: MediaEditError.exportFailed("Video export didn't finish."))
                }
            }
        }
    }

    private static func preferredExportPreset(for asset: AVAsset) -> String {
        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        if compatiblePresets.contains(AVAssetExportPreset1920x1080) {
            return AVAssetExportPreset1920x1080
        }
        if compatiblePresets.contains(AVAssetExportPreset1280x720) {
            return AVAssetExportPreset1280x720
        }
        return AVAssetExportPresetMediumQuality
    }

    private static func preferredOutputType(for asset: AVAsset, presetName: String) throws -> AVFileType {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw MediaEditError.exportUnavailable
        }

        let preferredTypes: [AVFileType] = [.mp4, .mov, .m4v]
        guard let outputType = preferredTypes.first(where: exporter.supportedFileTypes.contains) else {
            throw MediaEditError.unsupportedOutputType
        }

        return outputType
    }

    private static func contentType(for outputType: AVFileType) -> String {
        switch outputType {
        case .mp4:
            return "video/mp4"
        case .mov:
            return "video/quicktime"
        case .m4v:
            return "video/x-m4v"
        default:
            return "application/octet-stream"
        }
    }

    private static func fileExtension(for outputType: AVFileType) -> String {
        switch outputType {
        case .mp4:
            return "mp4"
        case .mov:
            return "mov"
        case .m4v:
            return "m4v"
        default:
            return "bin"
        }
    }

    private static func resizedImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return image }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
