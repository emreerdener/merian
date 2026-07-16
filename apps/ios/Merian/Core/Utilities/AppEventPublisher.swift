import Combine
import Foundation

enum RefinementEntryPoint: Sendable, Equatable {
    case standard
    case nonBiologicalCorrection
}

/// Strongly-typed system events replacing legacy `NotificationCenter` broadcasts.
enum AppEvent {
    /// Dispatched when the user exceeds their scan quota and the paywall must be presented.
    case triggerPaywall
    
    /// Dispatched via push notification tap to deep-link the user directly to a newly uploaded model.
    case appDidEnterActivePhaseWithScan(scanId: String)
    /// Dispatched via push notification tap to deep-link the user directly to an Explore post.
    case appDidEnterActivePhaseWithExplorePost(
        postId: String,
        targetCommentId: String?,
        targetReplyParentCommentId: String?
    )
    
    /// Dispatched when the app wakes up after being in the background for longer than the session timeout limit.
    /// Used to snap the UI back to a clean camera state.
    case appDidResumeAfterTimeout
    /// Dispatched by Siri/OS intents to immediately jump the user to the lens viewfinder.
    case requestIdentifyNatureIntent
    
    /// Dispatched by Siri/OS intents to immediately open the historical scans insight page.
    case requestRecallLastFindIntent
    
    /// Dispatched to seamlessly jump the user from an ambiguous Insight Sheet back to the Camera,
    /// carrying the scan ID forward into a supplementary multi-image generation sequence.
    case triggerRefinement(
        scanId: String,
        initialDescription: String? = nil,
        entryPoint: RefinementEntryPoint = .standard
    )

    /// Dispatched to open the scans sheet and push the non-biological collection.
    case requestOpenNonBiologicalScansIntent
    /// Dispatched from external integrations to open the main scan library sheet.
    case requestOpenScansLibraryIntent

    /// Dispatched after the app has durably copied an image received through document import.
    case externalImageImportAvailable(importId: UUID)
    /// Dispatched when an incoming file cannot be accepted into the document-import inbox.
    case externalImageImportFailed

    /// Dispatched after a scan review changes data that Explore renders through the scan join.
    case explorePostNeedsRefresh(postId: String)
    /// Dispatched after a local scan's Explore publication state changes.
    case exploreShareStateChanged(scanId: String, postId: String?)
    /// Dispatched after a community identification request should open in Explore.
    case openCommunityIdentificationRequest(requestId: String)
    /// Dispatched after a scan completes one or more Field Trip checklist items.
    case fieldTripProgressUpdated([FieldTripProgressUpdate])
    /// Dispatched after a scan completes one or more seasonal challenge items.
    case fieldTripChallengeProgressUpdated([FieldTripChallengeProgressUpdate])
    /// Dispatched after OAuth sign-in/linking or session restore refreshes the public Explore author identity.
    case publicAuthorIdentityChanged(previousUserId: String?, currentUserId: String)
}

/// A centralized, `@MainActor`-bound event bus for system-wide internal message routing.
/// Prevents memory leaks and ensures UI-modifying events are cleanly delivered to the main thread.
@MainActor
final class AppEventPublisher {
    static let shared = AppEventPublisher()
    
    let publisher = PassthroughSubject<AppEvent, Never>()
    
    private init() {}
    
    /// Publishes a strongly-typed event. Listeners should `.sink` onto `AppEventPublisher.shared.publisher`.
    func send(_ event: AppEvent) {
        publisher.send(event)
    }
}
