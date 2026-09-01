@testable import Merian
import Foundation
import Testing

private enum OnboardingDependencyTestError: Error {
    case persistenceFailed
}

@Suite("Onboarding dependency orchestration")
@MainActor
struct OnboardingDependencyTests {
    @Test func completionPreservesDurableConsentBeforeLifecycleGate() throws {
        var isCompleted = false
        var events: [String] = []
        let accountID = UUID()
        let viewModel = OnboardingViewModel(
            dependencies: OnboardingDependencies(
                hasCompletedOnboarding: { isCompleted },
                setHasCompletedOnboarding: { value in
                    events.append("gate")
                    isCompleted = value
                },
                recordCurrentConsent: { analyticsEnabled in
                    #expect(analyticsEnabled)
                    events.append("consent")
                },
                currentSessionUserID: { accountID },
                trackCompletion: {
                    events.append("telemetry")
                },
                resumeConsentBlockedScan: { receivedAccountID in
                    #expect(receivedAccountID == accountID)
                    #expect(isCompleted)
                    events.append("resume")
                }
            )
        )

        try viewModel.completeOnboarding(analyticsEnabled: true)

        #expect(isCompleted)
        #expect(events == ["consent", "telemetry", "gate", "resume"])
    }

    @Test func failedConsentWriteLeavesEveryDownstreamEffectClosed() {
        var isCompleted = false
        var downstreamEffects = 0
        let viewModel = OnboardingViewModel(
            dependencies: OnboardingDependencies(
                hasCompletedOnboarding: { isCompleted },
                setHasCompletedOnboarding: { isCompleted = $0 },
                recordCurrentConsent: { _ in
                    throw OnboardingDependencyTestError.persistenceFailed
                },
                currentSessionUserID: { UUID() },
                trackCompletion: { downstreamEffects += 1 },
                resumeConsentBlockedScan: { _ in downstreamEffects += 1 }
            )
        )

        #expect(throws: OnboardingDependencyTestError.self) {
            try viewModel.completeOnboarding(analyticsEnabled: false)
        }
        #expect(!isCompleted)
        #expect(downstreamEffects == 0)
    }

    @Test func completionWithoutAccountDoesNotAttemptRecovery() throws {
        var resumeAttempts = 0
        let viewModel = OnboardingViewModel(
            dependencies: OnboardingDependencies(
                recordCurrentConsent: { _ in },
                currentSessionUserID: { nil },
                resumeConsentBlockedScan: { _ in resumeAttempts += 1 }
            )
        )

        try viewModel.completeOnboarding(analyticsEnabled: false)

        #expect(resumeAttempts == 0)
    }

    @Test func expectedStepFenceRejectsDuplicateAndLateCompletions() {
        let viewModel = OnboardingViewModel(
            dependencies: OnboardingDependencies()
        )

        viewModel.advanceStep(from: .welcome)
        viewModel.advanceStep(from: .welcome)
        #expect(viewModel.currentStep == .camera)

        viewModel.advanceStep(from: .location)
        #expect(viewModel.currentStep == .camera)

        viewModel.advanceStep(from: .camera)
        #expect(viewModel.currentStep == .location)
    }
}
