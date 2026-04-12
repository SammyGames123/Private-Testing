import UIKit
import WebKit
import AVFoundation
import Capacitor

class PulseBridgeViewController: CAPBridgeViewController {
    override func viewDidLoad() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        super.viewDidLoad()
    }

    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(SSLBypassPlugin())
    }

    // Capacitor's CAPBridgeViewController is already the WKUIDelegate.
    // Adding this method here lets the subclass handle it via dynamic dispatch.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }
}
