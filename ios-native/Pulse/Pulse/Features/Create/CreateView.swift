import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct CreateView: View {
    @State private var pickerItem: PhotosPickerItem?

    @State private var mediaData: Data?
    @State private var mediaKind: MediaKind?
    @State private var contentType = "image/jpeg"
    @State private var fileExtension = "jpg"
    @State private var imagePreview: UIImage?

    @State private var title = ""
    @State private var caption = ""
    @State private var tags = ""

    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedTitle.isEmpty && mediaData != nil && !isPosting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        mediaSection
                        fieldsSection
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.leading)
                        }
                        submitButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Posted", isPresented: $showSuccess) {
                Button("OK", role: .cancel) { reset() }
            } message: {
                Text("Your post is live on the feed.")
            }
        }
    }

    // MARK: - Media picker

    private var mediaSection: some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        ) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )

                if let imagePreview {
                    Image(uiImage: imagePreview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if mediaKind == .video {
                    VStack(spacing: 10) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Video selected")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text("Tap to change")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "plus.viewfinder")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Pick a photo or video")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text("Tap to open your library")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(height: 240)
        }
        .buttonStyle(.plain)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadMedia(from: item) }
        }
    }

    // MARK: - Fields

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(label: "TITLE", placeholder: "Say what it is", text: $title)
            field(label: "CAPTION", placeholder: "Optional", text: $caption, multiline: true)
            field(label: "TAGS", placeholder: "music, travel, food", text: $tags)
        }
    }

    @ViewBuilder
    private func field(
        label: String,
        placeholder: String,
        text: Binding<String>,
        multiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.5)

            Group {
                if multiline {
                    TextField(placeholder, text: text, axis: .vertical)
                        .lineLimit(3...6)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.body)
            .foregroundStyle(.white)
            .tint(.accentColor)
            .autocorrectionDisabled(label == "TAGS")
            .textInputAutocapitalization(label == "TAGS" ? .never : .sentences)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.1))
            )
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button(action: submit) {
            ZStack {
                if isPosting {
                    ProgressView().tint(.white)
                } else {
                    Text("Post")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSubmit ? Color.accentColor : Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    // MARK: - Actions

    private func loadMedia(from item: PhotosPickerItem) async {
        errorMessage = nil
        imagePreview = nil
        mediaData = nil
        mediaKind = nil

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Couldn't read that file."
                return
            }
            mediaData = data

            let utType = item.supportedContentTypes.first
            let isVideo = utType?.conforms(to: .movie) ?? false
            mediaKind = isVideo ? .video : .image
            contentType = utType?.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
            fileExtension = utType?.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg")

            if !isVideo, let image = UIImage(data: data) {
                imagePreview = image
            }
        } catch {
            errorMessage = "Failed to load media: \(error.localizedDescription)"
        }
    }

    private func submit() {
        guard let mediaData, !trimmedTitle.isEmpty else { return }

        isPosting = true
        errorMessage = nil

        Task {
            defer { isPosting = false }
            do {
                let request = CreatePostRequest(
                    title: trimmedTitle,
                    caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                    tagsInput: tags.isEmpty ? nil : tags,
                    mediaData: mediaData,
                    contentType: contentType,
                    fileExtension: fileExtension
                )
                try await CreateService.shared.createPost(request)
                NotificationCenter.default.post(name: .pulseDidCreatePost, object: nil)
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reset() {
        pickerItem = nil
        mediaData = nil
        mediaKind = nil
        imagePreview = nil
        title = ""
        caption = ""
        tags = ""
    }
}
