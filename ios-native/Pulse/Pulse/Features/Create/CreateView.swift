import SwiftUI

/// Two-step create flow:
/// 1. `.camera` — live capture + library picker
/// 2. `.details(CapturedMedia)` — preview + caption + post
struct CreateView: View {
    private enum Step: Equatable {
        case camera
        case details(CapturedMedia)
    }

    @State private var step: Step = .camera

    var body: some View {
        NavigationStack {
            content
                .toolbar(step == .camera ? .hidden : .visible, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .camera:
            CameraCaptureView(
                onCancel: resetToCamera,
                onCapture: { media in
                    step = .details(media)
                }
            )
        case .details(let media):
            PostDetailsView(
                media: media,
                onBack: {
                    media.cleanup()
                    resetToCamera()
                },
                onPosted: resetToCamera
            )
        }
    }

    private func resetToCamera() {
        step = .camera
    }
}
