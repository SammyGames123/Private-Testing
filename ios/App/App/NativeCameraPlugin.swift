import Capacitor
import Foundation

@objc(NativeCameraPlugin)
public class NativeCameraPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NativeCameraPlugin"
    public let jsName = "NativeCamera"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise)
    ]

    private var savedCall: CAPPluginCall?

    @objc func open(_ call: CAPPluginCall) {
        savedCall = call
        let mode = call.getString("mode") ?? "video"

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let vc = self.bridge?.viewController else {
                call.reject("No view controller available")
                return
            }
            let cameraVC = NativeCameraViewController()
            cameraVC.initialMode = mode == "photo" ? .photo : .video
            cameraVC.onCapture = { [weak self] fileURL, mediaType, duration in
                self?.savedCall?.resolve([
                    "filePath": fileURL.absoluteString,
                    "type": mediaType,
                    "duration": duration,
                ])
                self?.savedCall = nil
            }
            cameraVC.onCancel = { [weak self] in
                self?.savedCall?.reject("Camera cancelled")
                self?.savedCall = nil
            }
            cameraVC.modalPresentationStyle = .fullScreen
            vc.present(cameraVC, animated: true)
        }
    }
}
