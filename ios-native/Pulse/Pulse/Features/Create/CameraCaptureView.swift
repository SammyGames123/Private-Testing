import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Camera-first capture screen — mirrors Instagram/TikTok's create
/// entry point. Top bar: close + flip. Center: live preview. Bottom:
/// PHOTO/VIDEO mode toggle, shutter, and library picker corner button.
struct CameraCaptureView: View {
    /// Called when the user dismisses the create flow entirely.
    let onCancel: () -> Void
    /// Called when a photo or video is ready to go to the details step.
    let onCapture: (CapturedMedia) -> Void

    @StateObject private var camera = CameraController()
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingPicked = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewLayerView(session: camera.session)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomControls
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)

            if let error = camera.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.bottom, 180)
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capturedMedia) { _, media in
            guard let media else { return }
            camera.capturedMedia = nil
            onCapture(media)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }

            Spacer()

            Button {
                camera.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 18) {
            modeToggle

            HStack(alignment: .center) {
                libraryButton
                    .frame(maxWidth: .infinity, alignment: .leading)

                shutterButton

                // Spacer matching the library button so the shutter
                // stays centered.
                Color.clear
                    .frame(width: 56, height: 56)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 28) {
            modePill("PHOTO", isActive: camera.mode == .photo) {
                guard !camera.isRecording else { return }
                camera.setMode(.photo)
            }
            modePill("VIDEO", isActive: camera.mode == .video) {
                guard !camera.isRecording else { return }
                camera.setMode(.video)
            }
        }
    }

    private func modePill(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(isActive ? .white : .white.opacity(0.55))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isActive ? Color.white.opacity(0.18) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var shutterButton: some View {
        Button(action: shutterTapped) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)

                Group {
                    if camera.mode == .photo {
                        Circle()
                            .fill(.white)
                            .frame(width: 62, height: 62)
                    } else if camera.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.red)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 62, height: 62)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: camera.isRecording)
                .animation(.easeInOut(duration: 0.15), value: camera.mode)
            }
        }
        .buttonStyle(.plain)
        .disabled(!camera.isSessionRunning)
    }

    private var libraryButton: some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        ) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.4), lineWidth: 1)
                    )
                    .frame(width: 56, height: 56)

                if isLoadingPicked {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoadingPicked)
    }

    // MARK: - Actions

    private func shutterTapped() {
        switch camera.mode {
        case .photo:
            camera.capturePhoto()
        case .video:
            if camera.isRecording {
                camera.stopRecording()
            } else {
                camera.startRecording()
            }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        isLoadingPicked = true
        defer { isLoadingPicked = false }

        let utType = item.supportedContentTypes.first
        let isVideo = utType?.conforms(to: .movie) ?? false

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                camera.errorMessage = "Couldn't read that file."
                return
            }

            if isVideo {
                let ext = utType?.preferredFilenameExtension ?? "mov"
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("spilltop-picked-\(UUID().uuidString).\(ext)")
                try data.write(to: tempURL)
                pickerItem = nil
                onCapture(.video(tempURL))
            } else {
                pickerItem = nil
                onCapture(.photo(data))
            }
        } catch {
            camera.errorMessage = "Failed to load media: \(error.localizedDescription)"
        }
    }
}

extension CapturedMedia: Equatable {
    static func == (lhs: CapturedMedia, rhs: CapturedMedia) -> Bool {
        switch (lhs, rhs) {
        case (.photo(let a), .photo(let b)):
            return a == b
        case (.video(let a), .video(let b)):
            return a == b
        default:
            return false
        }
    }
}
