enum HapticFeedbackPolicy {
    static func isFeedbackEnabled(
        isPreferenceEnabled: Bool,
        isExpeditionModeActive: Bool
    ) -> Bool {
        isPreferenceEnabled && !isExpeditionModeActive
    }

    static func suppressionLogKey(
        event: HapticEvent,
        source: String?,
        isPreferenceEnabled: Bool,
        isExpeditionModeActive: Bool
    ) -> String {
        [
            event.rawValue,
            source ?? "unspecified",
            isPreferenceEnabled.description,
            isExpeditionModeActive.description
        ].joined(separator: "|")
    }

    static func coreProfile(for style: HapticImpactStyle) -> HapticCoreProfile {
        switch style {
        case .light:
            HapticCoreProfile(intensity: 0.35, sharpness: 0.45)
        case .medium:
            HapticCoreProfile(intensity: 0.68, sharpness: 0.58)
        case .heavy:
            HapticCoreProfile(intensity: 1.0, sharpness: 0.75)
        case .rigid:
            HapticCoreProfile(intensity: 0.88, sharpness: 1.0)
        }
    }

    static let selectionProfile = HapticCoreProfile(
        intensity: 0.35,
        sharpness: 0.55
    )

    static func resolvedIntensity(
        _ overrideIntensity: Double?,
        profile: HapticCoreProfile
    ) -> Float {
        guard let overrideIntensity else { return profile.intensity }
        return Float(min(max(overrideIntensity, 0), 1))
    }
}
