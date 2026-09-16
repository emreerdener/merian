import AuthenticationServices
import UIKit

/// Resolves the existing application window policy for interactive OAuth
/// providers without making the Auth facade own UIKit presentation details.
@MainActor
enum OAuthPresentationContextResolver {
    static func rootViewController() -> UIViewController? {
        guard let screen = UIApplication.shared.connectedScenes.first
            as? UIWindowScene else {
            return nil
        }
        return screen.windows.first(where: \.isKeyWindow)?
            .rootViewController
    }

    static func keyWindowAnchor() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes.compactMap {
            $0 as? UIWindowScene
        }
        if let keyWindow = scenes.flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let firstWindow = scenes.flatMap(\.windows).first {
            return firstWindow
        }
        if let windowScene = scenes.first {
            return ASPresentationAnchor(windowScene: windowScene)
        }

        MerianLog.auth.error(
            "No UIWindowScene available for authentication presentation."
        )
        return nil
    }
}
