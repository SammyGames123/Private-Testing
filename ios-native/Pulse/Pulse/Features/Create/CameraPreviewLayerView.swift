import AVFoundation
import SwiftUI
import UIKit

/// Host view whose backing layer is an `AVCaptureVideoPreviewLayer`.
/// Lets us attach a capture session without manually managing layer
/// sizing.
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }
}

/// SwiftUI wrapper that binds an `AVCaptureSession` to an on-screen
/// preview layer. The session's lifecycle is managed by
/// `CameraController`; this view just displays frames.
struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}
