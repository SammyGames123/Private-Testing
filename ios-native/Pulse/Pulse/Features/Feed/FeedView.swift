import SwiftUI

/// Placeholder. The real TikTok-style vertical feed will land in the
/// next session, backed by AVPlayer for instant playback.
struct FeedView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Feed")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text("Vertical AVPlayer feed lands next session.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}
