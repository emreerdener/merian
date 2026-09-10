import Testing

@testable import Merian

@Suite("Haptic feedback policy")
struct HapticFeedbackPolicyTests {
    @Test("Preference and expedition gates compose without side effects")
    func feedbackEligibility() {
        #expect(
            HapticFeedbackPolicy.isFeedbackEnabled(
                isPreferenceEnabled: true,
                isExpeditionModeActive: false
            )
        )
        #expect(
            !HapticFeedbackPolicy.isFeedbackEnabled(
                isPreferenceEnabled: false,
                isExpeditionModeActive: false
            )
        )
        #expect(
            !HapticFeedbackPolicy.isFeedbackEnabled(
                isPreferenceEnabled: true,
                isExpeditionModeActive: true
            )
        )
    }

    @Test("Core profiles preserve the established UIKit style mapping")
    func coreProfiles() {
        #expect(
            HapticFeedbackPolicy.coreProfile(for: .light) ==
                HapticCoreProfile(intensity: 0.35, sharpness: 0.45)
        )
        #expect(
            HapticFeedbackPolicy.coreProfile(for: .medium) ==
                HapticCoreProfile(intensity: 0.68, sharpness: 0.58)
        )
        #expect(
            HapticFeedbackPolicy.coreProfile(for: .heavy) ==
                HapticCoreProfile(intensity: 1.0, sharpness: 0.75)
        )
        #expect(
            HapticFeedbackPolicy.coreProfile(for: .rigid) ==
                HapticCoreProfile(intensity: 0.88, sharpness: 1.0)
        )
    }

    @Test("Override intensity remains clamped to the supported range")
    func intensityClamping() {
        let profile = HapticCoreProfile(intensity: 0.68, sharpness: 0.58)

        #expect(
            HapticFeedbackPolicy.resolvedIntensity(nil, profile: profile) ==
                0.68
        )
        #expect(
            HapticFeedbackPolicy.resolvedIntensity(-1, profile: profile) == 0
        )
        #expect(
            HapticFeedbackPolicy.resolvedIntensity(0.42, profile: profile) ==
                Float(0.42)
        )
        #expect(
            HapticFeedbackPolicy.resolvedIntensity(2, profile: profile) == 1
        )
    }

    @Test("Suppression keys distinguish source and both eligibility gates")
    func suppressionKey() {
        #expect(
            HapticFeedbackPolicy.suppressionLogKey(
                event: .selectionPulse,
                source: nil,
                isPreferenceEnabled: false,
                isExpeditionModeActive: true
            ) == "selectionPulse|unspecified|false|true"
        )
        #expect(
            HapticFeedbackPolicy.suppressionLogKey(
                event: .selectionPulse,
                source: "capture.modeSelector",
                isPreferenceEnabled: false,
                isExpeditionModeActive: true
            ) == "selectionPulse|capture.modeSelector|false|true"
        )
    }
}
