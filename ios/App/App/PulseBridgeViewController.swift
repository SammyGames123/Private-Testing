import UIKit
import WebKit
import Capacitor

class PulseBridgeViewController: CAPBridgeViewController, WKUIDelegate {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(SSLBypassPlugin())
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView?.uiDelegate = self
    }

    // Auto-grant camera & mic permission requests from the WebView
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
