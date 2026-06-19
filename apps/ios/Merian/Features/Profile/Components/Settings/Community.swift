import StoreKit
import SwiftUI

struct Community: View {
    @Environment(AppSettings.self) private var appSettings

    @Binding var changelogActive: Bool
    @Binding var safariUrl: URL?
    @Binding var showSafari: Bool
    @Binding var showFeedbackSurvey: Bool
    
    var body: some View {
        Section {
            Button("Rate merian") {
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    SKStoreReviewController.requestReview(in: scene)
                }
            }
            Button("Suggest a feature / Report a bug") {
                if let url = MerianWebURL.supportEmail {
                    UIApplication.shared.open(url)
                }
            }
            Button("Give us feedback") {
                showFeedbackSurvey = true
            }
            Button("Changelog") {
                changelogActive = true
            }
            Button("Community guidelines") {
                openWebPage(path: "/guidelines")
            }
            Button("Terms of service & Privacy Policy") {
                openWebPage(path: "/legal")
            }
        } header: {
            Text("Resources")
        }
    }

    private func openWebPage(path: String) {
        guard let url = MerianWebURL.url(path: path, themeMode: appSettings.themeMode) else { return }

        safariUrl = url
        showSafari = true
    }
}

private enum MerianWebURL {
    static let supportEmail = URL(string: "mailto:support@merian.earth")

    static func url(path: String, themeMode: ThemeMode) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "merian.earth"
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.queryItems = [
            URLQueryItem(name: "theme", value: themeMode.webThemePreferenceValue)
        ]

        return components.url
    }
}

private extension ThemeMode {
    var webThemePreferenceValue: String {
        switch self {
        case .system:
            return "system"
        case .light:
            return "light"
        case .dark:
            return "dark"
        }
    }
}
