import Foundation

struct HapticAttemptRecord: Equatable, Sendable {
    let event: String
    let source: String
    let outcome: HapticAttemptOutcome
    let timestamp: Date

    var displaySummary: String {
        "Last attempt: \(outcome.displayName) (\(event), \(source))"
    }
}

enum HapticAttemptOutcome: String, Equatable, Sendable {
    case suppressed
    case coreHapticsAndUIKit
    case uiKitFallback
    case uiKitNotification

    var displayName: String {
        switch self {
        case .suppressed:
            "suppressed"
        case .coreHapticsAndUIKit:
            "Core Haptics + UIKit"
        case .uiKitFallback:
            "UIKit fallback"
        case .uiKitNotification:
            "UIKit notification"
        }
    }
}

struct HapticDiagnosticSnapshot: Equatable, Sendable {
    let source: String
    let isHapticsEnabled: Bool
    let isExpeditionModeActive: Bool
    let supportsCoreHaptics: Bool
    let audioCategory: String
    let audioMode: String

    var displaySummary: String {
        [
            isHapticsEnabled
                ? "Naturebook haptics: on"
                : "Naturebook haptics: off",
            isExpeditionModeActive
                ? "Expedition mode: on"
                : "Expedition mode: off",
            supportsCoreHaptics
                ? "Core Haptics: supported"
                : "Core Haptics: unavailable",
            "Audio: \(audioCategory) / \(audioMode)"
        ].joined(separator: "\n")
    }
}

struct HapticAudioSessionSnapshot: Equatable, Sendable {
    let category: String
    let mode: String
}

enum HapticEvent: String, Equatable, Sendable {
    case focusSnap
    case sheetSpring
    case mediumPulse
    case errorImpact
    case errorNotification
    case selectionPulse
    case successNotification
    case lightImpact
    case heavyImpact
    case prepareHeavyImpact
}

enum HapticImpactStyle: Equatable, Sendable {
    case light
    case medium
    case heavy
    case rigid
}

enum HapticNotificationKind: Equatable, Sendable {
    case error
    case success
}

struct HapticCoreProfile: Equatable, Sendable {
    let intensity: Float
    let sharpness: Float
}
