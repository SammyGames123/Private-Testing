import MapKit
import SwiftUI
import UIKit

struct MainTabView: View {
    @State private var selection: Tab = .feed
    @State private var isShowingInbox = false

    enum Tab: Hashable, CaseIterable {
        case feed
        case search
        case post
        case leaderboard
        case profile

        static func adjacent(to tab: Self, step: Int) -> Self? {
            guard let currentIndex = allCases.firstIndex(of: tab) else { return nil }
            let nextIndex = currentIndex + step
            guard allCases.indices.contains(nextIndex) else { return nil }
            return allCases[nextIndex]
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            FeedView()
                .tabItem { Label("Live", systemImage: "bolt.fill") }
                .tag(Tab.feed)

            SearchView()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(Tab.search)

            CreateView()
                .tabItem { Label("Post", systemImage: "plus.circle.fill") }
                .tag(Tab.post)

            LeaderboardView()
                .tabItem { Label("Top", systemImage: "crown.fill") }
                .tag(Tab.leaderboard)

            ProfileView {
                selection = .post
            }
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(Tab.profile)
        }
        .tint(.white)
        // Keep the tab bar + children put when the keyboard appears.
        // Without this, SwiftUI's default keyboard avoidance runs a layout
        // pass across the entire TabView subtree on every animation frame,
        // which causes app-wide lag. Sheets/inputs that need to move up
        // (comments, login, editors) are presented above this view and
        // still get their own keyboard avoidance.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay {
            TabSwipeGestureInstaller(selection: $selection)
                .allowsHitTesting(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseOpenCreate)) { notification in
            let targetTab: Tab

            if let route = notification.object as? PulseCreateRoute {
                switch route.normalizedMode {
                case .moment:
                    targetTab = .post
                case .checkIn:
                    // Check-in moved off its own tab; use the nightlife map.
                    targetTab = .search
                case .live:
                    targetTab = .post
                }
            } else {
                targetTab = .post
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                selection = targetTab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseExitCreate)) { _ in
            // Camera-first create flow has no intro/back screen; tapping the
            // X in the camera drops the user back on the feed.
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = .feed
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseOpenInbox)) { _ in
            isShowingInbox = true
        }
        .fullScreenCover(isPresented: $isShowingInbox) {
            InboxView(showsDismissButton: true)
        }
    }
}

struct PulseInboxLaunchButton: View {
    @ObservedObject private var badgeStore = InboxBadgeStore.shared

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .pulseOpenInbox, object: nil)
        } label: {
            Image(systemName: "envelope.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if badgeStore.unreadCount > 0 {
                        Text(badgeStore.unreadLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, badgeStore.unreadCount > 9 ? 6 : 5)
                            .padding(.vertical, 3)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open inbox")
        .task {
            await badgeStore.refreshIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseInboxDidUpdate)) { _ in
            Task {
                await badgeStore.refresh(force: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await badgeStore.refresh(force: true)
            }
        }
    }
}

@MainActor
final class InboxBadgeStore: ObservableObject {
    static let shared = InboxBadgeStore()

    @Published private(set) var unreadCount = 0

    private let service = FeedService.shared
    private let defaults = UserDefaults.standard
    private var lastRefreshAt: Date?

    private init() {}

    var unreadLabel: String {
        unreadCount > 9 ? "9+" : "\(unreadCount)"
    }

    func refreshIfNeeded() async {
        guard shouldRefresh else { return }
        await refresh(force: false)
    }

    func refresh(force: Bool) async {
        if !force, !shouldRefresh {
            return
        }

        guard let currentUserId = await SupabaseManager.shared.currentUserId() else {
            unreadCount = 0
            lastRefreshAt = Date()
            return
        }

        do {
            let threads = try await service.fetchInboxThreads(userId: currentUserId)
            let lastOpenedAt = inboxLastOpenedDate(for: currentUserId)
            unreadCount = threads.filter { thread in
                guard thread.latestMessageSenderId != nil else { return false }
                guard thread.latestMessageSenderId != currentUserId.lowercased() else { return false }
                guard let lastOpenedAt else { return true }
                return parseISODate(thread.latestMessageAt) > lastOpenedAt
            }.count
            lastRefreshAt = Date()
        } catch {
            lastRefreshAt = Date()
        }
    }

    func markInboxOpened() async {
        guard let currentUserId = await SupabaseManager.shared.currentUserId() else {
            unreadCount = 0
            return
        }

        defaults.set(Date().timeIntervalSince1970, forKey: inboxLastOpenedKey(for: currentUserId))
        unreadCount = 0
        lastRefreshAt = Date()
    }

    private var shouldRefresh: Bool {
        guard let lastRefreshAt else { return true }
        return Date().timeIntervalSince(lastRefreshAt) > 12
    }

    private func inboxLastOpenedDate(for userId: String) -> Date? {
        let value = defaults.double(forKey: inboxLastOpenedKey(for: userId))
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private func inboxLastOpenedKey(for userId: String) -> String {
        "spilltop.inboxLastOpened.\(userId.lowercased())"
    }

    private func parseISODate(_ value: String) -> Date {
        if let date = ProfileDateFormatter.isoWithFractional.date(from: value) {
            return date
        }
        if let date = ProfileDateFormatter.iso.date(from: value) {
            return date
        }
        return .distantPast
    }
}

/// Shared gate screens can flip to opt out of the global tab-swipe
/// gesture. Reference-counted so nested opt-outs (e.g. a modal within
/// a page that also disables) don't step on each other.
///
/// Use via `.pulseDisablesTabSwipe()` on the view that should block it.
enum PulseTabSwipeGate {
    private static var disableCount = 0

    static var isDisabled: Bool { disableCount > 0 }

    static func disable() {
        disableCount += 1
    }

    static func enable() {
        disableCount = max(0, disableCount - 1)
    }
}

extension View {
    /// Blocks the global tab-swipe gesture while this view is on screen.
    /// Safe to stack: multiple disabling views cancel correctly via
    /// refcounting.
    func pulseDisablesTabSwipe() -> some View {
        modifier(PulseDisablesTabSwipeModifier())
    }
}

private struct PulseDisablesTabSwipeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { PulseTabSwipeGate.disable() }
            .onDisappear { PulseTabSwipeGate.enable() }
    }
}

private struct TabSwipeGestureInstaller: UIViewRepresentable {
    @Binding var selection: MainTabView.Tab

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        installGestureIfNeeded(coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.selection = $selection
        installGestureIfNeeded(coordinator: context.coordinator)
    }

    private func installGestureIfNeeded(coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
                return
            }
            guard let window = windowScene.windows.first(where: \.isKeyWindow) else { return }
            coordinator.installIfNeeded(on: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var selection: Binding<MainTabView.Tab>

        private weak var hostView: UIView?
        private weak var panGesture: UIPanGestureRecognizer?

        init(selection: Binding<MainTabView.Tab>) {
            self.selection = selection
        }

        func installIfNeeded(on hostView: UIView) {
            guard self.hostView !== hostView else { return }

            if let panGesture, let previousHostView = self.hostView {
                previousHostView.removeGestureRecognizer(panGesture)
            }

            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            panGesture.cancelsTouchesInView = false
            panGesture.delaysTouchesBegan = false
            panGesture.delaysTouchesEnded = false
            panGesture.maximumNumberOfTouches = 1
            panGesture.delegate = self
            hostView.addGestureRecognizer(panGesture)

            self.hostView = hostView
            self.panGesture = panGesture
        }

        @objc
        private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended, let hostView else { return }

            let translation = gesture.translation(in: hostView)
            let horizontalDistance = translation.x
            let verticalDistance = translation.y

            let velocity = gesture.velocity(in: hostView)
            guard abs(horizontalDistance) >= 56 || abs(velocity.x) >= 700 else { return }
            guard abs(horizontalDistance) > abs(verticalDistance) * 1.15 || abs(velocity.x) > abs(velocity.y) * 1.15 else { return }

            let step = horizontalDistance < 0 ? 1 : -1
            guard let nextTab = MainTabView.Tab.adjacent(to: selection.wrappedValue, step: step) else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                selection.wrappedValue = nextTab
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if PulseTabSwipeGate.isDisabled {
                return false
            }
            if UIApplication.shared.hasPresentedOverlayController {
                return false
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !touchedView.blocksTabSwipeGesture
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    var blocksTabSwipeGesture: Bool {
        sequence(first: self, next: \.superview).contains {
            $0 is UITextField || $0 is UITextView || $0 is MKMapView
        }
    }
}

private extension UIApplication {
    var hasPresentedOverlayController: Bool {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .topPresentedController
            .presentingViewController != nil
    }
}

private extension UIViewController {
    var topPresentedController: UIViewController {
        presentedViewController?.topPresentedController ?? self
    }
}
