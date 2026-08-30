import SwiftUI

struct Community: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(ConsentManager.self) private var consentManager
    @State private var consentSaveErrorMessage = ""
    @State private var isShowingConsentSaveError = false

    @Binding var changelogActive: Bool
    @Binding var safariUrl: URL?
    @Binding var showSafari: Bool
    @Binding var showFeedbackSurvey: Bool

    private let dependencies = CommunitySettingsDependencies.live

    var body: some View {
        Section {
            SettingsToggleRow(
                title: "Analytics & diagnostics",
                description: "Optionally share pseudonymous app usage and diagnostics with PostHog. This account-wide choice never affects core functionality.",
                isOn: Binding(
                    get: { consentManager.hasGrantedCurrentPostHogAnalytics },
                    set: { isEnabled in
                        do {
                            try consentManager.setPostHogAnalyticsEnabled(
                                isEnabled
                            )
                        } catch {
                            consentSaveErrorMessage = isEnabled
                                ? "Analytics remains off because your choice could not be saved."
                                : "Analytics remains off, but the withdrawal still needs to finish saving."
                            isShowingConsentSaveError = true
                        }
                    }
                ),
                icon: "chart.bar.fill",
                iconColor: .teal
            )

            Button(action: dependencies.requestAppStoreReview) {
                Label("Rate Naturebook", systemImage: "star.fill")
            }

            Button {
                showFeedbackSurvey = true
            } label: {
                Label("Give us feedback", systemImage: "bubble.left.fill")
            }

            Button(action: dependencies.presentShareSheet) {
                Label("Share Naturebook", systemImage: "square.and.arrow.up")
            }

            Button {
                changelogActive = true
            } label: {
                Label("Changelog", systemImage: "clock.arrow.circlepath")
            }

            Button {
                openWebPage(path: "/guidelines")
            } label: {
                Label("Community guidelines", systemImage: "person.3.fill")
            }

            Button {
                openWebPage(path: "/legal")
            } label: {
                Label("Terms of service & Privacy Policy", systemImage: "doc.text.fill")
            }
        } header: {
            Text("Resources")
        }
        .alert(
            "Analytics setting not saved",
            isPresented: $isShowingConsentSaveError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(consentSaveErrorMessage)
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
