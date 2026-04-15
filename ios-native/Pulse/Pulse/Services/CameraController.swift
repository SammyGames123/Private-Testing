import AVFoundation
import Combine
import UIKit

/// Manages the `AVCaptureSession` backing the create flow's camera
/// screen. Handles photo capture, video record/stop, and camera
/// flipping. All AVFoundation work happens on `sessionQueue`;
/// `@Published` state is marshalled back to the main actor for SwiftUI.
final class CameraController: NSObject, ObservableObject {
    enum Mode {
        case photo
        case video
    }

    enum CameraError: LocalizedError {
        case notAuthorized
        case configurationFailed
        case captureFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Camera access denied. Enable it in Settings."
            case .configurationFailed:
                return "Couldn't configure the camera."
            case .captureFailed(let reason):
                return reason
            }
        }
    }

    // MARK: - Published state

    @Published private(set) var isSessionRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var mode: Mode = .video
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published var errorMessage: String?
    /// Set when a capture finishes. The view observes this and
    /// pushes into the details step.
    @Published var capturedMedia: CapturedMedia?

    // MARK: - AVFoundation

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "pulse.camera.session")

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    private var isConfigured = false

    // MARK: - Lifecycle

    func start() {
        requestAccess { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { self.errorMessage = CameraError.notAuthorized.errorDescription }
                return
            }
            self.sessionQueue.async {
                self.configureIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                let running = self.session.isRunning
                DispatchQueue.main.async { self.isSessionRunning = running }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    // MARK: - Mode

    func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        mode = newMode
    }

    // MARK: - Flip camera

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, let currentInput = self.videoDeviceInput else { return }
            let newPosition: AVCaptureDevice.Position = (self.position == .back) ? .front : .back

            guard let newDevice = Self.bestCamera(for: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                DispatchQueue.main.async {
                    self.errorMessage = CameraError.configurationFailed.errorDescription
                }
                return
            }

            self.session.beginConfiguration()
            self.session.removeInput(currentInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoDeviceInput = newInput
                DispatchQueue.main.async { self.position = newPosition }
            } else {
                // Roll back.
                if self.session.canAddInput(currentInput) {
                    self.session.addInput(currentInput)
                }
            }
            self.session.commitConfiguration()
        }
    }

    // MARK: - Photo

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            if let connection = self.photoOutput.connection(with: .video) {
                connection.videoRotationAngle = 90
                if self.position == .front {
                    connection.isVideoMirrored = true
                }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Video

    func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }

            if let connection = self.movieOutput.connection(with: .video) {
                connection.videoRotationAngle = 90
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = (self.position == .front)
                }
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pulse-\(UUID().uuidString).mov")
            self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecording = true }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    // MARK: - Setup

    private func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    // Also request mic for video recording.
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        completion(true)
                    }
                } else {
                    completion(false)
                }
            }
        default:
            completion(false)
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        // Video input
        if let device = Self.bestCamera(for: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
        } else {
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.errorMessage = CameraError.configurationFailed.errorDescription
            }
            return
        }

        // Audio input (best-effort — still works for photos without it)
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
            audioDeviceInput = audioInput
        }

        // Photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        // Movie output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        isConfigured = true
    }

    private static func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }
}

// MARK: - Photo delegate

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async {
                self.errorMessage = CameraError.captureFailed(error.localizedDescription).errorDescription
            }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.errorMessage = CameraError.captureFailed("Empty photo data").errorDescription
            }
            return
        }
        DispatchQueue.main.async {
            self.capturedMedia = .photo(data)
        }
    }
}

// MARK: - Movie delegate

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async { self.isRecording = false }

        if let error {
            DispatchQueue.main.async {
                self.errorMessage = CameraError.captureFailed(error.localizedDescription).errorDescription
            }
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        DispatchQueue.main.async {
            self.capturedMedia = .video(outputFileURL)
        }
    }
}
