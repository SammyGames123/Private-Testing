import UIKit
import AVFoundation
import Capacitor

class PulseBridgeViewController: CAPBridgeViewController {
    override func viewDidLoad() {
        // Pre-request camera & mic so iOS prompts before webview needs them
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        super.viewDidLoad()
    }

    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(SSLBypassPlugin())
    }
}
