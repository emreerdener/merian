import StoreKit
import SwiftUI

struct Community: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(ConsentManager.self) private var consentManager

    @Binding var changelogActive: Bool
    @Binding var safariUrl: URL?
    @Binding var showSafari: Bool
    @Binding var showFeedbackSurvey: Bool
    
    var body: some View {
        Section {
            SettingsToggleRow(
                title: "Analytics & diagnostics",
                description: "Optionally share pseudonymous app usage and diagnostics with PostHog. This account-wide choice never affects core functionality.",
                isOn: Binding(
                    get: { consentManager.hasGrantedCurrentPostHogAnalytics },
                    set: { consentManager.setPostHogAnalyticsEnabled($0) }
                ),
                icon: "chart.bar.fill",
                iconColor: .teal
            )

            Button("Rate Naturebook") {
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    SKStoreReviewController.requestReview(in: scene)
                }
            }
            Button("Give us feedback") {
                showFeedbackSurvey = true
            }
            Button("Invite a friend") {
                ReferralShareContent.presentShareSheet()
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
    static let supportEmail = URL(string: "mailto:\(PublicBrand.supportEmail)")

    static func url(path: String, themeMode: ThemeMode) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = PublicBrand.websiteURL.host
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
