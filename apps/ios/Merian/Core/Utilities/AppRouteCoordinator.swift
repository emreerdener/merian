import Foundation
import Observation

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
    case explorePost(postId: String, targetCommentId: String?, targetReplyParentCommentId: String?)
    case speciesDictionary(speciesId: String)
    case communityIdentification(requestId: String)
    case identifyNature
    case openScanner
    case achievement(AwardPayload)
    case captureGoal(CaptureGoalDestination)
    case fieldTrips
    case recallLastFind
    case refinement(scanId: String, initialDescription: String?, entryPoint: RefinementEntryPoint)
    case nonBiologicalScans
    case scansLibrary
    case scansLibraryRecovery(ExploreMediaRecoveryRouteContext)
    case processExternalImageImports
    case externalImageImportFailed

    #if DEBUG
    case debugPreviewAnalyzing
    #endif

    fileprivate func coalesces(with other: AppRoute) -> Bool {
        switch (self, other) {
        case (.proAccessRequired, .proAccessRequired),
             (.fieldTrips, .fieldTrips),
             (.recallLastFind, .recallLastFind),
             (.nonBiologicalScans, .nonBiologicalScans),
             (.scansLibrary, .scansLibrary),
             (.processExternalImageImports, .processExternalImageImports),
             (.externalImageImportFailed, .externalImageImportFailed):
            return true
        case let (.scan(lhs), .scan(rhs)),
             let (.speciesDictionary(lhs), .speciesDictionary(rhs)),
             let (.communityIdentification(lhs), .communityIdentification(rhs)):
            return Self.normalizedIdentifier(lhs) == Self.normalizedIdentifier(rhs)
        case let (
            .explorePost(lhsPost, lhsComment, lhsReply),
            .explorePost(rhsPost, rhsComment, rhsReply)
        ):
            return Self.normalizedIdentifier(lhsPost) == Self.normalizedIdentifier(rhsPost)
                && Self.normalizedIdentifier(lhsComment) == Self.normalizedIdentifier(rhsComment)
                && Self.normalizedIdentifier(lhsReply) == Self.normalizedIdentifier(rhsReply)
        case (.identifyNature, .openScanner), (.openScanner, .identifyNature):
            return true
        case (.identifyNature, .identifyNature), (.openScanner, .openScanner):
            return true
        case let (.achievement(lhs), .achievement(rhs)):
            return lhs.id == rhs.id
        case let (.captureGoal(lhs), .captureGoal(rhs)):
            return lhs == rhs
        case let (
            .refinement(lhsScanID, _, lhsEntryPoint),
            .refinement(rhsScanID, _, rhsEntryPoint)
        ):
            return Self.normalizedIdentifier(lhsScanID) == Self.normalizedIdentifier(rhsScanID)
                && lhsEntryPoint == rhsEntryPoint
        case let (.scansLibraryRecovery(lhs), .scansLibraryRecovery(rhs)):
            return Self.normalizedIdentifier(lhs.ownerUserId)
                == Self.normalizedIdentifier(rhs.ownerUserId)
        #if DEBUG
        case (.debugPreviewAnalyzing, .debugPreviewAnalyzing):
            return true
        #endif
        default:
            return false
        }
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        value.map { normalizedIdentifier($0) }
    }

    fileprivate var isAccountSensitive: Bool {
        switch self {
        case .scan, .communityIdentification, .achievement, .captureGoal, .fieldTrips,
             .recallLastFind, .refinement, .nonBiologicalScans, .scansLibrary,
             .scansLibraryRecovery, .proAccessRequired:
            return true
        case .explorePost, .speciesDictionary, .identifyNature, .openScanner,
             .processExternalImageImports, .externalImageImportFailed:
            return false
        #if DEBUG
        case .debugPreviewAnalyzing:
            return false
        #endif
        }
    }
}

enum AppRouteSource: String, Sendable, Equatable {
    case durableExternalImport
    case deepLink
    case pushNotification
    case appIntent
    case internalUserAction
    case genericLaunch
    case debug

    fileprivate var priority: AppRoutePriority {
        switch self {
        case .durableExternalImport: .durableExternalImport
        case .deepLink, .pushNotification, .appIntent: .explicitExternal
        case .internalUserAction: .internalUserAction
        case .genericLaunch: .genericLaunch
        case .debug: .debug
        }
    }

    fileprivate var lifetime: TimeInterval? {
        switch self {
        case .durableExternalImport:
            return nil
        case .deepLink, .pushNotification:
            return 5 * 60
        case .appIntent:
            return 2 * 60
        case .internalUserAction:
            return 30
        case .genericLaunch:
            return 15
        case .debug:
            return 30
        }
    }

    fileprivate var survivesSessionReset: Bool {
        switch self {
        case .durableExternalImport, .deepLink, .pushNotification, .appIntent:
            return true
        case .internalUserAction, .genericLaunch, .debug:
            return false
        }
    }
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
    fileprivate let insertionSequence: UInt64

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

    fileprivate var isTerminal: Bool {
        switch self {
        case .applied(let presentationID):
            return presentationID == nil
        case .dismissed, .rejected:
            return true
        case .deferred:
            return false
        }
    }
}

struct AppRouteOutcomeRecord: Identifiable, Sendable, Equatable {
    let id: UUID
    let requestID: UUID
    let outcome: AppRouteOutcome
    let recordedAt: Date
}

@MainActor
protocol AppRouteRequesting: AnyObject {
    @discardableResult
    func request(_ route: AppRoute, source: AppRouteSource, id: UUID, now: Date) -> UUID
}

extension AppRouteRequesting {
    @discardableResult
    func request(
        _ route: AppRoute,
        source: AppRouteSource
    ) -> UUID {
        request(route, source: source, id: UUID(), now: Date())
    }
}

@MainActor
protocol AppRouteConsuming: AnyObject {
    var nextRequestID: UUID? { get }
    func claimNext(now: Date) -> AppRouteEnvelope?
    func resolve(_ requestID: UUID, outcome: AppRouteOutcome, now: Date)
    func resumeDeferredRequest(_ requestID: UUID)
}

@MainActor
protocol AppRouteSessionControlling: AnyObject {
    var accountGeneration: UInt64 { get }
    func beginAccountSession(
        accountID: String?,
        origin: AppRouteAccountSessionOrigin,
        now: Date
    )
    func advanceSession(now: Date)
    func shouldSuppressTimeoutReset(now: Date) -> Bool
}

extension AppRouteSessionControlling {
    func beginAccountSession(accountID: String?, now: Date) {
        beginAccountSession(accountID: accountID, origin: .runtimeTransition, now: now)
    }
}

/// Process-local, bounded state machine for delivery-critical navigation.
/// Durable work is represented by a route to drain its owning durable store;
/// route envelopes themselves intentionally do not survive process termination.
@MainActor
@Observable final class AppRouteCoordinator: AppRouteRequesting, AppRouteConsuming, AppRouteSessionControlling {
    private(set) var pendingRequests: [AppRouteEnvelope] = []
    private(set) var inFlightRequest: AppRouteEnvelope?
    private(set) var inFlightOutcome: AppRouteOutcome?
    private(set) var recentOutcomes: [AppRouteOutcomeRecord] = []
    private(set) var accountGeneration: UInt64 = 0
    private(set) var sessionGeneration: UInt64 = 0
    private(set) var currentAccountID: String?

    @ObservationIgnored private let maximumPendingCount: Int
    @ObservationIgnored private let maximumOutcomeCount: Int
    @ObservationIgnored private var lastAppliedExternalRouteAt: Date?
    @ObservationIgnored private var nextInsertionSequence: UInt64 = 0

    init(maximumPendingCount: Int = 16, maximumOutcomeCount: Int = 64) {
        self.maximumPendingCount = max(1, maximumPendingCount)
        self.maximumOutcomeCount = max(1, maximumOutcomeCount)
    }

    var nextRequestID: UUID? {
        guard inFlightRequest == nil else { return nil }
        return pendingRequests.first?.id
    }

    @discardableResult
    func request(
        _ route: AppRoute,
        source: AppRouteSource,
        id: UUID = UUID(),
        now: Date = Date()
    ) -> UUID {
        discardExpiredRequests(now: now)

        if let existing = inFlightRequest,
           existing.route.coalesces(with: route) {
            if shouldPromote(existing, to: source, now: now) {
                inFlightRequest = promoted(existing, to: source, now: now)
            }
            record(requestID: id, outcome: .rejected(reason: .coalesced(into: existing.id)), now: now)
            return id
        }

        if let existingIndex = pendingRequests.firstIndex(where: { $0.route.coalesces(with: route) }) {
            let existing = pendingRequests[existingIndex]
            pendingRequests[existingIndex] = mergedPendingDuplicate(
                existing,
                with: route,
                source: source,
                now: now
            )
            sortPendingRequests()
            record(requestID: id, outcome: .rejected(reason: .coalesced(into: existing.id)), now: now)
            return id
        }

        let envelope = AppRouteEnvelope(
            id: id,
            route: route,
            source: source,
            createdAt: now,
            priority: source.priority,
            expiresAt: source.lifetime.map { now.addingTimeInterval($0) },
            accountGeneration: accountGeneration,
            sessionGeneration: sessionGeneration,
            insertionSequence: nextInsertionSequence
        )
        nextInsertionSequence &+= 1

        if pendingRequests.count >= maximumPendingCount {
            let evictionIndex = pendingRequests.indices
                .filter { pendingRequests[$0].priority <= envelope.priority }
                .min { lhs, rhs in
                    let left = pendingRequests[lhs]
                    let right = pendingRequests[rhs]
                    if left.priority != right.priority { return left.priority < right.priority }
                    if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
                    return left.insertionSequence < right.insertionSequence
                }

            guard let evictionIndex else {
                record(requestID: id, outcome: .rejected(reason: .overflow), now: now)
                return id
            }

            let evicted = pendingRequests.remove(at: evictionIndex)
            record(requestID: evicted.id, outcome: .rejected(reason: .overflow), now: now)
        }

        pendingRequests.append(envelope)
        sortPendingRequests()
        return id
    }

    func claimNext(now: Date = Date()) -> AppRouteEnvelope? {
        discardExpiredRequests(now: now)
        guard inFlightRequest == nil, !pendingRequests.isEmpty else { return nil }

        let request = pendingRequests.removeFirst()
        guard request.accountGeneration == accountGeneration || !request.route.isAccountSensitive else {
            record(requestID: request.id, outcome: .rejected(reason: .staleAccount), now: now)
            return claimNext(now: now)
        }
        guard request.sessionGeneration == sessionGeneration || request.source.survivesSessionReset else {
            record(requestID: request.id, outcome: .rejected(reason: .staleSession), now: now)
            return claimNext(now: now)
        }

        inFlightRequest = request
        inFlightOutcome = nil
        return request
    }

    func resolve(_ requestID: UUID, outcome: AppRouteOutcome, now: Date = Date()) {
        guard inFlightRequest?.id == requestID else { return }

        // Enforce the state machine instead of allowing duplicate or stale UI
        // callbacks to rewrite an accepted presentation's identity.
        switch (inFlightOutcome, outcome) {
        case (nil, .applied), (nil, .deferred), (nil, .rejected):
            break
        case let (.applied(expectedPresentationID?), .dismissed(presentationID))
            where expectedPresentationID == presentationID:
            break
        default:
            return
        }

        if case .applied = outcome,
           let source = inFlightRequest?.source,
           source == .durableExternalImport || source == .deepLink || source == .pushNotification || source == .appIntent {
            lastAppliedExternalRouteAt = now
        }

        inFlightOutcome = outcome
        guard outcome.isTerminal else { return }

        record(requestID: requestID, outcome: outcome, now: now)
        inFlightRequest = nil
        inFlightOutcome = nil
    }

    func resumeDeferredRequest(_ requestID: UUID) {
        guard let request = inFlightRequest,
              request.id == requestID,
              case .deferred = inFlightOutcome else { return }
        inFlightRequest = nil
        inFlightOutcome = nil
        pendingRequests.append(request)
        sortPendingRequests()
    }

    func beginAccountSession(
        accountID: String?,
        origin: AppRouteAccountSessionOrigin,
        now: Date = Date()
    ) {
        let trimmedAccountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmedAccountID.flatMap { $0.isEmpty ? nil : $0.lowercased() }
        guard normalized != currentAccountID else { return }

        // Only the SDK's explicit initial-session event may adopt launch intent.
        // A generic nil -> account transition can be an interactive sign-in and
        // must fence private routes that were queued for a different owner.
        if origin == .initialRestoration,
           currentAccountID == nil,
           accountGeneration == 0 {
            currentAccountID = normalized
            return
        }

        currentAccountID = normalized
        accountGeneration &+= 1
        rejectRequests(where: { $0.route.isAccountSensitive }, reason: .staleAccount, now: now)
    }

    func advanceSession(now: Date = Date()) {
        sessionGeneration &+= 1
        rejectRequests(where: { !$0.source.survivesSessionReset }, reason: .staleSession, now: now)
    }

    func shouldSuppressTimeoutReset(now: Date = Date()) -> Bool {
        if let lastAppliedExternalRouteAt,
           now.timeIntervalSince(lastAppliedExternalRouteAt) <= 5 {
            return true
        }

        return ([inFlightRequest].compactMap { $0 } + pendingRequests).contains { request in
            request.source.survivesSessionReset && (request.expiresAt == nil || request.expiresAt! > now)
        }
    }

    #if DEBUG
    func resetForTesting() {
        pendingRequests.removeAll()
        inFlightRequest = nil
        inFlightOutcome = nil
        recentOutcomes.removeAll()
        accountGeneration = 0
        sessionGeneration = 0
        currentAccountID = nil
        lastAppliedExternalRouteAt = nil
        nextInsertionSequence = 0
    }
    #endif

    private func discardExpiredRequests(now: Date) {
        let hasAppliedPresentation: Bool
        if case .applied(let presentationID) = inFlightOutcome {
            hasAppliedPresentation = presentationID != nil
        } else {
            hasAppliedPresentation = false
        }

        if let inFlightRequest,
           inFlightRequest.expiresAt.map({ $0 <= now }) ?? false,
           !hasAppliedPresentation {
            record(requestID: inFlightRequest.id, outcome: .rejected(reason: .expired), now: now)
            self.inFlightRequest = nil
            inFlightOutcome = nil
        }

        let rejected = pendingRequests.filter { request in
            request.expiresAt.map { $0 <= now } ?? false
        }
        pendingRequests.removeAll { request in
            request.expiresAt.map { $0 <= now } ?? false
        }
        for request in rejected {
            record(requestID: request.id, outcome: .rejected(reason: .expired), now: now)
        }
    }

    private func rejectRequests(
        where predicate: (AppRouteEnvelope) -> Bool,
        reason: AppRouteRejectionReason,
        now: Date
    ) {
        if let inFlightRequest, predicate(inFlightRequest) {
            record(requestID: inFlightRequest.id, outcome: .rejected(reason: reason), now: now)
            self.inFlightRequest = nil
            inFlightOutcome = nil
        }

        let rejected = pendingRequests.filter(predicate)
        pendingRequests.removeAll(where: predicate)
        for request in rejected {
            record(requestID: request.id, outcome: .rejected(reason: reason), now: now)
        }
    }

    private func sortPendingRequests() {
        pendingRequests.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.insertionSequence < rhs.insertionSequence
        }
    }

    private func shouldPromote(
        _ existing: AppRouteEnvelope,
        to source: AppRouteSource,
        now: Date
    ) -> Bool {
        if source.priority != existing.priority {
            return source.priority > existing.priority
        }
        guard source != existing.source else { return false }

        let candidateExpiry = source.lifetime.map { now.addingTimeInterval($0) }
        switch (existing.expiresAt, candidateExpiry) {
        case (.some(let existingExpiry), .some(let candidateExpiry)):
            return candidateExpiry > existingExpiry
        case (.some, .none):
            return true
        case (.none, _):
            return false
        }
    }

    private func promoted(
        _ existing: AppRouteEnvelope,
        to source: AppRouteSource,
        now: Date
    ) -> AppRouteEnvelope {
        AppRouteEnvelope(
            id: existing.id,
            route: existing.route,
            source: source,
            createdAt: existing.createdAt,
            priority: source.priority,
            expiresAt: source.lifetime.map { now.addingTimeInterval($0) },
            accountGeneration: accountGeneration,
            sessionGeneration: sessionGeneration,
            insertionSequence: existing.insertionSequence
        )
    }

    private func mergedPendingDuplicate(
        _ existing: AppRouteEnvelope,
        with latestRoute: AppRoute,
        source: AppRouteSource,
        now: Date
    ) -> AppRouteEnvelope {
        guard shouldPromote(existing, to: source, now: now) else {
            return AppRouteEnvelope(
                id: existing.id,
                route: latestRoute,
                source: existing.source,
                createdAt: existing.createdAt,
                priority: existing.priority,
                expiresAt: existing.expiresAt,
                accountGeneration: existing.accountGeneration,
                sessionGeneration: existing.sessionGeneration,
                insertionSequence: existing.insertionSequence
            )
        }

        let promotedEnvelope = promoted(existing, to: source, now: now)
        return AppRouteEnvelope(
            id: promotedEnvelope.id,
            route: latestRoute,
            source: promotedEnvelope.source,
            createdAt: promotedEnvelope.createdAt,
            priority: promotedEnvelope.priority,
            expiresAt: promotedEnvelope.expiresAt,
            accountGeneration: promotedEnvelope.accountGeneration,
            sessionGeneration: promotedEnvelope.sessionGeneration,
            insertionSequence: promotedEnvelope.insertionSequence
        )
    }

    private func record(requestID: UUID, outcome: AppRouteOutcome, now: Date) {
        recentOutcomes.append(
            AppRouteOutcomeRecord(id: UUID(), requestID: requestID, outcome: outcome, recordedAt: now)
        )
        if recentOutcomes.count > maximumOutcomeCount {
            recentOutcomes.removeFirst(recentOutcomes.count - maximumOutcomeCount)
        }
    }
}
