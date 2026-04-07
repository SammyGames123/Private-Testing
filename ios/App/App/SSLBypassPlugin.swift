import Capacitor
import Foundation

/// Allows WKWebView to accept self-signed certificates during development.
/// This enables HTTPS dev server with getUserMedia camera access.
@objc(SSLBypassPlugin)
public class SSLBypassPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SSLBypassPlugin"
    public let jsName = "SSLBypass"
    public let pluginMethods: [CAPPluginMethod] = []

    @objc override public func handleWKWebViewURLAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return true
            }
        }
        return false
    }
}
