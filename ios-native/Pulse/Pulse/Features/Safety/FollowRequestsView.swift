import SwiftUI

/// Incoming follow requests for the current user. Shown only when the
/// user has a private account (approved requests mean nothing for public
/// accounts — they just follow directly).
struct FollowRequestsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var requests: [FollowRequestEntry] = []
    @State private var isLoading = false
    @State private var busyIds: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading && requests.isEmpty {
                ProgressView().tint(.white)
            } else if requests.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("No follow requests")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("New requests show up here until you approve or decline.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(requests) { request in
                            row(request)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Follow requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .alert("Couldn't update", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ request: FollowRequestEntry) -> some View {
        HStack(spacing: 12) {
            avatar(for: request.requester)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.requester?.name ?? "Someone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let handle = request.requester?.username {
                    Text("@\(handle)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer()

            if busyIds.contains(request.id) {
                ProgressView().tint(.white)
            } else {
                HStack(spacing: 8) {
                    Button("Decline") {
                        Task { await reject(request) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())

                    Button("Approve") {
                        Task { await approve(request) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func avatar(for profile: UserProfile?) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 44, height: 44)
            if let urlString = profile?.avatarUrlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        initialPlaceholder(for: profile)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                initialPlaceholder(for: profile)
            }
        }
    }

    private func initialPlaceholder(for profile: UserProfile?) -> some View {
        Text(String((profile?.name ?? "U").prefix(1)).uppercased())
            .foregroundStyle(.white.opacity(0.8))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            requests = try await FollowRequestsService.shared.fetchIncomingRequests()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func approve(_ request: FollowRequestEntry) async {
        busyIds.insert(request.id)
        defer { busyIds.remove(request.id) }
        do {
            try await FollowRequestsService.shared.approve(requestId: request.id)
            requests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reject(_ request: FollowRequestEntry) async {
        busyIds.insert(request.id)
        defer { busyIds.remove(request.id) }
        do {
            try await FollowRequestsService.shared.reject(requestId: request.id)
            requests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
