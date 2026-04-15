import SwiftUI

struct FeedView: View {
    @StateObject private var model = FeedViewModel()
    @StateObject private var pool = FeedPlayerPool()
    @State private var activeVideoId: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if model.videos.isEmpty {
                    placeholder
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(model.videos) { video in
                                FeedVideoCell(
                                    video: video,
                                    pool: pool,
                                    model: model
                                )
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
                        if activeVideoId == nil, let first = model.videos.first {
                            activeVideoId = first.id
                            syncPool(to: first.id)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .task {
            await model.loadIfNeeded()
            if activeVideoId == nil, let first = model.videos.first {
                activeVideoId = first.id
                syncPool(to: first.id)
            }
        }
        .refreshable {
            await model.load()
            if let first = model.videos.first {
                activeVideoId = first.id
                syncPool(to: first.id)
            }
        }
        .onChange(of: activeVideoId) { _, newValue in
            guard let newValue else { return }
            syncPool(to: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseDidCreatePost)) { _ in
            Task {
                await model.load()
                if let first = model.videos.first {
                    activeVideoId = first.id
                    syncPool(to: first.id)
                }
            }
        }
        .onDisappear {
            pool.tearDownAll()
        }
    }

    private func syncPool(to videoId: String) {
        guard let idx = model.videos.firstIndex(where: { $0.id == videoId }) else { return }
        pool.syncActiveWindow(videos: model.videos, activeIndex: idx)
    }

    @ViewBuilder
    private var placeholder: some View {
        if model.isLoading {
            ProgressView()
                .tint(.white)
        } else if let error = model.errorMessage {
            VStack(spacing: 12) {
                Text("Couldn't load feed")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await model.load() }
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(32)
        } else {
            Text("No public videos yet")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
