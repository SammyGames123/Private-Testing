import MapKit
import SwiftUI
import UIKit

/// Decides which top-level screen to show based on auth state.
struct RootView: View {
    @EnvironmentObject private var authState: AuthState

    var body: some View {
        Group {
            if authState.isLoading {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            } else if authState.session != nil {
                MainTabView()
            } else {
                LoginView()
            }
        }
        // Tap-outside-keyboard dismissal applied at the root so every screen
        // inherits it. The modifier's gesture delegate already ignores taps
        // landing inside UITextField/UITextView/MKMapView, so it won't eat
        // legitimate input taps.
        .dismissKeyboardOnTap()
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(KeyboardDismissOnTapModifier())
    }
}

private struct KeyboardDismissOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(KeyboardDismissTapInstaller())
    }
}

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        installGestureIfNeeded(from: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        installGestureIfNeeded(from: uiView, coordinator: context.coordinator)
    }

    private func installGestureIfNeeded(from view: UIView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let hostView = view.superview else { return }
            coordinator.installIfNeeded(on: hostView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var hostView: UIView?
        private weak var tapGesture: UITapGestureRecognizer?

        func installIfNeeded(on hostView: UIView) {
            guard self.hostView !== hostView else { return }

            if let tapGesture, let previousHostView = self.hostView {
                previousHostView.removeGestureRecognizer(tapGesture)
            }

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tapGesture.cancelsTouchesInView = false
            tapGesture.delegate = self
            hostView.addGestureRecognizer(tapGesture)

            self.hostView = hostView
            self.tapGesture = tapGesture
        }

        @objc
        private func handleTap() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !touchedView.blocksKeyboardDismissTap
        }
    }
}

private extension UIView {
    var blocksKeyboardDismissTap: Bool {
        sequence(first: self, next: \.superview).contains {
            $0 is UITextField || $0 is UITextView || $0 is MKMapView
        }
    }
}
