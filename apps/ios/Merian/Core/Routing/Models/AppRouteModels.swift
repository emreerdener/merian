import Foundation

enum RefinementEntryPoint: Sendable, Equatable {
    case standard
    case nonBiologicalCorrection
}

struct ExploreMediaRecoveryRouteContext: Sendable, Equatable {
    let ownerUserId: String
}

enum AppRoute: Sendable, Equatable {
    case proAccessRequired
    case scan(scanId: String)
    case explorePost(
        postId: String,
        targetCommentId: String?,
        targetReplyParentCommentId: String?
    )
    case speciesDictionary(speciesId: String)
    case communityIdentification(requestId: String)
    case identifyNature
    case openScanner
    case achievement(AwardPayload)
    case captureGoal(CaptureGoalDestination)
    case fieldTrips
    case recallLastFind
    case refinement(
        scanId: String,
        initialDescription: String?,
        entryPoint: RefinementEntryPoint
    )
    case nonBiologicalScans
    case scansLibrary
    case scansLibraryRecovery(ExploreMediaRecoveryRouteContext)
    case processExternalImageImports
    case externalImageImportFailed

    #if DEBUG
    case debugPreviewAnalyzing
    #endif
}

enum AppRouteSource: String, Sendable, Equatable {
    case durableExternalImport
    case deepLink
    case pushNotification
    case appIntent
    case internalUserAction
    case genericLaunch
    case debug
}

enum AppRoutePriority: Int, Sendable, Comparable {
    case debug = 50
    case genericLaunch = 100
    case internalUserAction = 200
    case explicitExternal = 300
    case durableExternalImport = 400

    static func < (lhs: AppRoutePriority, rhs: AppRoutePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AppRouteEnvelope: Identifiable, Sendable, Equatable {
    let id: UUID
    let route: AppRoute
    let source: AppRouteSource
    let createdAt: Date
    let priority: AppRoutePriority
    let expiresAt: Date?
    let accountGeneration: UInt64
    let sessionGeneration: UInt64

    /// Stable FIFO tie-breaker owned by the route coordinator.
    let insertionSequence: UInt64
}

enum AppRouteDeferralReason: Sendable, Equatable {
    case presentationOccupied
    case dependenciesUnavailable
}

enum AppRouteAccountSessionOrigin: Sendable, Equatable {
    /// The SDK is restoring the session that already owned durable launch intent.
    case initialRestoration
    /// A sign-in, sign-out, account deletion, or account replacement happened at runtime.
    case runtimeTransition
}

enum AppRouteRejectionReason: Sendable, Equatable {
    case coalesced(into: UUID)
    case expired
    case overflow
    case staleAccount
    case staleSession
    case targetUnavailable
    case invalidPayload
    case superseded
}

enum AppRouteOutcome: Sendable, Equatable {
    case applied(presentationID: UUID?)
    case deferred(reason: AppRouteDeferralReason)
    case dismissed(presentationID: UUID)
    case rejected(reason: AppRouteRejectionReason)
}

struct AppRouteOutcomeRecord: Identifiable, Sendable, Equatable {
    let id: UUID
    let requestID: UUID
    let outcome: AppRouteOutcome
    let recordedAt: Date
}
