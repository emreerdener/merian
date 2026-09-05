import Combine
import Foundation

/// Loss-tolerant, strongly typed invalidations and lifecycle commands.
///
/// Events never carry authoritative domain state. Every consumer must recover
/// from SwiftData, UserDefaults, or its owning service when an event is missed.
/// Delivery-critical navigation belongs to `AppRouteCoordinator` instead.
enum AppEvent: Sendable {
    /// Dispatched when the app wakes up after being in the background for longer than the session timeout limit.
    /// Used to snap the UI back to a clean camera state.
    case appDidResumeAfterTimeout

    /// Dispatched after a current foreground inference durably completes with a biological result.
    case foregroundBiologicalScanCompleted(scanId: String)

    /// Dispatched after a scan review changes data that Explore renders through the scan join.
    case explorePostNeedsRefresh(postId: String)
    /// Dispatched after a local scan's Explore publication state changes.
    case exploreShareStateChanged(scanId: String, postId: String?)
    /// Dispatched after historical sync reconciles a batch of Explore publication state.
    case exploreShareStateReconciled
    /// Dispatched after Field trip progress changes. Consumers reload durable progress.
    case fieldTripProgressInvalidated(templateIds: Set<String>)
    /// Dispatched after seasonal challenge progress changes. Consumers reload durable progress.
    case fieldTripChallengeProgressInvalidated(challengeIds: Set<String>)
    /// Dispatched after a scan-specific progress mutation so an open Insight can
    /// refresh persistent contribution rows, including correction removals.
    case fieldTripScanContributionsInvalidated(scanId: String)
    /// Dispatched when a goal-producing feature changes eligibility or progress and
    /// Capture should refresh its source-agnostic goal context.
    case captureGoalContextInvalidated(source: CaptureGoalSourceKind)
    /// Dispatched after OAuth sign-in/linking or session restore refreshes the public Explore author identity.
    case publicAuthorIdentityChanged(previousUserId: String?, currentUserId: String)

    /// Dispatched after a scan mutation invalidates the in-memory search document.
    case scanSearchIndexInvalidated(scanId: String)
    /// Dispatched after the durable Scan Library changes.
    case scanLibraryChanged
    /// Dispatched after a Community identification request changes remotely.
    case communityIdentificationRequestChanged(requestId: String)
    /// Dispatched after the persisted Explore audio-boost preference changes.
    case exploreAudioBoostPreferenceChanged(postId: String, isEnabled: Bool)
    /// Dispatched after the persisted Explore video-mute preference resets.
    case exploreVideoMutePreferenceReset
    /// Dispatched after the durable manual Apple-revocation notice is recorded.
    case manualAppleRevocationNoticeRequired
    /// Dispatched after the identity-free account-deletion recovery marker
    /// changes. Consumers re-read the durable store; the event carries no ID.
    case accountDeletionRecoveryStateChanged
}

/// Producer-only capability. Domain services cannot subscribe through it.
@MainActor
protocol AppEventSending: AnyObject {
    func send(_ event: AppEvent)
}

/// Subscriber-only capability. Consumers cannot access the underlying subject.
@MainActor
protocol AppEventStreaming: AnyObject {
    var publisher: AnyPublisher<AppEvent, Never> { get }
}

/// A synchronous, `@MainActor`-isolated process-local invalidation bus.
/// The subject is deliberately private so callers cannot bypass actor isolation.
@MainActor
final class AppEventPublisher: AppEventSending, AppEventStreaming {
    private let subject: PassthroughSubject<AppEvent, Never>
    let publisher: AnyPublisher<AppEvent, Never>

    init() {
        let subject = PassthroughSubject<AppEvent, Never>()
        self.subject = subject
        publisher = subject.eraseToAnyPublisher()
    }

    func send(_ event: AppEvent) {
        subject.send(event)
    }
}
