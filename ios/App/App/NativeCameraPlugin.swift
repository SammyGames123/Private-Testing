import Capacitor
import Foundation

@objc(NativeCameraPlugin)
public class NativeCameraPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NativeCameraPlugin"
    public let jsName = "NativeCamera"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "readFile", returnType: CAPPluginReturnPromise),
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

    @objc func readFile(_ call: CAPPluginCall) {
        guard let path = call.getString("path") else {
            call.reject("Missing path parameter")
            return
        }

        // Accept both file:// URLs and raw paths
        var url: URL
        if path.hasPrefix("file://") {
            guard let parsed = URL(string: path) else {
                call.reject("Invalid file URL")
                return
            }
            url = parsed
        } else {
            url = URL(fileURLWithPath: path)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let base64 = data.base64EncodedString()
                let mimeType: String = {
                    let ext = url.pathExtension.lowercased()
                    switch ext {
                    case "mp4", "mov": return "video/mp4"
                    case "jpg", "jpeg": return "image/jpeg"
                    case "png": return "image/png"
                    case "heic": return "image/heic"
                    default: return "application/octet-stream"
                    }
                }()
                call.resolve([
                    "data": base64,
                    "mimeType": mimeType,
                    "size": data.count,
                ])
            } catch {
                call.reject("Failed to read file: \(error.localizedDescription)")
            }
        }
    }
}
