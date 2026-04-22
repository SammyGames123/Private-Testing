import SwiftUI
import UIKit
@preconcurrency import LiveKit

struct PulseLiveChatMessage: Identifiable, Equatable {
    let id: String
    let senderIdentity: String
    let senderName: String
    let body: String
    let sentAt: Date
    let isFromCurrentUser: Bool
}

struct PulseLiveReactionBurst: Identifiable, Equatable {
    let id: String
    let senderName: String
    let emoji: String
    let isFromCurrentUser: Bool
    let horizontalDrift: CGFloat
    let verticalTravel: CGFloat
    let duration: Double
}

struct PulseLiveChatPayload: Codable {
    let id: String
    let senderIdentity: String
    let senderName: String
    let body: String
    let sentAt: TimeInterval
}

struct PulseLiveReactionPayload: Codable {
    let id: String
    let senderIdentity: String
    let senderName: String
    let emoji: String
    let sentAt: TimeInterval
}

private struct PulseLiveCreatorRoute: Identifiable {
    let id = UUID()
    let creatorId: String
}

struct PulseLiveKitRoomView: View {
    @Environment(\.dismiss) private var dismiss

    let stream: LiveStream
    let isOwner: Bool
    let onEnded: (() -> Void)?

    @StateObject private var model: PulseLiveKitRoomViewModel
    @State private var isEnding = false
    @State private var endErrorMessage: String?
    @State private var chatDraft = ""
    @State private var selectedCreatorRoute: PulseLiveCreatorRoute?
    @FocusState private var isChatComposerFocused: Bool

    private let feedService = FeedService.shared

    init(stream: LiveStream, isOwner: Bool, onEnded: (() -> Void)? = nil) {
        self.stream = stream
        self.isOwner = isOwner
        self.onEnded = onEnded
        _model = StateObject(
            wrappedValue: PulseLiveKitRoomViewModel(
                stream: stream,
                isOwner: isOwner
            )
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            mediaLayer

            LinearGradient(
                colors: [.black.opacity(0.82), .clear, .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            floatingReactionsOverlay

            topBar

            VStack(alignment: .leading, spacing: 12) {
                Spacer()

                if let message = endErrorMessage ?? model.errorMessage {
                    messagePill(text: message, tint: .red)
                }

                detailsCard

                if showsChatOverlay {
                    liveChatPanel
                }

                if showsInteractionDock {
                    interactionDock
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 38)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isChatComposerFocused = false
        }
        .task {
            await model.connectIfNeeded()
        }
        .onDisappear {
            Task {
                await model.disconnect()
            }
        }
        .fullScreenCover(item: $selectedCreatorRoute) { route in
            CreatorProfileView(creatorId: route.creatorId)
        }
        .interactiveDismissDisabled(isOwner && stream.isLive)
    }

    @ViewBuilder
    private var mediaLayer: some View {
        if let track = model.primaryVideoTrack {
            PulseLiveKitVideoTrackView(
                track: track,
                mirrorMode: isOwner ? .auto : .off
            )
                .ignoresSafeArea()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.08, blue: 0.31),
                        Color(red: 0.08, green: 0.04, blue: 0.15),
                        Color.black,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 14) {
                    if model.isConnecting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: isOwner ? "video.badge.waveform.fill" : "dot.radiowaves.left.and.right")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Text(model.statusTitle)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(model.statusSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .padding(.top, 70)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if !(isOwner && stream.isLive) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
            } else {
                PulseLiveBadge(title: stream.liveBadgeTitle)
            }

            Spacer()

            topCountPill

            if isOwner && stream.isLive {
                Button {
                    Task {
                        await endStream()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isEnding {
                            ProgressView()
                                .tint(.black)
                        }

                        Text(isEnding ? "Ending..." : "End Live")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isEnding)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var topCountPill: some View {
        Label("\(model.viewerCount)", systemImage: "eye.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.34))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private var showsReactionOverlay: Bool {
        !model.remoteStreamEnded && !model.reactionBursts.isEmpty
    }

    private var showsChatOverlay: Bool {
        !model.remoteStreamEnded && !model.chatMessages.isEmpty
    }

    private var showsInteractionDock: Bool {
        !isOwner && !model.remoteStreamEnded
    }

    @ViewBuilder
    private var floatingReactionsOverlay: some View {
        if showsReactionOverlay {
            ZStack(alignment: .bottomTrailing) {
                ForEach(model.reactionBursts) { reaction in
                    PulseFloatingReactionView(reaction: reaction)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
            .padding(.bottom, isOwner ? 132 : 184)
            .allowsHitTesting(false)
        }
    }

    private var liveChatPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(model.chatMessages) { message in
                    chatBubble(message)
                        .id(message.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxWidth: 248, maxHeight: 144, alignment: .leading)
    }

    private func chatBubble(_ message: PulseLiveChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.isFromCurrentUser ? "You" : message.senderName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))

            Text(message.body)
                .font(.subheadline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 248, alignment: .leading)
        .shadow(color: .black.opacity(0.85), radius: 10, x: 0, y: 3)
    }

    private var interactionDock: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PulseLiveKitRoomViewModel.quickReactionOptions, id: \.self) { emoji in
                        Button {
                            Task {
                                await model.sendReaction(emoji)
                            }
                        } label: {
                            Text(emoji)
                                .font(.system(size: 18))
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.28))
                                .clipShape(Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canSendInteractions)
                }
            }
            .frame(width: 156)

            HStack(spacing: 8) {
                TextField(model.remoteStreamEnded ? "Live ended" : "Comment", text: $chatDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1 ... 2)
                    .focused($isChatComposerFocused)
                    .disabled(!model.canSendInteractions)

                Button {
                    let trimmedDraft = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedDraft.isEmpty else { return }
                    chatDraft = ""
                    isChatComposerFocused = false

                    Task {
                        let didSend = await model.sendChatMessage(trimmedDraft)
                        if !didSend {
                            chatDraft = trimmedDraft
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(canSendChat ? .white : .white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(!canSendChat)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.28))
            .clipShape(Capsule())
        }
        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 3)
    }

    private var canSendChat: Bool {
        model.canSendInteractions && !chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isOwner {
                Text(stream.creatorHandle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
            } else {
                Button {
                    selectedCreatorRoute = PulseLiveCreatorRoute(creatorId: stream.creatorId)
                } label: {
                    Text(stream.creatorHandle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.84))
                }
                .buttonStyle(.plain)
            }

            Text(stream.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 6) {
                Label(model.contextSubtitle, systemImage: stream.contextSystemImage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)

                if isOwner {
                    Text("• \(model.roomStateLabel)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
        .shadow(color: .black.opacity(0.85), radius: 10, x: 0, y: 4)
    }

    private func detailPill(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
    }

    private func messagePill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint.opacity(0.95))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
    }

    private func endStream() async {
        guard !isEnding else { return }
        isEnding = true
        endErrorMessage = nil
        defer { isEnding = false }

        guard let currentUserId = await SupabaseManager.shared.currentUserId() else {
            endErrorMessage = "You need to be signed in to end this live."
            return
        }

        do {
            _ = try await feedService.endLiveStream(
                streamId: stream.id,
                userId: currentUserId
            )
            await model.disconnect()
            NotificationCenter.default.post(name: .pulseDidCreatePost, object: nil)
            onEnded?()
            dismiss()
        } catch {
            endErrorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class PulseLiveKitRoomViewModel: NSObject, ObservableObject, @preconcurrency RoomDelegate {
    static let quickReactionOptions = ["🔥", "🍻", "💜", "👏"]

    private static let chatTopic = "spilltop.live.chat"
    private static let reactionTopic = "spilltop.live.reaction"
    private static let maxVisibleChatMessages = 30
    private static let maxVisibleReactionBursts = 6
    private static let genericParticipantNames: Set<String> = ["viewer", "host", "guest", "publisher", "subscriber"]

    @Published private(set) var primaryVideoTrack: VideoTrack?
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var participantCount = 0
    @Published private(set) var remoteStreamEnded = false
    @Published private(set) var chatMessages: [PulseLiveChatMessage] = []
    @Published private(set) var reactionBursts: [PulseLiveReactionBurst] = []

    let stream: LiveStream
    let isOwner: Bool

    lazy var room = Room(delegate: self)

    private let liveKitService = LiveKitService.shared
    private let feedService = FeedService.shared
    private var hasAttemptedConnect = false
    private var lastSyncedViewerCount: Int?
    private var hasRegisteredInteractionHandlers = false
    private var currentParticipantIdentity: String?
    private var currentParticipantName = "You"

    init(stream: LiveStream, isOwner: Bool) {
        self.stream = stream
        self.isOwner = isOwner
        super.init()
    }

    var roomStateLabel: String {
        if remoteStreamEnded {
            return "Ended"
        }
        if isConnected {
            return isOwner ? "Broadcasting" : "Watching"
        }
        if isConnecting {
            return "Connecting"
        }
        return "Waiting"
    }

    var viewerCount: Int {
        max(participantCount - 1, 0)
    }

    var viewerCountLabel: String {
        viewerCount == 1 ? "1 watching" : "\(viewerCount) watching"
    }

    var badgeTitle: String {
        remoteStreamEnded ? "ENDED" : stream.liveBadgeTitle
    }

    var contextTitle: String {
        remoteStreamEnded ? "Live Ended" : stream.contextTitle
    }

    var contextSubtitle: String {
        remoteStreamEnded ? "This live has ended." : stream.contextSubtitle
    }

    var canSendInteractions: Bool {
        isConnected && !remoteStreamEnded && errorMessage == nil
    }

    var statusTitle: String {
        if remoteStreamEnded {
            return "Live ended"
        }
        if let errorMessage, !errorMessage.isEmpty {
            return "Couldn't join live"
        }
        if isConnected && primaryVideoTrack == nil {
            return isOwner ? "Camera is connecting" : "Waiting for video"
        }
        if isConnecting {
            return "Joining LiveKit room"
        }
        return isOwner ? "Ready to broadcast" : "Waiting for host"
    }

    var statusSubtitle: String {
        if remoteStreamEnded {
            return "The broadcaster ended this live. You can head back whenever you're ready."
        }
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if isOwner {
            return "Spilltop is connecting your camera and microphone to your LiveKit room."
        }
        return "Spilltop is joining the live room and waiting for the broadcaster's camera feed."
    }

    func connectIfNeeded() async {
        guard !hasAttemptedConnect else { return }
        hasAttemptedConnect = true
        isConnecting = true
        errorMessage = nil

        do {
            let session = try await liveKitService.fetchSession(
                for: stream,
                as: isOwner ? .publisher : .subscriber
            )
            currentParticipantIdentity = session.participantIdentity
            currentParticipantName = await resolveCurrentParticipantName(
                fallbackName: session.participantName ?? (isOwner ? stream.creatorName : "Viewer")
            )

            try await room.connect(url: session.wsURL, token: session.token)
            try await registerInteractionHandlersIfNeeded()

            isConnected = true
            participantCount = room.remoteParticipants.count + 1
            remoteStreamEnded = false
            await syncViewerCountIfNeeded()

            if isOwner {
                try await room.localParticipant.setCamera(enabled: true)
                try await room.localParticipant.setMicrophone(enabled: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }

    func disconnect() async {
        if hasRegisteredInteractionHandlers {
            await room.unregisterTextStreamHandler(for: Self.chatTopic)
            await room.unregisterTextStreamHandler(for: Self.reactionTopic)
            hasRegisteredInteractionHandlers = false
        }

        await room.disconnect()
        isConnected = false
        isConnecting = false
        primaryVideoTrack = nil
        participantCount = 0
        chatMessages.removeAll()
        reactionBursts.removeAll()
    }

    func sendChatMessage(_ body: String) async -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendInteractions, !trimmedBody.isEmpty else { return false }
        guard ContentPolicy.isAllowed(trimmedBody) else {
            errorMessage = ContentPolicyError.blockedText.localizedDescription
            return false
        }

        let payload = PulseLiveChatPayload(
            id: UUID().uuidString.lowercased(),
            senderIdentity: currentParticipantIdentity ?? "local",
            senderName: currentParticipantName,
            body: trimmedBody,
            sentAt: Date().timeIntervalSince1970
        )

        do {
            let encodedPayload = try JSONEncoder().encode(payload)
            guard let text = String(data: encodedPayload, encoding: .utf8) else {
                throw LiveStreamInteractionError.invalidPayload
            }

            try await room.localParticipant.sendText(text, for: Self.chatTopic)
            appendChatMessage(
                PulseLiveChatMessage(
                    id: payload.id,
                    senderIdentity: payload.senderIdentity,
                    senderName: payload.senderName,
                    body: payload.body,
                    sentAt: Date(timeIntervalSince1970: payload.sentAt),
                    isFromCurrentUser: true
                )
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Couldn't send message."
            return false
        }
    }

    func sendReaction(_ emoji: String) async {
        guard canSendInteractions else { return }

        let payload = PulseLiveReactionPayload(
            id: UUID().uuidString.lowercased(),
            senderIdentity: currentParticipantIdentity ?? "local",
            senderName: currentParticipantName,
            emoji: emoji,
            sentAt: Date().timeIntervalSince1970
        )

        do {
            let encodedPayload = try JSONEncoder().encode(payload)
            guard let text = String(data: encodedPayload, encoding: .utf8) else {
                throw LiveStreamInteractionError.invalidPayload
            }

            try await room.localParticipant.sendText(text, for: Self.reactionTopic)
            appendReaction(
                PulseLiveReactionBurst(
                    id: payload.id,
                    senderName: payload.senderName,
                    emoji: payload.emoji,
                    isFromCurrentUser: true,
                    horizontalDrift: Self.randomReactionDrift(),
                    verticalTravel: Self.randomReactionRise(),
                    duration: Self.randomReactionDuration()
                )
            )
            errorMessage = nil

            // Fire-and-forget: persist to Supabase so reactions count toward
            // the creator's leaderboard points. The owner reacting on their
            // own stream is skipped (self-reactions don't earn points). RPC
            // failures are swallowed — visual feedback already happened and
            // one dropped reaction isn't worth nagging the viewer about.
            if !isOwner {
                let streamId = stream.id
                Task {
                    try? await SupabaseManager.shared.client
                        .rpc("send_live_reaction", params: LiveReactionRPCParams(p_stream_id: streamId))
                        .execute()
                }
            }
        } catch {
            errorMessage = "Couldn't send reaction."
        }
    }

    private struct LiveReactionRPCParams: Encodable {
        let p_stream_id: String
    }

    private func resolveCurrentParticipantName(fallbackName: String) async -> String {
        guard let currentUserId = await SupabaseManager.shared.currentUserId() else {
            return Self.preferredDisplayName(primary: nil, fallback: fallbackName)
        }

        do {
            if let profile = try await feedService.fetchCurrentProfile(userId: currentUserId) {
                return profile.name
            }
        } catch {}

        if let session = await SupabaseManager.shared.currentSession(),
           let email = session.user.email {
            return Self.preferredDisplayName(primary: email.components(separatedBy: "@").first, fallback: fallbackName)
        }

        return Self.preferredDisplayName(primary: nil, fallback: fallbackName)
    }

    private func registerInteractionHandlersIfNeeded() async throws {
        guard !hasRegisteredInteractionHandlers else { return }

        try await room.registerTextStreamHandler(for: Self.chatTopic) { [weak self] reader, participantIdentity in
            guard let self else { return }
            let payloadText = try await reader.readAll()
            await self.handleIncomingChatPayload(payloadText, participantIdentity: participantIdentity.stringValue)
        }

        try await room.registerTextStreamHandler(for: Self.reactionTopic) { [weak self] reader, participantIdentity in
            guard let self else { return }
            let payloadText = try await reader.readAll()
            await self.handleIncomingReactionPayload(payloadText, participantIdentity: participantIdentity.stringValue)
        }

        hasRegisteredInteractionHandlers = true
    }

    private func handleIncomingChatPayload(_ payloadText: String, participantIdentity: String) {
        guard let data = payloadText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PulseLiveChatPayload.self, from: data) else {
            return
        }

        appendChatMessage(
            PulseLiveChatMessage(
                id: payload.id,
                senderIdentity: payload.senderIdentity,
                senderName: resolveDisplayName(for: participantIdentity, fallbackName: payload.senderName),
                body: payload.body,
                sentAt: Date(timeIntervalSince1970: payload.sentAt),
                isFromCurrentUser: payload.senderIdentity == currentParticipantIdentity
            )
        )
    }

    private func handleIncomingReactionPayload(_ payloadText: String, participantIdentity: String) {
        guard let data = payloadText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PulseLiveReactionPayload.self, from: data) else {
            return
        }

        appendReaction(
            PulseLiveReactionBurst(
                id: payload.id,
                senderName: resolveDisplayName(for: participantIdentity, fallbackName: payload.senderName),
                emoji: payload.emoji,
                isFromCurrentUser: payload.senderIdentity == currentParticipantIdentity,
                horizontalDrift: Self.randomReactionDrift(),
                verticalTravel: Self.randomReactionRise(),
                duration: Self.randomReactionDuration()
            )
        )
    }

    private func resolveDisplayName(for participantIdentity: String, fallbackName: String) -> String {
        if participantIdentity == currentParticipantIdentity {
            return currentParticipantName
        }

        if let participant = room.remoteParticipants.values.first(where: { $0.identity?.stringValue == participantIdentity }),
           let name = participant.name,
           let preferredName = Self.normalizedDisplayName(name) {
            return preferredName
        }

        return Self.preferredDisplayName(primary: fallbackName, fallback: "Someone")
    }

    private func appendChatMessage(_ message: PulseLiveChatMessage) {
        guard !chatMessages.contains(where: { $0.id == message.id }) else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            chatMessages.append(message)
            if chatMessages.count > Self.maxVisibleChatMessages {
                chatMessages.removeFirst(chatMessages.count - Self.maxVisibleChatMessages)
            }
        }
    }

    private func appendReaction(_ reaction: PulseLiveReactionBurst) {
        guard !reactionBursts.contains(where: { $0.id == reaction.id }) else { return }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            reactionBursts.append(reaction)
            if reactionBursts.count > Self.maxVisibleReactionBursts {
                reactionBursts.removeFirst(reactionBursts.count - Self.maxVisibleReactionBursts)
            }
        }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.expireReaction(id: reaction.id)
        }
    }

    private func expireReaction(id: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            reactionBursts.removeAll { $0.id == id }
        }
    }

    private func markRemoteStreamEndedIfNeeded() {
        guard !isOwner, !remoteStreamEnded else { return }
        remoteStreamEnded = true
        primaryVideoTrack = nil
        isConnected = false
        errorMessage = nil
        chatMessages.removeAll()
        reactionBursts.removeAll()
        Task {
            await room.disconnect()
        }
    }

    private static func normalizedDisplayName(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !genericParticipantNames.contains(trimmed.lowercased()) else { return nil }
        return trimmed
    }

    private static func preferredDisplayName(primary: String?, fallback: String) -> String {
        normalizedDisplayName(primary) ?? normalizedDisplayName(fallback) ?? "Someone"
    }

    private static func randomReactionDrift() -> CGFloat {
        CGFloat(Double.random(in: -54 ... 18))
    }

    private static func randomReactionRise() -> CGFloat {
        CGFloat(Double.random(in: 120 ... 188))
    }

    private static func randomReactionDuration() -> Double {
        Double.random(in: 2.0 ... 2.8)
    }

    private func syncViewerCountIfNeeded() async {
        guard isOwner else { return }
        let nextViewerCount = viewerCount
        guard lastSyncedViewerCount != nextViewerCount else { return }
        lastSyncedViewerCount = nextViewerCount

        guard let currentUserId = await SupabaseManager.shared.currentUserId() else { return }
        try? await feedService.updateLiveViewerCount(
            streamId: stream.id,
            userId: currentUserId,
            viewerCount: nextViewerCount
        )
    }

    func room(_: Room, participant _: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        guard isOwner, let track = publication.track as? VideoTrack else { return }
        Task { @MainActor in
            primaryVideoTrack = track
            participantCount = room.remoteParticipants.count + 1
            await syncViewerCountIfNeeded()
        }
    }

    func room(_: Room, participantDidConnect _: RemoteParticipant) {
        Task { @MainActor in
            participantCount = room.remoteParticipants.count + 1
            await syncViewerCountIfNeeded()
        }
    }

    func room(_: Room, participantDidDisconnect _: RemoteParticipant) {
        Task { @MainActor in
            participantCount = room.remoteParticipants.count + 1
            if !isOwner && room.remoteParticipants.isEmpty {
                markRemoteStreamEndedIfNeeded()
            }
            await syncViewerCountIfNeeded()
        }
    }

    func room(_: Room, participant _: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        guard let track = publication.track as? VideoTrack else { return }
        Task { @MainActor in
            remoteStreamEnded = false
            if !isOwner || primaryVideoTrack == nil {
                primaryVideoTrack = track
            }
            participantCount = room.remoteParticipants.count + 1
            await syncViewerCountIfNeeded()
        }
    }

    func room(_: Room, participant _: RemoteParticipant, didUnsubscribeTrack _: RemoteTrackPublication) {
        Task { @MainActor in
            participantCount = room.remoteParticipants.count + 1
            if !isOwner && room.remoteParticipants.isEmpty {
                markRemoteStreamEndedIfNeeded()
            }
            await syncViewerCountIfNeeded()
        }
    }

    func room(_: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in
            isConnected = false
            if isOwner {
                if let error {
                    errorMessage = error.localizedDescription
                }
            } else {
                markRemoteStreamEndedIfNeeded()
            }
            await syncViewerCountIfNeeded()
        }
    }
}

private struct PulseFloatingReactionView: View {
    let reaction: PulseLiveReactionBurst

    @State private var hasAnimated = false

    var body: some View {
        Text(reaction.emoji)
            .font(.system(size: 34))
            .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 4)
            .scaleEffect(hasAnimated ? 1.18 : 0.84)
            .offset(
                x: hasAnimated ? reaction.horizontalDrift : 0,
                y: hasAnimated ? -reaction.verticalTravel : 0
            )
            .opacity(hasAnimated ? 0.0 : 1.0)
            .onAppear {
                withAnimation(.easeOut(duration: reaction.duration)) {
                    hasAnimated = true
                }
            }
    }
}

private struct PulseLiveKitVideoTrackView: UIViewRepresentable {
    let track: VideoTrack
    let mirrorMode: VideoView.MirrorMode

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.clipsToBounds = true
        view.contentMode = .scaleAspectFill
        view.mirrorMode = mirrorMode
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        uiView.track = track
        uiView.mirrorMode = mirrorMode
    }
}

private enum LiveStreamInteractionError: LocalizedError {
    case invalidPayload
}
