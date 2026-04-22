import SwiftUI

struct LeaderboardView: View {
    @State private var window: LeaderboardWindow = .last7Days
    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedCreatorRoute: LeaderboardCreatorRoute?
    @State private var currentUserId: String?

    private let service = LeaderboardService.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isLoading && entries.isEmpty {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else if let errorMessage, entries.isEmpty {
                    Spacer()
                    emptyMessage(
                        title: "Couldn't load leaderboard",
                        subtitle: errorMessage,
                        actionTitle: "Try again"
                    ) {
                        await load(forceRefresh: true)
                    }
                    Spacer()
                } else if entries.isEmpty {
                    Spacer()
                    emptyMessage(
                        title: "Nobody on the board yet",
                        subtitle: "Post a moment, check in, or go live to start earning points.",
                        actionTitle: nil,
                        action: nil
                    )
                    Spacer()
                } else {
                    leaderboardList
                }
            }
        }
        .task {
            currentUserId = await SupabaseManager.shared.currentUserId()
            // Always refresh on appear — the user may have just liked/commented/
            // posted/checked-in, and seeing their score tick up is the whole
            // point of the board. The 30s cache still covers rapid window
            // switching below.
            await load(forceRefresh: true)
        }
        .onChange(of: window) { _, _ in
            Task { await load(forceRefresh: false) }
        }
        .fullScreenCover(item: $selectedCreatorRoute) { route in
            CreatorProfileView(creatorId: route.creatorId)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Text("Top")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                PulseInboxLaunchButton()
            }

            Picker("Window", selection: $window) {
                ForEach(LeaderboardWindow.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - List

    private var leaderboardList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Pin the current user's row at the top if they're not in the
                // visible top-3 (so everyone always sees their own standing).
                if let currentUserId,
                   let myRank = service.rank(for: currentUserId, in: entries),
                   myRank > 3,
                   let mine = entries.first(where: { $0.userId.lowercased() == currentUserId.lowercased() }) {
                    LeaderboardRow(
                        rank: myRank,
                        entry: mine,
                        isCurrentUser: true
                    ) {
                        selectedCreatorRoute = LeaderboardCreatorRoute(creatorId: mine.userId)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let rank = index + 1
                    let isCurrentUser = entry.userId.lowercased() == currentUserId?.lowercased()
                    LeaderboardRow(
                        rank: rank,
                        entry: entry,
                        isCurrentUser: isCurrentUser
                    ) {
                        selectedCreatorRoute = LeaderboardCreatorRoute(creatorId: entry.userId)
                    }
                    .padding(.horizontal, 16)
                }

                // How points work footer
                pointsInfoFooter
                    .padding(.top, 24)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96) // space above the tab bar
            }
            .padding(.top, 4)
        }
        .refreshable {
            await load(forceRefresh: true)
        }
    }

    private var pointsInfoFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How points work")
                .font(.footnote.bold())
                .foregroundStyle(.white.opacity(0.75))

            pointRow("Post a moment", points: LeaderboardPoints.post)
            pointRow("Check in at a venue", points: LeaderboardPoints.checkIn)
            pointRow("Comment on your post", points: LeaderboardPoints.commentReceived)
            pointRow("Like on your post", points: LeaderboardPoints.likeReceived)
            pointRow("Heart on your live stream", points: LeaderboardPoints.reactionReceived)

            Text("Points last 7 days from when they're earned.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 4)
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func pointRow(_ label: String, points: Int) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text("+\(points)")
                .font(.footnote.monospacedDigit().bold())
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyMessage(
        title: String,
        subtitle: String,
        actionTitle: String?,
        action: (() async -> Void)?
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.4))

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let actionTitle, let action {
                Button {
                    Task { await action() }
                } label: {
                    Text(actionTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Loading

    private func load(forceRefresh: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await service.fetchLeaderboard(
                window: window,
                forceRefresh: forceRefresh
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                entries = fetched
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isCurrentUser: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                rankBadge

                AvatarView(
                    urlString: entry.avatarUrlString,
                    size: 44,
                    ringColor: rankRingColor
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.resolvedDisplayName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if isCurrentUser {
                            Text("You")
                                .font(.caption2.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                    }

                    if let handle = entry.resolvedHandle, handle != entry.resolvedDisplayName {
                        Text(handle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(entry.points)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("pts")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isCurrentUser ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isCurrentUser ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var rankBadge: some View {
        Group {
            if rank <= 3 {
                ZStack {
                    Circle()
                        .fill(rankRingColor)
                        .frame(width: 30, height: 30)
                    Image(systemName: rank == 1 ? "crown.fill" : "medal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                }
            } else {
                Text("\(rank)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .monospacedDigit()
            }
        }
    }

    private var rankRingColor: Color {
        switch rank {
        case 1: return Color(red: 1.00, green: 0.84, blue: 0.28)  // gold
        case 2: return Color(red: 0.80, green: 0.80, blue: 0.85)  // silver
        case 3: return Color(red: 0.85, green: 0.60, blue: 0.35)  // bronze
        default: return .clear
        }
    }
}

// MARK: - Avatar

private struct AvatarView: View {
    let urlString: String?
    let size: CGFloat
    let ringColor: Color

    var body: some View {
        ZStack {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                placeholder
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
        }
        .overlay(
            Circle()
                .stroke(ringColor == .clear ? Color.white.opacity(0.12) : ringColor, lineWidth: ringColor == .clear ? 1 : 2)
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.1)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.45))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

// MARK: - Route

private struct LeaderboardCreatorRoute: Identifiable {
    let id = UUID()
    let creatorId: String
}
