import SwiftUI

struct FeedView: View {
    @StateObject private var model = FeedViewModel()
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
                                    isActive: activeVideoId == video.id
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
                        if activeVideoId == nil {
                            activeVideoId = model.videos.first?.id
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .task { await model.loadIfNeeded() }
        .refreshable { await model.load() }
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
