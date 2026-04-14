import SwiftUI

struct MainTabView: View {
    @State private var selection: Tab = .feed

    enum Tab: Hashable {
        case feed
        case search
        case create
        case inbox
        case profile
    }

    var body: some View {
        TabView(selection: $selection) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "house.fill") }
                .tag(Tab.feed)

            placeholder("Search", icon: "magnifyingglass")
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            placeholder("Create", icon: "plus.square.fill")
                .tabItem { Label("Create", systemImage: "plus.square.fill") }
                .tag(Tab.create)

            placeholder("Inbox", icon: "envelope.fill")
                .tabItem { Label("Inbox", systemImage: "envelope.fill") }
                .tag(Tab.inbox)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(Tab.profile)
        }
        .tint(.white)
    }

    @ViewBuilder
    private func placeholder(_ title: String, icon: String) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.6))
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Coming soon.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
