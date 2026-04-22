import AVFoundation
import PhotosUI
import Supabase
import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var authState: AuthState

    let onCreateRequested: () -> Void

    @StateObject private var model = ProfileViewModel()
    @State private var selectedPostsRoute: ProfilePostsRoute?
    @State private var selectedLiveStream: LiveStream?
    @State private var isShowingEditProfile = false
    @State private var isShowingSettings = false
    @State private var editingVideo: FeedVideo?
    @State private var pendingDeletionVideo: FeedVideo?

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    init(onCreateRequested: @escaping () -> Void = {}) {
        self.onCreateRequested = onCreateRequested
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.isLoading && model.profile == nil && model.videos.isEmpty {
                ProgressView()
                    .tint(.white)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        topBar
                        headerSection

                        if let errorMessage = model.errorMessage {
                            inlineMessage(errorMessage, tint: .red)
                        }

                        statsSection
                        actionsSection
                        liveSection
                        postsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 110)
                }
                .refreshable {
                    await model.refresh(session: authState.session)
                }
            }
        }
        .task(id: authState.session?.user.id) {
            await model.load(session: authState.session)
        }
        .sheet(isPresented: $isShowingEditProfile) {
            if let session = authState.session {
                EditProfileSheet(model: model, session: session)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            ProfileSettingsSheet(authState: authState)
        }
        .sheet(item: $editingVideo) { video in
            if let session = authState.session {
                EditPostSheet(model: model, session: session, video: video)
            }
        }
        .fullScreenCover(item: $selectedPostsRoute) { route in
            ProfilePostsFeedView(videos: route.videos, initialVideoId: route.initialVideoId, showsPageLabel: true)
        }
        .fullScreenCover(item: $selectedLiveStream) { stream in
            LiveStreamViewerView(stream: stream, isOwner: true)
        }
        .confirmationDialog(
            "Delete this post?",
            isPresented: Binding(
                get: { pendingDeletionVideo != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionVideo = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete post", role: .destructive) {
                guard let video = pendingDeletionVideo else { return }
                Task {
                    await model.delete(video: video, session: authState.session)
                    pendingDeletionVideo = nil
                }
            }

            Button("Cancel", role: .cancel) {
                pendingDeletionVideo = nil
            }
        } message: {
            Text("This will permanently remove the post from your profile.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseDidCreatePost)) { notification in
            if let source = notification.object as? String, source == PulseRefreshSource.profileMutation {
                return
            }
            Task {
                await model.refresh(session: authState.session)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("Profile")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Spacer()

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            PulseInboxLaunchButton()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 14) {
            avatarView

            VStack(spacing: 4) {
                Text(profileName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(profileHandle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if let bio = profileBio, !bio.isEmpty {
                Text(bio)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 96, height: 96)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )

            if let avatarURL = model.profile?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(profileInitial)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .id(avatarURL.absoluteString)
                .frame(width: 96, height: 96)
                .clipShape(Circle())
            } else {
                Text(profileInitial)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 10) {
            statPill(value: "\(model.stats.postsCount)", title: "Posts")
            statPill(value: ProfileCountFormatter.string(for: model.stats.followersCount), title: "Followers")
            statPill(value: ProfileCountFormatter.string(for: model.stats.followingCount), title: "Following")
        }
    }

    private var actionsSection: some View {
        Button {
            isShowingEditProfile = true
        } label: {
            Text("Edit profile")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var liveSection: some View {
        if let activeLiveStream = model.activeLiveStream {
            LiveStreamFeatureCard(
                stream: activeLiveStream,
                primaryActionTitle: "Open live"
            ) {
                selectedLiveStream = activeLiveStream
            }
        }
    }

    @ViewBuilder
    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posts")
                .font(.headline)
                .foregroundStyle(.white)

            if model.videos.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: gridColumns, spacing: 4) {
                    ForEach(model.videos) { video in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                selectedPostsRoute = ProfilePostsRoute(
                                    videos: model.videos,
                                    initialVideoId: video.id
                                )
                            } label: {
                                ProfileGridCell(video: video, showsCreatorAvatar: true)
                            }
                            .buttonStyle(.plain)

                            PostManagementMenu(
                                video: video,
                                onEdit: {
                                    editingVideo = video
                                },
                                onTogglePin: {
                                    Task {
                                        await model.togglePin(video: video, session: authState.session)
                                    }
                                },
                                onToggleArchive: {
                                    Task {
                                        await model.toggleArchive(video: video, session: authState.session)
                                    }
                                },
                                onDelete: {
                                    pendingDeletionVideo = video
                                }
                            )
                            .padding(8)
                        }
                    }
                }

                Text("Tap the ... button on a post to edit, pin, archive, or delete it.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            VStack(spacing: 6) {
                Text("No posts yet")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Your uploads will show up here as a clean profile grid.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
            }

            Button {
                onCreateRequested()
            } label: {
                Text("Create your first post")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 24)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func statPill(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
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

    private var profileName: String {
        if let profile = model.profile {
            return profile.name
        }

        if let email = authState.session?.user.email, !email.isEmpty {
            return email.components(separatedBy: "@").first?.capitalized ?? email
        }

        return "Creator"
    }

    private var profileHandle: String {
        if let profile = model.profile {
            return profile.handle
        }

        if let email = authState.session?.user.email, !email.isEmpty {
            return email
        }

        return "@creator"
    }

    private var profileBio: String? {
        model.profile?.bio
    }

    private var profileInitial: String {
        if let initial = model.profile?.initial, !initial.isEmpty {
            return initial
        }

        return String(profileName.prefix(1)).uppercased()
    }
}

@MainActor
private final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var videos: [FeedVideo] = []
    @Published private(set) var activeLiveStream: LiveStream?
    @Published private(set) var stats = ProfileStats(postsCount: 0, followersCount: 0, followingCount: 0)
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var saveErrorMessage: String?

    private let service = FeedService.shared

    func load(session: Session?) async {
        guard let session else {
            reset()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let userId = session.user.id.uuidString.lowercased()

        do {
            async let profileTask = service.fetchCurrentProfile(userId: userId)
            async let postsTask = service.fetchPostsForCurrentUser(userId: userId)
            async let statsTask = service.fetchProfileStats(userId: userId)
            async let liveTask = service.fetchActiveLiveStream(creatorId: userId)

            profile = try await profileTask
            videos = try await postsTask
            stats = try await statsTask
            activeLiveStream = try await liveTask
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(session: Session?) async {
        await load(session: session)
    }

    func saveProfile(
        session: Session,
        displayName: String,
        username: String,
        bio: String,
        avatarJPEGData: Data?
    ) async -> Bool {
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }

        do {
            let normalizedUserId = session.user.id.uuidString.lowercased()
            profile = try await service.updateCurrentProfile(
                userId: session.user.id.uuidString.lowercased(),
                email: session.user.email,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                usernameInput: username,
                bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarJPEGData: avatarJPEGData,
                existingAvatarUrlString: profile?.avatarUrlString
            )
            if let refreshedVideos = try? await service.fetchPostsForCurrentUser(userId: normalizedUserId) {
                videos = refreshedVideos
            }
            NotificationCenter.default.post(name: .pulseDidCreatePost, object: PulseRefreshSource.profileMutation)
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }

    func togglePin(video: FeedVideo, session: Session?) async {
        guard let session else { return }

        do {
            try await service.updatePostPinState(
                videoId: video.id,
                userId: session.user.id.uuidString.lowercased(),
                isPinned: !video.isPinned
            )
            await refresh(session: session)
            NotificationCenter.default.post(name: .pulseDidCreatePost, object: PulseRefreshSource.profileMutation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleArchive(video: FeedVideo, session: Session?) async {
        guard let session else { return }

        do {
            try await service.updatePostArchiveState(
                videoId: video.id,
                userId: session.user.id.uuidString.lowercased(),
                isArchived: !video.isArchived
            )
            await refresh(session: session)
            NotificationCenter.default.post(name: .pulseDidCreatePost, object: PulseRefreshSource.profileMutation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(video: FeedVideo, session: Session?) async {
        guard let session else { return }

        do {
            try await service.deletePost(
                videoId: video.id,
                userId: session.user.id.uuidString.lowercased()
            )
            await refresh(session: session)
            NotificationCenter.default.post(name: .pulseDidCreatePost, object: PulseRefreshSource.profileMutation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        profile = nil
        videos = []
        activeLiveStream = nil
        stats = ProfileStats(postsCount: 0, followersCount: 0, followingCount: 0)
        errorMessage = nil
        saveErrorMessage = nil
        isLoading = false
        isSaving = false
    }
}

private struct EditPostSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var model: ProfileViewModel
    let session: Session
    let video: FeedVideo

    @State private var title: String
    @State private var caption: String
    @State private var tags = ""
    @State private var isLoadingTags = true
    @State private var didLoadTags = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let service = FeedService.shared

    init(model: ProfileViewModel, session: Session, video: FeedVideo) {
        self.model = model
        self.session = session
        self.video = video
        _title = State(initialValue: video.title)
        _caption = State(initialValue: video.caption ?? "")
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && !isSaving && didLoadTags
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        previewCard

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.red.opacity(0.28), lineWidth: 1)
                                )
                        }

                        editorField(label: "Title") {
                            TextField("Say what it is", text: $title)
                        }

                        editorField(label: "Caption") {
                            TextField("Optional", text: $caption, axis: .vertical)
                                .lineLimit(3...6)
                        }

                        editorField(
                            label: "Tags",
                            helper: didLoadTags ? "Separate tags with commas." : nil
                        ) {
                            if isLoadingTags {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Loading tags...")
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                            } else {
                                TextField("music, travel, food", text: $tags)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Post status")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.58))
                                .textCase(.uppercase)

                            HStack(spacing: 8) {
                                statusBadge(video.isPinned ? "Pinned" : "Not pinned")
                                statusBadge(video.isArchived ? "Archived" : "Visible")
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .disabled(!canSave)
                }
            }
            .task(id: video.id) {
                await loadTags()
            }
            .dismissKeyboardOnTap()
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .textCase(.uppercase)

            HStack {
                Spacer()
                ProfileGridCell(video: video)
                    .frame(width: 180)
                Spacer()
            }
        }
    }

    private func editorField<Content: View>(
        label: String,
        helper: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .textCase(.uppercase)

            content()
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )

            if let helper {
                Text(helper)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func statusBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func loadTags() async {
        isLoadingTags = true
        didLoadTags = false
        errorMessage = nil

        do {
            let loadedTags = try await service.fetchTags(videoId: video.id)
            tags = loadedTags.joined(separator: ", ")
            didLoadTags = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingTags = false
    }

    private func save() {
        guard canSave else { return }

        isSaving = true
        errorMessage = nil

        Task { @MainActor in
            defer { isSaving = false }

            do {
                try await service.updatePostDetails(
                    videoId: video.id,
                    userId: session.user.id.uuidString.lowercased(),
                    title: title,
                    caption: caption,
                    tagsInput: tags
                )
                await model.refresh(session: session)
                NotificationCenter.default.post(name: .pulseDidCreatePost, object: PulseRefreshSource.profileMutation)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var model: ProfileViewModel
    let session: Session

    @State private var displayName: String
    @State private var username: String
    @State private var bio: String
    @State private var isShowingAvatarPicker = false
    @State private var selectedAvatarImage: UIImage?
    @State private var selectedAvatarJPEGData: Data?
    @State private var isLoadingAvatar = false
    @State private var avatarErrorMessage: String?

    init(model: ProfileViewModel, session: Session) {
        self.model = model
        self.session = session
        _displayName = State(initialValue: model.profile?.displayName ?? "")
        _username = State(initialValue: model.profile?.username ?? "")
        _bio = State(initialValue: model.profile?.bio ?? "")
    }

    private var activeErrorMessage: String? {
        avatarErrorMessage ?? model.saveErrorMessage
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let activeErrorMessage {
                            Text(activeErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.red.opacity(0.28), lineWidth: 1)
                                )
                        }

                        avatarEditor

                        profileField(label: "Display name") {
                            TextField("Sammy Rivers", text: $displayName)
                        }

                        profileField(label: "Username", helper: "Letters, numbers, and underscores work best.") {
                            TextField("sammy", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        profileField(label: "Bio") {
                            TextField(
                                "Builder, editor, and all-night idea collector.",
                                text: $bio,
                                axis: .vertical
                            )
                            .lineLimit(4...6)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.58))
                                .textCase(.uppercase)

                            Text(session.user.email ?? "No email")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            let didSave = await model.saveProfile(
                                session: session,
                                displayName: displayName,
                                username: username,
                                bio: bio,
                                avatarJPEGData: selectedAvatarJPEGData
                            )
                            if didSave {
                                dismiss()
                            }
                        }
                    } label: {
                        if model.isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .disabled(model.isSaving || isLoadingAvatar)
                }
            }
            .onAppear {
                model.saveErrorMessage = nil
                avatarErrorMessage = nil
            }
            .sheet(isPresented: $isShowingAvatarPicker) {
                AvatarImagePicker(
                    onImagePicked: handleAvatarSelection(_:),
                    onError: { message in
                        avatarErrorMessage = message
                    }
                )
            }
            .dismissKeyboardOnTap()
        }
    }

    private var avatarEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile photo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .textCase(.uppercase)

            HStack(spacing: 16) {
                profileAvatarPreview

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        isShowingAvatarPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            if isLoadingAvatar {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "photo")
                                    .font(.subheadline.weight(.semibold))
                            }

                            Text(isLoadingAvatar ? "Loading..." : "Choose photo")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingAvatar)

                    Text("Square photos work best. We’ll crop and optimize it for the profile avatar.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var profileAvatarPreview: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 96, height: 96)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )

            if let selectedAvatarImage {
                Image(uiImage: selectedAvatarImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
            } else if let avatarURL = model.profile?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(model.profile?.initial ?? "C")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .id(avatarURL.absoluteString)
                .frame(width: 96, height: 96)
                .clipShape(Circle())
            } else {
                Text(model.profile?.initial ?? "C")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private func profileField<Content: View>(
        label: String,
        helper: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .textCase(.uppercase)

            content()
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )

            if let helper {
                Text(helper)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func handleAvatarSelection(_ image: UIImage) {
        isLoadingAvatar = true
        avatarErrorMessage = nil
        defer { isLoadingAvatar = false }

        let processedImage = Self.preparedAvatarImage(from: image)
        guard let jpegData = processedImage.jpegData(compressionQuality: 0.86) else {
            avatarErrorMessage = "Couldn't prepare that photo for upload."
            return
        }

        selectedAvatarImage = processedImage
        selectedAvatarJPEGData = jpegData
    }

    private static func preparedAvatarImage(from image: UIImage) -> UIImage {
        let cropSide = min(image.size.width, image.size.height)
        let cropOrigin = CGPoint(
            x: (image.size.width - cropSide) / 2,
            y: (image.size.height - cropSide) / 2
        )
        let cropRect = CGRect(origin: cropOrigin, size: CGSize(width: cropSide, height: cropSide))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let outputSide: CGFloat = 512
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format)

        return renderer.image { _ in
            image.draw(in: CGRect(x: -cropRect.origin.x * (outputSide / cropRect.width),
                                  y: -cropRect.origin.y * (outputSide / cropRect.height),
                                  width: image.size.width * (outputSide / cropRect.width),
                                  height: image.size.height * (outputSide / cropRect.height)))
        }
    }
}

private struct ProfileSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var authState: AuthState

    // Privacy
    @State private var isPrivateAccount = false
    @State private var isPrivateLoading = false
    @State private var isPrivateFirstLoad = true

    // Notifications — stored in UserDefaults for now; wire to real push
    // preferences when we add APNs/FCM.
    @AppStorage("spilltop.notif.likes")    private var notifyLikes = true
    @AppStorage("spilltop.notif.comments") private var notifyComments = true
    @AppStorage("spilltop.notif.follows")  private var notifyFollows = true
    @AppStorage("spilltop.notif.dms")      private var notifyDMs = true
    @AppStorage("spilltop.notif.lives")    private var notifyLives = true

    // Destructive
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var isDeletingAccount = false

    // General
    @State private var errorMessage: String?
    @State private var isShowingReport = false

    private var appVersionLabel: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        privacySection
                        safetySection
                        notificationsSection
                        dataSection
                        aboutSection
                        accountSection
                    }
                    .padding(16)
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .task { await loadPrivacyState() }
            .confirmationDialog("Sign out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await authState.signOut()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    Task { await performDelete() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your profile, moments, and sign-in record. This can't be undone.")
            }
            .alert("Couldn't update", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $isShowingReport) {
                // Self-report as a generic "report a problem" entry point.
                // Target: self so the report ties to the reporter; the note
                // captures the actual content. Keeps us on a single table.
                if let userId = authState.session?.user.id.uuidString.lowercased() {
                    ReportSheet(target: .user(userId), subjectLabel: "a bug or concern")
                }
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        settingsCard(
            title: "Privacy",
            subtitle: "Control who sees your profile and moments."
        ) {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private account")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("New followers need your approval before they can see your content.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.56))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if isPrivateLoading {
                        ProgressView().tint(.white)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { isPrivateAccount },
                            set: { newValue in
                                Task { await togglePrivate(newValue) }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                NavigationLink {
                    FollowRequestsView()
                } label: {
                    settingsRow(
                        title: "Follow requests",
                        systemImage: "person.crop.circle.badge.checkmark",
                        trailing: "chevron.right"
                    )
                }
            }
        }
    }

    // MARK: - Safety

    private var safetySection: some View {
        settingsCard(
            title: "Safety",
            subtitle: "Manage people you've blocked and flag anything that feels off."
        ) {
            VStack(spacing: 10) {
                NavigationLink {
                    BlockedUsersView()
                } label: {
                    settingsRow(title: "Blocked accounts", systemImage: "hand.raised.fill", trailing: "chevron.right")
                }

                Button {
                    isShowingReport = true
                } label: {
                    settingsRow(title: "Report a problem", systemImage: "exclamationmark.bubble", trailing: "chevron.right")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        settingsCard(
            title: "Notifications",
            subtitle: "Pick what you want to hear about. Changes sync to your account so they apply on every device."
        ) {
            VStack(spacing: 8) {
                notifToggle(title: "Likes", isOn: $notifyLikes)
                notifToggle(title: "Comments", isOn: $notifyComments)
                notifToggle(title: "New followers", isOn: $notifyFollows)
                notifToggle(title: "Direct messages", isOn: $notifyDMs)
                notifToggle(title: "Friends going live", isOn: $notifyLives)
            }
            .onChange(of: notifyLikes)    { _, _ in syncNotificationPrefs() }
            .onChange(of: notifyComments) { _, _ in syncNotificationPrefs() }
            .onChange(of: notifyFollows)  { _, _ in syncNotificationPrefs() }
            .onChange(of: notifyDMs)      { _, _ in syncNotificationPrefs() }
            .onChange(of: notifyLives)    { _, _ in syncNotificationPrefs() }
        }
    }

    private func syncNotificationPrefs() {
        Task {
            await NotificationPreferencesService.upsert(
                likes: notifyLikes,
                comments: notifyComments,
                follows: notifyFollows,
                directMessages: notifyDMs,
                liveStreams: notifyLives
            )
        }
    }

    private func notifToggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .tint(Color.accentColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data

    private var dataSection: some View {
        settingsCard(
            title: "Data",
            subtitle: "Wipe cached images, videos, and feed data off this device."
        ) {
            Button {
                clearCaches()
            } label: {
                settingsRow(title: "Clear cache", systemImage: "sparkles", trailing: nil)
            }
            .buttonStyle(.plain)
        }
    }

    private func clearCaches() {
        URLCache.shared.removeAllCachedResponses()
        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: cachesDir.path)) ?? []
            for item in items {
                try? FileManager.default.removeItem(at: cachesDir.appendingPathComponent(item))
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsCard(
            title: "About",
            subtitle: nil
        ) {
            VStack(spacing: 8) {
                staticRow(title: "Version", value: appVersionLabel)
                linkRow(title: "Support", url: URL(string: "mailto:support@spilltop.com"))
                linkRow(title: "Terms of Service", url: URL(string: "https://spilltop.com/terms"))
                linkRow(title: "Privacy Policy", url: URL(string: "https://spilltop.com/privacy"))
                linkRow(title: "Community Guidelines", url: URL(string: "https://spilltop.com/guidelines"))
            }
        }
    }

    private func staticRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func linkRow(title: String, url: URL?) -> some View {
        Group {
            if let url {
                Link(destination: url) {
                    settingsRow(title: title, systemImage: nil, trailing: "arrow.up.right")
                }
            } else {
                settingsRow(title: title, systemImage: nil, trailing: nil)
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        settingsCard(
            title: "Account",
            subtitle: nil
        ) {
            VStack(spacing: 10) {
                Button {
                    isConfirmingSignOut = true
                } label: {
                    settingsRow(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right", trailing: nil)
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    HStack(spacing: 10) {
                        if isDeletingAccount {
                            ProgressView().tint(.red.opacity(0.95))
                        } else {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.95))
                        }
                        Text(isDeletingAccount ? "Deleting…" : "Delete account")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.95))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isDeletingAccount)
            }
        }
    }

    // MARK: - Helpers

    private func settingsRow(title: String, systemImage: String?, trailing: String?) -> some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 20)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            if let trailing {
                Image(systemName: trailing)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func loadPrivacyState() async {
        guard isPrivateFirstLoad else { return }
        isPrivateFirstLoad = false
        guard let userId = authState.session?.user.id.uuidString.lowercased() else { return }
        do {
            if let profile = try await ProfilePrivacyService.fetchIsPrivate(userId: userId) {
                isPrivateAccount = profile
            }
        } catch {
            // Non-fatal — default to off and let the user toggle if they want.
        }
    }

    private func togglePrivate(_ newValue: Bool) async {
        isPrivateLoading = true
        defer { isPrivateLoading = false }
        let previous = isPrivateAccount
        isPrivateAccount = newValue
        do {
            try await SafetyService.shared.setProfilePrivate(newValue)
        } catch {
            isPrivateAccount = previous
            errorMessage = error.localizedDescription
        }
    }

    private func performDelete() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await AccountService.shared.deleteMyAccount()
            // Server has already invalidated the session; this locally
            // clears our in-memory auth state and routes back to sign-in.
            await authState.signOut()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.58))
            }

            content()
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Tiny helper that reads the caller's `is_private` flag. Kept separate
/// from SafetyService because the reading direction (self) doesn't need
/// any of the blocking/reporting scaffolding.
enum ProfilePrivacyService {
    static func fetchIsPrivate(userId: String) async throws -> Bool? {
        struct Row: Decodable { let is_private: Bool? }
        let rows: [Row] = try await SupabaseManager.shared.client
            .from("profiles")
            .select("is_private")
            .eq("id", value: userId.lowercased())
            .limit(1)
            .execute()
            .value
        return rows.first?.is_private
    }
}

private struct AvatarImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .photoLibrary
        controller.allowsEditing = true
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .fullScreen
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImagePicked: (UIImage) -> Void
        private let onError: (String) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onError: @escaping (String) -> Void) {
            self.onImagePicked = onImagePicked
            self.onError = onError
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            picker.dismiss(animated: true)

            guard let image else {
                onError("Couldn't read that photo.")
                return
            }

            onImagePicked(image)
        }
    }
}

struct ProfilePostsRoute: Identifiable {
    let id = UUID()
    let videos: [FeedVideo]
    let initialVideoId: String
}

struct PostManagementMenu: View {
    let video: FeedVideo
    let onEdit: () -> Void
    let onTogglePin: () -> Void
    let onToggleArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button("Edit post", systemImage: "pencil") {
                onEdit()
            }

            Button(video.isPinned ? "Unpin post" : "Pin post", systemImage: video.isPinned ? "pin.slash" : "pin") {
                onTogglePin()
            }

            Button(
                video.isArchived ? "Unarchive post" : "Archive post",
                systemImage: video.isArchived ? "tray.and.arrow.up" : "archivebox"
            ) {
                onToggleArchive()
            }

            Button("Delete post", systemImage: "trash", role: .destructive) {
                onDelete()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ProfileGridCell: View {
    let video: FeedVideo
    var showsCreatorAvatar = false

    var body: some View {
        ZStack {
            ProfileGridThumbnail(video: video)

            if video.mediaKind == .video {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                            .padding(8)
                    }
                }
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        if showsCreatorAvatar {
                            gridAvatar
                        }

                        if let momentLabel = video.momentLabel {
                            badge(momentLabel.uppercased())
                        }

                        if video.isPinned {
                            badge("PINNED")
                        }

                        if video.isArchived {
                            badge("ARCHIVED")
                        }
                    }

                    Spacer()
                }
                Spacer()
            }
            .padding(8)
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(video.isArchived ? 0.58 : 1)
    }

    private var gridAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.45))
                .frame(width: 24, height: 24)

            if let avatarURL = video.creatorAvatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(video.creatorInitial)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .id(avatarURL.absoluteString)
                .frame(width: 24, height: 24)
                .clipShape(Circle())
            } else {
                Text(video.creatorInitial)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .overlay(
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
    }
}

struct ProfileGridThumbnail: View {
    let video: FeedVideo

    var body: some View {
        Group {
            if video.mediaKind == .image {
                ResilientFeedImageView(
                    primaryURL: video.optimizedThumbnailURL(width: 540, height: 960, quality: 70),
                    secondaryURL: video.optimizedPlaybackImageURL(width: 540, height: 960, quality: 78),
                    fallbackURL: video.playbackURL
                )
            } else if let thumbnailURL = video.optimizedThumbnailURL(width: 540, height: 960, quality: 70) {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Color.white.opacity(0.04)
                    }
                }
            } else if let playbackURL = video.playbackURL {
                RemoteVideoThumbnailView(url: playbackURL)
            } else {
                Color.white.opacity(0.04)
            }
        }
        .clipped()
    }
}

struct RemoteVideoThumbnailView: View {
    let url: URL

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.04)
                    Image(systemName: "film")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .task(id: url) {
            image = await Self.generateThumbnail(for: url)
        }
    }

    private static func generateThumbnail(for url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 500, height: 900)

            do {
                let image = try generator.copyCGImage(
                    at: CMTime(seconds: 0.1, preferredTimescale: 600),
                    actualTime: nil
                )
                return UIImage(cgImage: image)
            } catch {
                return nil
            }
        }.value
    }
}

struct ProfilePostsFeedView: View {
    @Environment(\.dismiss) private var dismiss

    let videos: [FeedVideo]
    let initialVideoId: String
    let showsPageLabel: Bool

    @StateObject private var pool = FeedPlayerPool()
    @State private var activeVideoId: String?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                if videos.isEmpty {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(videos) { video in
                                ProfilePostsFeedSlide(video: video, pool: pool)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .id(video.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $activeVideoId)
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea()
                    .onAppear {
                        resumePlayback()
                    }
                }

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        if let speedLabel = pool.activePlaybackSpeedLabel {
                            PlaybackSpeedBadge(text: speedLabel)
                        }

                        if showsPageLabel && !videos.isEmpty {
                            Text(pageLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.top, topSafeAreaInset + 14)
                .padding(.horizontal, 16)
            }
        }
        .ignoresSafeArea()
        .task {
            resumePlayback()
        }
        .simultaneousGesture(searchFeedDismissGesture)
        .onChange(of: activeVideoId) { _, newValue in
            guard let newValue else { return }
            syncPool(to: newValue)
        }
        .onDisappear {
            pool.tearDownAll()
        }
    }

    private func resumePlayback() {
        let targetId: String

        if let activeVideoId, videos.contains(where: { $0.id == activeVideoId }) {
            targetId = activeVideoId
        } else if videos.contains(where: { $0.id == initialVideoId }) {
            targetId = initialVideoId
        } else if let firstVideoId = videos.first?.id {
            targetId = firstVideoId
        } else {
            return
        }

        activeVideoId = targetId
        syncPool(to: targetId)
    }

    private func syncPool(to videoId: String) {
        guard let index = videos.firstIndex(where: { $0.id == videoId }) else { return }
        pool.syncActiveWindow(videos: videos, activeIndex: index)
    }

    private var pageLabel: String {
        let currentIndex = videos.firstIndex(where: { $0.id == activeVideoId }) ?? videos.firstIndex(where: { $0.id == initialVideoId }) ?? 0
        return "\(currentIndex + 1) / \(videos.count)"
    }

    private var topSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }

    private var searchFeedDismissGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                guard !showsPageLabel else { return }
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                guard horizontalDistance >= 88 else { return }
                guard abs(horizontalDistance) > abs(verticalDistance) * 1.2 else { return }
                dismiss()
            }
    }
}

struct ProfilePostsFeedSlide: View {
    let video: FeedVideo
    @ObservedObject var pool: FeedPlayerPool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
                .overlay { mediaLayer }
                .clipped()
                .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 320)
            .allowsHitTesting(false)
            .ignoresSafeArea()

            if video.mediaKind == .video {
                PlaybackGestureOverlay(
                    onTogglePlayback: { pool.togglePlayback(for: video.id) },
                    onBeginFastForwardHold: { pool.beginFastForwardHold(for: video.id) },
                    onEndFastForwardHold: { pool.endFastForwardHold(for: video.id) },
                    onToggleLockedFastForward: { pool.toggleLockedDoubleSpeed(for: video.id) }
                )

                if pool.isPaused(videoId: video.id) {
                    PlaybackPausedIndicator()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    creatorAvatar

                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.creatorHandle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)

                        Text(video.creatorName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                    }

                    if video.isPinned {
                        viewerBadge("Pinned")
                    }

                    if video.isArchived {
                        viewerBadge("Archived")
                    }
                }

                if let momentLabel = video.momentLabel {
                    viewerAccentBadge(
                        momentLabel,
                        tint: video.isOutNowMoment ? Color.orange : Color.purple.opacity(0.94)
                    )
                }

                Text(video.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                if video.isOutNowMoment, let venueName = video.venueName {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(Color.purple.opacity(0.94))

                        Text(venueName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))

                        if let venueShortLocation = video.venueShortLocation {
                            Text("• \(venueShortLocation)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }
                }

                if let caption = video.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.86))
                        .lineSpacing(2)
                }

                HStack(spacing: 18) {
                    viewerStat(systemName: "heart.fill", value: ProfileCountFormatter.string(for: video.likesCount))
                    viewerStat(systemName: "bubble.right.fill", value: ProfileCountFormatter.string(for: video.commentsCount))
                    viewerStat(systemName: "calendar", value: Self.formattedDate(from: video.createdAt))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 112)
        }
    }

    private var creatorAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 42, height: 42)

            if let avatarURL = video.creatorAvatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Text(video.creatorInitial)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .id(avatarURL.absoluteString)
                .frame(width: 42, height: 42)
                .clipShape(Circle())
            } else {
                Text(video.creatorInitial)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .overlay(
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var mediaLayer: some View {
        if video.mediaKind == .image {
            ResilientFeedImageView(
                primaryURL: video.optimizedPlaybackImageURL(width: 1440, quality: 84),
                fallbackURL: video.playbackURL,
                contentMode: .fit
            )
        } else if let avPlayer = pool.player(for: video.id) {
            PlayerLayerView(player: avPlayer)
        } else if let thumbnailURL = video.optimizedThumbnailURL(width: 1080, height: 1920, quality: 76) {
            AsyncImage(url: thumbnailURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.black
            }
        } else {
            Color.black
        }
    }

    private func viewerBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
    }

    private func viewerAccentBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.16))
            .clipShape(Capsule())
    }

    private func viewerStat(systemName: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.72))
    }

    private static func formattedDate(from value: String) -> String {
        if let date = ProfileDateFormatter.isoWithFractional.date(from: value) ?? ProfileDateFormatter.iso.date(from: value) {
            return ProfileDateFormatter.display.string(from: date)
        }
        return "Recently"
    }
}

struct ProfilePostViewer: View {
    let video: FeedVideo

    var body: some View {
        ProfilePostsFeedView(videos: [video], initialVideoId: video.id, showsPageLabel: true)
    }
}

enum ProfileDateFormatter {
    static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

enum ProfileCountFormatter {
    static func string(for count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
