import UIKit
import Capacitor

class PulseBridgeViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(SSLBypassPlugin())
        bridge?.registerPluginInstance(NativeCameraPlugin())
    }
}
