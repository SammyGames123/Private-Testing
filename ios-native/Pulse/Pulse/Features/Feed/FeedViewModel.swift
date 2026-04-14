import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var videos: [FeedVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func loadIfNeeded() async {
        guard videos.isEmpty, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            videos = try await FeedService.shared.fetchFeed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
