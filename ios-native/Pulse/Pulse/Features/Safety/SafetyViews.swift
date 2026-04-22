import SwiftUI

// MARK: - Report sheet

/// Category picker + optional note. Used for reporting users, videos,
/// comments, and live streams — driven entirely by `ReportTarget`.
struct ReportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: ReportTarget
    let subjectLabel: String

    @State private var category: ReportCategory = .spam
    @State private var note: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Reason")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .tracking(0.5)

                            ForEach(ReportCategory.allCases) { option in
                                categoryRow(option)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Extra detail (optional)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .tracking(0.5)

                            TextField(
                                "Anything else our team should know",
                                text: $note,
                                axis: .vertical
                            )
                            .lineLimit(3...6)
                            .foregroundStyle(.white)
                            .tint(.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.1))
                            )
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                }
            }
            .safeAreaInset(edge: .bottom) { submitBar }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .alert("Thanks for the report", isPresented: $didSubmit) {
                Button("OK") { dismiss() }
            } message: {
                Text("We'll review and take action when appropriate. You can also block this account from their profile.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reporting \(subjectLabel)")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Reports are sent to our safety team. Pick what fits best — free-form notes help us act faster on edge cases.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func categoryRow(_ option: ReportCategory) -> some View {
        Button {
            category = option
        } label: {
            HStack {
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: category == option ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(category == option ? Color.accentColor : .white.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(category == option ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        category == option ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))

            Button(action: submit) {
                ZStack {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Submit report")
                            .font(.body.bold())
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.43, green: 0.28, blue: 1.0),
                            Color(red: 0.08, green: 0.48, blue: 0.95),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.94))
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                try await SafetyService.shared.report(
                    target: target,
                    category: category,
                    note: note
                )
                didSubmit = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Blocked users list

struct BlockedUsersView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var safety = SafetyService.shared

    @State private var profiles: [UserProfile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading && profiles.isEmpty {
                ProgressView().tint(.white)
            } else if profiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("You haven't blocked anyone")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Block from anyone's profile if you ever need to.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(profiles) { profile in
                            blockedRow(profile)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Blocked")
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

    private func blockedRow(_ profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                if let urlString = profile.avatarUrlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Text(String((profile.displayName ?? profile.username ?? "U").prefix(1)).uppercased())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName ?? profile.username ?? "User")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let handle = profile.username {
                    Text("@\(handle)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("Unblock") {
                Task { await unblock(profile) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profiles = try await safety.fetchBlockedProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unblock(_ profile: UserProfile) async {
        do {
            try await safety.unblock(userId: profile.id)
            profiles.removeAll { $0.id.lowercased() == profile.id.lowercased() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
