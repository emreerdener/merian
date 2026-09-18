import Foundation
import SwiftUI

enum AppLaunchPresentationPolicy {
    static func shouldOpenExplore(
        hasCompletedOnboarding: Bool,
        opensExploreOnLaunch: Bool
    ) -> Bool {
        hasCompletedOnboarding && opensExploreOnLaunch
    }
}

enum AppRootPresentation: Equatable {
    case onboarding
    case restoringConsent
    case workspace
}

enum AppRootPresentationPolicy {
    static func presentation(
        hasCompletedOnboarding: Bool,
        hasCurrentRequiredConsent: Bool,
        isRestoringRequiredConsent: Bool
    ) -> AppRootPresentation {
        guard hasCompletedOnboarding else { return .onboarding }
        if hasCurrentRequiredConsent { return .workspace }
        if isRestoringRequiredConsent { return .restoringConsent }
        return .onboarding
    }
}

enum StartupRecoveryNoticePolicy {
    static func combined(
        storeNotice: StartupRecoveryNotice?,
        configurationIssues: [MerianEnvironment.ConfigurationIssue] =
            MerianEnvironment.configurationIssues
    ) -> StartupRecoveryNotice? {
        guard !configurationIssues.isEmpty else { return storeNotice }

        let configurationMessage = "Configuration warnings: " +
            configurationIssues.map(\.description).joined(separator: " ")
        guard let storeNotice else {
            return StartupRecoveryNotice(
                title: "Configuration Warning",
                message: configurationMessage
            )
        }

        return StartupRecoveryNotice(
            title: storeNotice.title,
            message: "\(storeNotice.message)\n\n\(configurationMessage)",
            diagnosticText: storeNotice.diagnosticText
        )
    }
}

private struct StartupStoreStateKey: EnvironmentKey {
    static let defaultValue: StartupStoreState = .normal
}

private struct SignOutCompletionFeedbackKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

private struct StartupRecoveryNoticeKey: EnvironmentKey {
    static let defaultValue: StartupRecoveryNotice? = nil
}

extension EnvironmentValues {
    var showSignOutConfirmation: @MainActor @Sendable () -> Void {
        get { self[SignOutCompletionFeedbackKey.self] }
        set { self[SignOutCompletionFeedbackKey.self] = newValue }
    }

    var startupRecoveryNotice: StartupRecoveryNotice? {
        get { self[StartupRecoveryNoticeKey.self] }
        set { self[StartupRecoveryNoticeKey.self] = newValue }
    }

    var startupStoreState: StartupStoreState {
        get { self[StartupStoreStateKey.self] }
        set { self[StartupStoreStateKey.self] = newValue }
    }
}

struct StartupRecoveryNoticeView: View {
    let notice: StartupRecoveryNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(notice.title)
                .font(.subheadline.weight(.semibold))
            Text(notice.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let diagnosticText = notice.diagnosticText,
               Self.shouldShowDiagnostics {
                ShareLink(item: diagnosticText) {
                    Label(
                        "Share Diagnostics",
                        systemImage: "square.and.arrow.up"
                    )
                    .font(.footnote.weight(.semibold))
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .allowsHitTesting(hasInteractiveContent)
    }

    private var hasInteractiveContent: Bool {
        notice.diagnosticText != nil && Self.shouldShowDiagnostics
    }

    private static var shouldShowDiagnostics: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent ==
            "sandboxReceipt"
        #endif
    }
}

/// Applied outside the root presentation tree so sheets and navigation routes
/// inherit the same top-edge treatment. Individual control glass and bottom
/// scroll-edge effects keep their native appearance.
struct AppTopScrollEdgeEffectModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
