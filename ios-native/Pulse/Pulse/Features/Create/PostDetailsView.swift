import AVFoundation
import SwiftUI
import UIKit

/// Step 2 of the create flow. Shows a preview of what the user just
/// captured, lets them add title/caption/tags, and posts.
struct PostDetailsView: View {
    let media: CapturedMedia
    let onBack: () -> Void
    let onPosted: () -> Void

    @State private var title = ""
    @State private var caption = ""
    @State private var tags = ""

    @State private var isPosting = false
    @State private var errorMessage: String?

    @State private var imagePreview: UIImage?
    @State private var videoThumbnail: UIImage?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedTitle.isEmpty && !isPosting
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewSection
                    fieldsSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Retake")
                    }
                    .foregroundStyle(.white)
                }
                .disabled(isPosting)
            }
        }
        .task { await buildPreview() }
    }

    // MARK: - Preview

    private var previewSection: some View {
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
            } else if let videoThumbnail {
                ZStack {
                    Image(uiImage: videoThumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Image(systemName: "play.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 6)
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(height: 260)
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

    private func buildPreview() async {
        switch media {
        case .photo(let data):
            if let image = UIImage(data: data) {
                await MainActor.run { imagePreview = image }
            }
        case .video(let url):
            let thumb = await Self.generateThumbnail(for: url)
            await MainActor.run { videoThumbnail = thumb }
        }
    }

    private static func generateThumbnail(for url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                return UIImage(cgImage: cgImage)
            } catch {
                return nil
            }
        }.value
    }

    private func submit() {
        guard !trimmedTitle.isEmpty else { return }
        isPosting = true
        errorMessage = nil

        Task {
            defer { isPosting = false }
            do {
                let data = try media.loadData()
                let request = CreatePostRequest(
                    title: trimmedTitle,
                    caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                    tagsInput: tags.isEmpty ? nil : tags,
                    mediaData: data,
                    contentType: media.contentType,
                    fileExtension: media.fileExtension
                )
                try await CreateService.shared.createPost(request)
                media.cleanup()
                NotificationCenter.default.post(name: .pulseDidCreatePost, object: nil)
                onPosted()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
