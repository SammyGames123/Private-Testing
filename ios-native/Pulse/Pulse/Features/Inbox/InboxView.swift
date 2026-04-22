import SwiftUI
import UIKit

struct InboxView: View {
    @Environment(\.dismiss) private var dismiss

    let showsDismissButton: Bool

    @StateObject private var model = InboxViewModel()
    @State private var activeConversation: ConversationRoute?
    @State private var selectedSegment: InboxSegment = .inbox

    enum InboxSegment: Hashable {
        case inbox
        case requests
    }

    init(showsDismissButton: Bool = false) {
        self.showsDismissButton = showsDismissButton
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock

                    if let errorMessage = model.errorMessage {
                        inlineMessage(errorMessage, tint: .red)
                    }

                    segmentedControl

                    if selectedSegment == .inbox {
                        conversationsSection
                        peopleSection
                    } else {
                        requestsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await model.load()
            }
        }
        .task {
            await model.load()
            await InboxBadgeStore.shared.markInboxOpened()
        }
        .fullScreenCover(item: $activeConversation) { route in
            ConversationView(route: route)
        }
        .dismissKeyboardOnTap()
    }

    private var segmentedControl: some View {
        // Plain picker styled to match the dark UI. Requests tab carries a
        // pill count when the user has pending requests waiting.
        HStack(spacing: 6) {
            segmentButton(title: "Inbox", segment: .inbox, badge: nil)
            segmentButton(
                title: "Requests",
                segment: .requests,
                badge: model.pendingRequests.isEmpty ? nil : model.pendingRequests.count
            )
        }
        .padding(4)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    private func segmentButton(title: String, segment: InboxSegment, badge: Int?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedSegment = segment
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(selectedSegment == segment ? .black : .white)

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(selectedSegment == segment ? .white : .black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(selectedSegment == segment ? Color.black : Color.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(selectedSegment == segment ? Color.white : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var requestsSection: some View {
        let requests = model.pendingRequests
        VStack(alignment: .leading, spacing: 12) {
            if requests.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No requests")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Messages from people you don't follow show up here first. You can accept or ignore them without letting them know.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.vertical, 20)
            } else {
                Text("Requests")
                    .font(.headline)
                    .foregroundStyle(.white)

                VStack(spacing: 10) {
                    ForEach(requests) { thread in
                        requestRow(thread)
                    }
                }
            }
        }
    }

    private func requestRow(_ thread: InboxThread) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if let currentUserId = model.currentUserId {
                    activeConversation = ConversationRoute(thread: thread, viewerUserId: currentUserId)
                }
            } label: {
                HStack(spacing: 12) {
                    avatar(
                        initial: String(thread.otherUserName.prefix(1)).uppercased(),
                        avatarURL: thread.otherUserAvatarURL
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(thread.otherUserName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            Spacer()

                            Text(inboxRelativeDate(thread.latestMessageAt))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.4))
                        }

                        Text(thread.otherUserHandle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))

                        Text(thread.latestMessage)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    Task { await model.acceptRequest(thread: thread) }
                } label: {
                    Text("Accept")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await model.declineRequest(thread: thread) }
                } label: {
                    Text("Decline")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Inbox")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Jump back into conversations or start a new one with a creator.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            if showsDismissButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var conversationsSection: some View {
        let inboxThreads = model.inboxThreads
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversations")
                .font(.headline)
                .foregroundStyle(.white)

            if model.isLoading && inboxThreads.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else if inboxThreads.isEmpty {
                Text("No conversations yet.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(spacing: 10) {
                    ForEach(inboxThreads) { thread in
                        Button {
                            if let currentUserId = model.currentUserId {
                                activeConversation = ConversationRoute(thread: thread, viewerUserId: currentUserId)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                avatar(
                                    initial: String(thread.otherUserName.prefix(1)).uppercased(),
                                    avatarURL: thread.otherUserAvatarURL
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(thread.otherUserName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)

                                        if thread.isPending,
                                           let currentUserId = model.currentUserId,
                                           thread.isPendingRequester(viewerUserId: currentUserId) {
                                            Text("Pending")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.white.opacity(0.7))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.white.opacity(0.1))
                                                .clipShape(Capsule())
                                        }

                                        Spacer()

                                        Text(inboxRelativeDate(thread.latestMessageAt))
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.4))
                                    }

                                    Text(thread.otherUserHandle)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))

                                    Text(thread.latestMessage)
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.74))
                                        .lineLimit(2)
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a conversation")
                .font(.headline)
                .foregroundStyle(.white)

            if model.suggestedCreators.isEmpty {
                Text("More creators will appear here as the directory grows.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(spacing: 10) {
                    ForEach(model.suggestedCreators) { creator in
                        HStack(spacing: 12) {
                            HStack(spacing: 12) {
                                avatar(initial: creator.initial, avatarURL: creator.avatarURL)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(creator.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)

                                    Text(creator.handle)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.52))

                                    Text(creator.bio?.isEmpty == false ? (creator.bio ?? "") : "No bio yet.")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.68))
                                        .lineLimit(2)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task {
                                    activeConversation = await model.startConversation(with: creator)
                                }
                            }

                            Spacer(minLength: 10)

                            Button {
                                Task {
                                    activeConversation = await model.startConversation(with: creator)
                                }
                            } label: {
                                Text("Message")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(Color.white)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func avatar(initial: String, avatarURL: URL?) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 50, height: 50)

            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(initial)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Text(initial)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private func inlineMessage(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint.opacity(0.95))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
    }

}

struct ConversationView: View {
    @Environment(\.dismiss) private var dismiss

    let route: ConversationRoute

    @StateObject private var model: ConversationViewModel
    @State private var activeSharedPost: SharedPostRoute?

    /// Identifier for the full-screen cover. Carries both the id (used to
    /// fetch the full post) and the in-message preview (shown while
    /// loading so the open feels instant).
    struct SharedPostRoute: Identifiable, Hashable {
        let id: String
        let preview: SharedVideoPreview?
    }

    init(route: ConversationRoute) {
        self.route = route
        _model = StateObject(wrappedValue: ConversationViewModel(route: route))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                messagesList
                footer
            }
        }
        .task {
            await model.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await model.load()
            }
        }
        .fullScreenCover(item: $activeSharedPost) { route in
            SharedPostViewerSheet(videoId: route.id, fallbackPreview: route.preview)
        }
        .dismissKeyboardOnTap()
    }

    /// Pending recipient sees Accept/Decline bar. Pending requester sees a
    /// subtle read-only notice + the composer (they can still send, each
    /// silent after the first). Accepted shows the normal composer.
    @ViewBuilder
    private var footer: some View {
        if model.currentStatus == .pending, !model.viewerIsCreator {
            pendingRecipientBar
        } else if model.currentStatus == .pending, model.viewerIsCreator {
            VStack(spacing: 0) {
                pendingRequesterNotice
                composer
            }
        } else {
            composer
        }
    }

    private var pendingRecipientBar: some View {
        VStack(spacing: 10) {
            Text("\(route.otherUserName) wants to message you.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button {
                    Task {
                        await model.accept()
                    }
                } label: {
                    Text(model.isAccepting ? "Accepting…" : "Accept")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isAccepting || model.isDeclining)

                Button {
                    Task {
                        await model.decline()
                        dismiss()
                    }
                } label: {
                    Text(model.isDeclining ? "Declining…" : "Decline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isAccepting || model.isDeclining)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.92))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .padding(.bottom, 24)
        .background(Color.black)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var pendingRequesterNotice: some View {
        Text("Request sent. \(route.otherUserName) will see a notification when you first message — replies are locked until they accept.")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 42, height: 42)

                if let avatarURL = route.otherUserAvatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            Text(String(route.otherUserName.prefix(1)).uppercased())
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                } else {
                    Text(String(route.otherUserName.prefix(1)).uppercased())
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(route.otherUserName)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(route.otherUserHandle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if model.isLoading && model.messages.isEmpty {
                        ProgressView()
                            .tint(.white)
                            .padding(.top, 40)
                    }

                    ForEach(model.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                guard let lastId = model.messages.last?.id else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ConversationMessage) -> some View {
        let isFromCurrentUser = message.senderId == route.viewerUserId
        HStack {
            if isFromCurrentUser { Spacer(minLength: 54) }

            if let sharedVideo = message.sharedVideo {
                sharedPostBubble(
                    message: message,
                    sharedVideo: sharedVideo,
                    isFromCurrentUser: isFromCurrentUser
                )
            } else {
                textBubble(message, isFromCurrentUser: isFromCurrentUser)
            }

            if !isFromCurrentUser { Spacer(minLength: 54) }
        }
        .frame(maxWidth: .infinity)
    }

    private func textBubble(_ message: ConversationMessage, isFromCurrentUser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.body)
                .font(.subheadline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(inboxRelativeDate(message.createdAt))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isFromCurrentUser ? Color.accentColor : Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// Post card bubble: thumbnail + title + creator handle. Tapping
    /// anywhere on the card opens the full-screen viewer. The sender's
    /// optional note floats above the card inside the same bubble.
    private func sharedPostBubble(
        message: ConversationMessage,
        sharedVideo: SharedVideoPreview,
        isFromCurrentUser: Bool
    ) -> some View {
        let trimmedBody = message.body.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 8) {
            if !trimmedBody.isEmpty {
                Text(trimmedBody)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }

            Button {
                guard !sharedVideo.isUnavailable else { return }
                activeSharedPost = SharedPostRoute(
                    id: sharedVideo.id,
                    preview: sharedVideo
                )
            } label: {
                sharedPostCard(sharedVideo)
            }
            .buttonStyle(.plain)
            .disabled(sharedVideo.isUnavailable)

            Text(inboxRelativeDate(message.createdAt))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
                .padding(.horizontal, 2)
        }
        .padding(10)
        .frame(maxWidth: 260, alignment: .leading)
        .background(isFromCurrentUser ? Color.accentColor.opacity(0.92) : Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func sharedPostCard(_ sharedVideo: SharedVideoPreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.black

                if sharedVideo.isUnavailable {
                    VStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Post unavailable")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else if let thumb = sharedVideo.thumbnailURL ?? sharedVideo.playbackURL {
                    AsyncImage(url: thumb) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            Color.white.opacity(0.05)
                        }
                    }
                } else {
                    Color.white.opacity(0.05)
                }

                if sharedVideo.mediaKind == .video, !sharedVideo.isUnavailable {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
            }
            .frame(width: 240, height: 320)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(sharedVideo.displayTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let creator = sharedVideo.creator {
                    Text(creator.handle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.35))
        }
        .frame(width: 240)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.92))
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message...", text: $model.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)

                Button {
                    Task {
                        await model.send()
                    }
                } label: {
                    if model.isSending {
                        ProgressView()
                            .tint(.black)
                            .frame(width: 60, height: 46)
                    } else {
                        Text("Send")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(width: 60, height: 46)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
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
}

private func inboxRelativeDate(_ value: String) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    let date = ProfileDateFormatter.isoWithFractional.date(from: value) ?? ProfileDateFormatter.iso.date(from: value)
    guard let date else { return "now" }
    return formatter.localizedString(for: date, relativeTo: Date())
}

@MainActor
private final class InboxViewModel: ObservableObject {
    @Published private(set) var threads: [InboxThread] = []
    @Published private(set) var suggestedCreators: [UserProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var currentUserId: String?
    @Published var errorMessage: String?

    private let service = FeedService.shared

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            currentUserId = await SupabaseManager.shared.currentUserId()

            guard let currentUserId else {
                threads = []
                suggestedCreators = []
                return
            }

            async let threadsTask = service.fetchInboxThreads(userId: currentUserId)
            async let creatorsTask = service.fetchCreators(excluding: currentUserId, limit: 12)

            threads = try await threadsTask
            suggestedCreators = try await creatorsTask
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startConversation(with creator: UserProfile) async -> ConversationRoute? {
        guard let currentUserId else { return nil }

        do {
            let result = try await service.startConversation(
                currentUserId: currentUserId,
                targetUserId: creator.id
            )
            await load()
            NotificationCenter.default.post(name: .pulseInboxDidUpdate, object: nil)
            // The local caller always opens threads, so they're the creator
            // side. If the thread already existed and the viewer was actually
            // the original recipient, fetchInboxThreads next load will
            // reconcile that — and the thread would already have been
            // accepted by that point anyway, so the pending/recipient
            // distinction doesn't matter here.
            return ConversationRoute(
                threadId: result.threadId,
                viewerUserId: currentUserId,
                profile: creator,
                status: result.status,
                viewerIsCreator: true
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func acceptRequest(thread: InboxThread) async {
        guard let currentUserId else { return }
        do {
            try await service.acceptMessageRequest(threadId: thread.id, viewerUserId: currentUserId)
            await load()
            NotificationCenter.default.post(name: .pulseInboxDidUpdate, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func declineRequest(thread: InboxThread) async {
        guard let currentUserId else { return }
        do {
            try await service.declineMessageRequest(threadId: thread.id, viewerUserId: currentUserId)
            await load()
            NotificationCenter.default.post(name: .pulseInboxDidUpdate, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Accepted threads + pending-requester threads (ones viewer sent out).
    var inboxThreads: [InboxThread] {
        guard let currentUserId else { return threads }
        return threads.filter { thread in
            !thread.isPendingRecipient(viewerUserId: currentUserId)
        }
    }

    /// Pending threads where the viewer is the recipient — the "Requests"
    /// tab. Ordered newest-first like the inbox.
    var pendingRequests: [InboxThread] {
        guard let currentUserId else { return [] }
        return threads.filter { thread in
            thread.isPendingRecipient(viewerUserId: currentUserId)
        }
    }
}

@MainActor
private final class ConversationViewModel: ObservableObject {
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var isAccepting = false
    @Published private(set) var isDeclining = false
    /// Mutable copy of the route's status so the view updates locally when
    /// the recipient taps Accept.
    @Published private(set) var currentStatus: MessageThreadStatus
    @Published var draft = ""
    @Published var errorMessage: String?

    private let route: ConversationRoute
    private let service = FeedService.shared

    var viewerIsCreator: Bool { route.viewerIsCreator }

    init(route: ConversationRoute) {
        self.route = route
        self.currentStatus = route.status
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            messages = try await service.fetchConversationMessages(threadId: route.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func accept() async {
        guard currentStatus == .pending, !route.viewerIsCreator else { return }
        isAccepting = true
        errorMessage = nil
        defer { isAccepting = false }

        do {
            try await service.acceptMessageRequest(
                threadId: route.id,
                viewerUserId: route.viewerUserId
            )
            currentStatus = .accepted
            NotificationCenter.default.post(name: .pulseInboxDidUpdate, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func decline() async {
        guard currentStatus == .pending, !route.viewerIsCreator else { return }
        isDeclining = true
        errorMessage = nil
        defer { isDeclining = false }

        do {
            try await service.declineMessageRequest(
                threadId: route.id,
                viewerUserId: route.viewerUserId
            )
            NotificationCenter.default.post(name: .pulseInboxDidUpdate, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send() async {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }

        let optimisticMessage = ConversationMessage(
            id: "local-\(UUID().uuidString)",
            threadId: route.id,
            senderId: route.viewerUserId,
            body: trimmedDraft,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        draft = ""
        messages.append(optimisticMessage)
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let persistedMessage = try await service.sendMessage(
                threadId: route.id,
                senderId: route.viewerUserId,
                body: trimmedDraft
            )
            if let index = messages.firstIndex(where: { $0.id == optimisticMessage.id }) {
                messages[index] = persistedMessage
            } else {
                messages.append(persistedMessage)
            }
            NotificationCenter.default.post(name: .pulseInboxDidUpdate, object: nil)
        } catch {
            messages.removeAll { $0.id == optimisticMessage.id }
            draft = trimmedDraft
            errorMessage = error.localizedDescription
        }
    }
}
