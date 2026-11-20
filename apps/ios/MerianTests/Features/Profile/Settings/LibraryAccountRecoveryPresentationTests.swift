@testable import Merian
import Testing

@Suite("Library account startup presentation")
@MainActor
struct LibraryAccountRecoveryPresentationTests {
    @Test func recoveryIsScopedToPrivateDestinations() {
        for destination: CaptureWorkspaceViewModel.ActiveSheet in [.scans, .profile, .insight, .reanalysis, .achievement] {
            #expect(destination.libraryAccessTitle != nil)
        }
        for destination: CaptureWorkspaceViewModel.ActiveSheet in [.explore, .paywall, .notificationPrompt, .whatsNew] {
            #expect(destination.libraryAccessTitle == nil)
        }
    }
    @Test func savedLibraryWaitsForInitialAuthEventWithoutShowingRecovery() {
        #expect(presentation(required: true, generation: 0) == .restoringSession)
        // A matching restored identity clears the existing ownership barrier.
        #expect(presentation(required: false, generation: 1) == .none)
    }

    @Test func missingOrForeignSessionStillRequiresRecoveryAfterInitialEvent() {
        #expect(presentation(required: true, generation: 1) == .recoveryRequired)
        #expect(presentation(required: true, generation: 2) == .recoveryRequired)
    }

    @Test func anonymousBootstrapKeepsRecoveryCoveredUntilItFinishes() {
        #expect(presentation(required: true, generation: 1, transition: .anonymousBootstrap) == .restoringSession)
        #expect(presentation(required: true, generation: 1) == .recoveryRequired)
        #expect(presentation(required: false, generation: 2) == .none)
    }

    @Test func providerSignInDoesNotHideConfirmedRecovery() {
        #expect(presentation(required: true, generation: 1, transition: .oauth(.apple)) == .recoveryRequired)
        #expect(presentation(required: true, generation: 1, transition: .oauth(.google)) == .recoveryRequired)
    }

    @Test func emptyLibraryNeedsNoStartupCover() {
        #expect(presentation(required: false, generation: 0) == .none)
    }

    @Test func expiredCachedSessionWaitsForRefreshInsteadOfFlashingRecovery() {
        #expect(presentation(required: true, generation: 1, awaitingRefresh: true) == .restoringSession)
        // Successful refresh releases ownership; terminal sign-out offers recovery.
        #expect(presentation(required: false, generation: 2) == .none)
        #expect(presentation(required: true, generation: 2) == .recoveryRequired)
        // Later runtime uncertainty must not hide an already confirmed recovery.
        #expect(presentation(required: true, generation: 2, awaitingRefresh: true) == .recoveryRequired)
    }

    private func presentation(
        required: Bool,
        generation: UInt64,
        awaitingRefresh: Bool = false,
        transition: AuthTransitionKind? = nil
    ) -> LibraryAccountRecoveryPresentation {
        .resolve(
            recoveryRequired: required,
            authSessionGeneration: generation,
            hasCachedSessionAwaitingRefresh: awaitingRefresh,
            activeTransitionKind: transition
        )
    }
}
