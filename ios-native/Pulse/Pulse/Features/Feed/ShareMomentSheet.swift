import SwiftUI
import UIKit

/// In-app share sheet for a feed post. Primary path is sending it as a
/// DM to contacts (mutual follows + people with an accepted DM thread).
/// Secondary path is the native share sheet for external apps.
///
/// Presentation is driven by the caller via `isPresented`. The caller
/// is responsible for handling the "share externally" fallback — when
/// the user taps "More apps" the sheet dismisses and calls
/// `onRequestExternalShare`.
struct ShareMomentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let video: FeedVideo
    let onRequestExternalShare: () -> Void

    @StateObject private var model: ShareMomentViewModel
    @State private var searchText: String = ""

    init(video: FeedVideo, onRequestExternalShare: @escaping () -> Void) {
        self.video = video
        self.onRequestExternalShare = onRequestExternalShare
        _model = StateObject(wrappedValue: ShareMomentViewModel(video: video))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            postPreview
            searchField

            if model.isLoading && model.contacts.isEmpty {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            } else if model.contacts.isEmpty {
                emptyState
            } else {
                contactList
            }
        }
        .background(Color.black.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .task {
            await model.load()
        }
        .dismissKeyboardOnTap()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            HStack {
                Text("Share")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .overlay(alignment: .trailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: - Preview row

    private var postPreview: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 48, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(video.creatorHandle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            Color.white.opacity(0.08)

            if let thumbnailURL = video.optimizedThumbnailURL(width: 200, height: 280, quality: 70) ?? video.thumbnailURL {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            } else {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            TextField("Search", text: $searchText)
                .foregroundStyle(.white)
                .tint(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Contact list

    private var contactList: some View {
        let filtered = model.filtered(for: searchText)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { contact in
                    contactRow(contact)
                }

                if filtered.isEmpty && !searchText.isEmpty {
                    Text("No matches for “\(searchText)”.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func contactRow(_ contact: UserProfile) -> some View {
        let selected = model.selectedUserIds.contains(contact.id)
        return Button {
            model.toggle(contact)
        } label: {
            HStack(spacing: 12) {
                contactAvatar(contact)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(contact.handle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 22, height: 22)

                    if selected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func contactAvatar(_ contact: UserProfile) -> some View {
        ZStack {
            Color.white.opacity(0.08)

            if let avatarURL = contact.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Text(contact.initial)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
            } else {
                Text(contact.initial)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            Text("No contacts yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Follow people back — or accept a message request — to share posts with them here.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.92))
            }

            if model.sendConfirmation != nil {
                // Keep layout steady; confirmation lives here momentarily
                // before we auto-dismiss.
                Text(model.sendConfirmation ?? " ")
                    .font(.caption)
                    .foregroundStyle(.green.opacity(0.92))
            }

            // Note field — only shown once at least one contact is
            // selected, so the sheet stays compact when browsing.
            if !model.selectedUserIds.isEmpty {
                TextField("Add a note (optional)", text: $model.note, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                Button {
                    dismiss()
                    // Deferred so dismissal animation completes before the
                    // native sheet presents — otherwise iOS aborts the
                    // presentation as "already in a transition".
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onRequestExternalShare()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("More apps")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        let didSend = await model.send()
                        if didSend {
                            NotificationCenter.default.post(name: .pulseInboxDidUpdate, object: nil)
                            // Small delay so the confirmation registers.
                            try? await Task.sleep(nanoseconds: 650_000_000)
                            dismiss()
                        }
                    }
                } label: {
                    Group {
                        if model.isSending {
                            ProgressView().tint(.black)
                        } else {
                            Text(sendButtonTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .opacity(sendButtonEnabled ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!sendButtonEnabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.95), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var sendButtonEnabled: Bool {
        !model.selectedUserIds.isEmpty && !model.isSending
    }

    private var sendButtonTitle: String {
        let count = model.selectedUserIds.count
        if count == 0 { return "Send" }
        if count == 1 { return "Send" }
        return "Send to \(count)"
    }
}

@MainActor
private final class ShareMomentViewModel: ObservableObject {
    @Published private(set) var contacts: [UserProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published var selectedUserIds: Set<String> = []
    @Published var note: String = ""
    @Published var errorMessage: String?
    @Published private(set) var sendConfirmation: String?

    private let video: FeedVideo
    private let service = FeedService.shared
    private var currentUserId: String?

    init(video: FeedVideo) {
        self.video = video
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        currentUserId = await SupabaseManager.shared.currentUserId()
        do {
            contacts = try await service.fetchShareableContacts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ contact: UserProfile) {
        if selectedUserIds.contains(contact.id) {
            selectedUserIds.remove(contact.id)
        } else {
            selectedUserIds.insert(contact.id)
        }
    }

    func filtered(for query: String) -> [UserProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return contacts }
        return contacts.filter { contact in
            contact.name.lowercased().contains(trimmed)
                || contact.handle.lowercased().contains(trimmed)
        }
    }

    @discardableResult
    func send() async -> Bool {
        guard let currentUserId else {
            errorMessage = "You need to be signed in to share."
            return false
        }
        guard !selectedUserIds.isEmpty else { return false }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let sentCount = try await service.shareMoment(
                video: video,
                toUserIds: Array(selectedUserIds),
                note: note,
                currentUserId: currentUserId
            )
            if sentCount == 0 {
                errorMessage = "Couldn't send to anyone. Try again?"
                return false
            }
            if sentCount < selectedUserIds.count {
                sendConfirmation = "Sent to \(sentCount) of \(selectedUserIds.count)."
            } else if sentCount == 1 {
                sendConfirmation = "Sent."
            } else {
                sendConfirmation = "Sent to \(sentCount)."
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
