import UIKit
import AuthenticationServices

/// Provides a presentation anchor for ASWebAuthenticationSession (used by
/// Supabase OAuth flows like Google sign-in).
final class WebAuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthAnchor()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Find the key window on the active foreground scene.
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        if let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return window
        }
        if let window = scenes.flatMap({ $0.windows }).first {
            return window
        }
        return ASPresentationAnchor()
    }
}
