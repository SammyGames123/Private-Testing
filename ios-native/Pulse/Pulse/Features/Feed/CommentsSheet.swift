import SwiftUI

struct CommentsSheet: View {
    let video: FeedVideo
    let onCommentCreated: () -> Void

    @StateObject private var model: CommentsViewModel

    init(video: FeedVideo, onCommentCreated: @escaping () -> Void = {}) {
        self.video = video
        self.onCommentCreated = onCommentCreated
        _model = StateObject(wrappedValue: CommentsViewModel(videoId: video.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.isLoading && model.comments.isEmpty {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            } else if model.comments.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.34))
                    Text("No comments yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Start the conversation on this post.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                }
                .padding(.horizontal, 24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(model.comments) { comment in
                            commentRow(comment)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(Color.black.ignoresSafeArea())
        // Pin the composer via safeAreaInset rather than overlaying it in a
        // ZStack. Previously every keystroke in the vertical TextField
        // (lineLimit 1...4) resized the composer and triggered a layout pass
        // through the whole ZStack; with safeAreaInset the scroll view just
        // adjusts its inset and the keyboard handles the rest.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .task {
            await model.load()
        }
        .dismissKeyboardOnTap()
    }

    private var header: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            Text("Comments")
                .font(.headline)
                .foregroundStyle(.white)

            Text(video.title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
    }

    private func commentRow(_ comment: FeedComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            commentAvatar(comment)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(comment.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(comment.authorHandle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer(minLength: 8)

                    Text(Self.relativeDate(comment.createdAt))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.38))
                }

                Text(comment.body)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func commentAvatar(_ comment: FeedComment) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 38, height: 38)

            if let avatarURL = comment.author?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(comment.authorInitial)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())
            } else {
                Text(comment.authorInitial)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.92))
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Add a comment...", text: $model.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)

                Button {
                    Task {
                        let didCreate = await model.submit()
                        if didCreate {
                            onCommentCreated()
                        }
                    }
                } label: {
                    if model.isSubmitting {
                        ProgressView()
                            .tint(.black)
                            .frame(width: 54, height: 46)
                    } else {
                        Text("Send")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(width: 54, height: 46)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSubmitting)
                .opacity(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.92), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private static func relativeDate(_ value: String) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = ProfileDateFormatter.isoWithFractional.date(from: value) ?? ProfileDateFormatter.iso.date(from: value)
        guard let date else { return "now" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

@MainActor
private final class CommentsViewModel: ObservableObject {
    @Published private(set) var comments: [FeedComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published var draft = ""
    @Published var errorMessage: String?

    private let service = FeedService.shared
    private let videoId: String
    private var currentUserId: String?

    init(videoId: String) {
        self.videoId = videoId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        currentUserId = await SupabaseManager.shared.currentUserId()

        do {
            comments = try await service.fetchComments(videoId: videoId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submit() async -> Bool {
        guard let currentUserId else {
            errorMessage = "You need to be signed in to comment."
            return false
        }

        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return false }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let insertedComment = try await service.addComment(videoId: videoId, userId: currentUserId, body: trimmedDraft)
            draft = ""
            comments.append(insertedComment)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
