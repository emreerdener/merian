import Foundation
import Observation
import Supabase

/// Owns the server-verified, current-launch complimentary entitlement.
/// Paid offline access remains owned by RevenueCatManager.
@MainActor
@Observable final class EntitlementManager {
    static let shared = EntitlementManager()

    private(set) var currentPlan = "free"
    private(set) var currentTier = "free"
    private(set) var isPaid = false
    private(set) var scansRemaining = 0
    private(set) var scansAvailableToStart = 0
    private(set) var inFlightCount = 0
    private(set) var entitlementVersion = 0
    private(set) var isVerifiedForCurrentLaunch = false

    @ObservationIgnored private var sessionUserID: UUID?
    @ObservationIgnored private var sessionGeneration = UUID()
    @ObservationIgnored private var pendingScanSnapshot: EntitlementSnapshotDTO?
    @ObservationIgnored private var fundingReservations:
        [String: ScanFundingReservation] = [:]
    @ObservationIgnored private var complimentaryStates:
        [String: ComplimentaryScanState] = [:]
    @ObservationIgnored private var legacyPotentialBlockers: [String: Date] = [:]
    @ObservationIgnored private var pendingTerminalSettlementRefreshScanIds:
        Set<String> = []

    private init() {}

    var hasVerifiedComplimentaryAccess: Bool {
        isVerifiedForCurrentLaunch && currentPlan == "pro_complimentary"
    }

    /// Current-session server proof for functional Pro features. This includes
    /// legacy trial mode only until the backend's atomic complimentary cutover.
    var hasVerifiedFunctionalProAccess: Bool {
        isVerifiedForCurrentLaunch && currentTier == "pro"
    }

    /// Starting a new Pro-funded scan requires an unheld complimentary credit.
    /// Existing holds still unlock non-scan Pro functionality and recovery.
    var canStartProFundedScan: Bool {
        guard isVerifiedForCurrentLaunch else { return false }
        switch currentPlan {
        case "pro_paid", "pro_trial":
            return true
        case "pro_complimentary":
            return locallyAvailableComplimentaryCredits > 0
        default:
            return false
        }
    }

    var isComplimentaryExhausted: Bool {
        isVerifiedForCurrentLaunch && !isPaid && scansRemaining == 0 && inFlightCount == 0
    }

    var activeAccountID: UUID? { sessionUserID }

    /// Server availability minus unresolved local reservations. A state-only
    /// status read cannot prove that the current entitlement snapshot already
    /// reflects a hold, so reservations remain subtracted until terminal proof.
    var locallyAvailableComplimentaryCredits: Int {
        max(0, scansAvailableToStart - unresolvedLocalComplimentaryCount)
    }

    /// Claims an idempotent funding class before capture code writes files or
    /// begins foreground inference. A nil result means the capture is neither
    /// Pro-funded nor eligible for the single-item Flash fallback.
    func claimFunding(
        scanId: String,
        flashFallbackEligible: Bool
    ) -> ScanFundingReservation? {
        guard let accountId = sessionUserID else { return nil }
        let normalizedScanId = scanId.lowercased()
        if let existing = fundingReservations[normalizedScanId],
           existing.accountId == accountId {
            return existing
        }

        let source: ScanFundingSource
        var blockerScanIds: [String] = []
        if hasPaidProAccessForAdmission {
            source = .paidPro
        } else if hasVerifiedComplimentaryAccessForAdmission &&
                    locallyAvailableComplimentaryCredits > 0 {
            source = .complimentaryPro
        } else if flashFallbackEligible {
            blockerScanIds = unresolvedComplimentaryBlockerIds
            source = blockerScanIds.isEmpty ? .immediateFlash : .deferredFlash
        } else {
            return nil
        }

        let reservation = ScanFundingReservation(
            accountId: accountId,
            scanId: normalizedScanId,
            source: source,
            blockerScanIds: blockerScanIds
        )
        if complimentaryStates[normalizedScanId] == .released {
            complimentaryStates[normalizedScanId] = nil
        }
        fundingReservations[normalizedScanId] = reservation
        return reservation
    }

    func fundingReservation(scanId: String) -> ScanFundingReservation? {
        guard let reservation = fundingReservations[scanId.lowercased()],
              reservation.accountId == sessionUserID else {
            return nil
        }
        return reservation
    }

    func restoreFundingReservation(_ reservation: ScanFundingReservation) {
        guard reservation.accountId == sessionUserID else { return }
        let key = reservation.scanId.lowercased()
        if complimentaryStates[key] == .consumed ||
            complimentaryStates[key] == .released {
            return
        }
        if let existing = fundingReservations[key],
           existing.createdAt > reservation.createdAt {
            return
        }
        fundingReservations[key] = reservation
    }

    func restoreLegacyPotentialBlocker(scanId: String, createdAt: Date) {
        let key = scanId.lowercased()
        if complimentaryStates[key] == .consumed ||
            complimentaryStates[key] == .released {
            return
        }
        legacyPotentialBlockers[key] = min(
            legacyPotentialBlockers[key] ?? createdAt,
            createdAt
        )
    }

    /// Releases only admissions proven not to have reached server dispatch.
    /// Ambiguous outcomes deliberately retain their reservation.
    func releaseFundingAfterProvenLocalFailure(scanId: String) {
        let key = scanId.lowercased()
        let releasedComplimentaryBlocker =
            fundingReservations[key]?.source == .complimentaryPro ||
            legacyPotentialBlockers[key] != nil
        fundingReservations[key] = nil
        legacyPotentialBlockers[key] = nil
        pendingTerminalSettlementRefreshScanIds.remove(key)
        complimentaryStates[key] = releasedComplimentaryBlocker
            ? .released
            : nil
    }

    func fundingAllowsDispatch(scanId: String) -> Bool {
        let key = scanId.lowercased()
        return fundingReservation(scanId: key)?.allowsDispatch ??
            true
    }

    func fundingAllowsForegroundInference(scanId: String) -> Bool {
        fundingReservation(scanId: scanId)?.allowsForegroundInference ?? true
    }

    func fundingPriority(scanId: String) -> Int {
        if legacyPotentialBlockers[scanId.lowercased()] != nil { return 0 }
        switch fundingReservation(scanId: scanId)?.source {
        case .complimentaryPro?: return 0
        case .paidPro?: return 1
        case .immediateFlash?: return 2
        case .deferredFlash?: return 3
        case nil: return 4
        }
    }

    var deferredFundingReservations: [ScanFundingReservation] {
        fundingReservations.values
            .filter { $0.accountId == sessionUserID && $0.source == .deferredFlash }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var fundingBlockerScanIds: [String] {
        Array(Set(deferredFundingReservations.flatMap(\.blockerScanIds))).sorted()
    }

    func applyComplimentaryState(
        _ state: ComplimentaryScanState?,
        scanId: String,
        terminalized: Bool
    ) {
        let key = scanId.lowercased()
        if let state {
            // A released hold can become available again only after the
            // earlier local job is terminal. Until then that job may retry and
            // claim the same complimentary capacity again.
            guard state != .released || terminalized else { return }
            complimentaryStates[key] = state
            if state == .consumed && terminalized {
                // A status response proves settlement, but only a subsequent
                // entitlement read proves that the local balance snapshot
                // includes it. Keep the local blocker reserved until then.
                pendingTerminalSettlementRefreshScanIds.insert(key)
            } else if state == .released && terminalized {
                fundingReservations[key] = nil
                legacyPotentialBlockers[key] = nil
                pendingTerminalSettlementRefreshScanIds.remove(key)
            }
        } else if terminalized {
            // Absence after terminalization is authoritative evidence that the
            // local complimentary assumption did not establish a hold.
            complimentaryStates[key] = .released
            fundingReservations[key] = nil
            legacyPotentialBlockers[key] = nil
            pendingTerminalSettlementRefreshScanIds.remove(key)
        }
    }

    var needsTerminalSettlementEntitlementRefresh: Bool {
        !pendingTerminalSettlementRefreshScanIds.isEmpty
    }

    /// Clears terminal consumed blockers only after get_my_entitlement has
    /// succeeded after the status proof. This prevents a pre-hold snapshot from
    /// reopening complimentary capacity during the refresh suspension.
    func confirmTerminalSettlementsAfterEntitlementRefresh() {
        for key in pendingTerminalSettlementRefreshScanIds
        where complimentaryStates[key] == .consumed {
            fundingReservations[key] = nil
            legacyPotentialBlockers[key] = nil
        }
        pendingTerminalSettlementRefreshScanIds.removeAll()
    }

    var hasReleasedDeferredBlocker: Bool {
        deferredFundingReservations.contains { reservation in
            reservation.blockerScanIds.contains {
                complimentaryStates[$0.lowercased()] == .released
            }
        }
    }

    /// Reclassifies deferred work after blocker states and, when needed, a
    /// fresh entitlement snapshot have been installed. The caller persists
    /// each returned reservation back into the job metadata.
    func resolveDeferredFunding() -> [ScanFundingReservation] {
        var changes: [ScanFundingReservation] = []
        for current in deferredFundingReservations {
            let key = current.scanId.lowercased()
            let states = current.blockerScanIds.map {
                complimentaryStates[$0.lowercased()]
            }
            var updated = current
            if hasPaidProAccessForAdmission {
                updated.source = .paidPro
                updated.blockerScanIds = []
            } else if states.allSatisfy({ $0 == .held || $0 == .consumed }) {
                updated.source = .immediateFlash
                updated.blockerScanIds = []
            } else if states.contains(.released) {
                if hasVerifiedComplimentaryAccessForAdmission &&
                    locallyAvailableComplimentaryCredits > 0 {
                    updated.source = .complimentaryPro
                    updated.blockerScanIds = []
                    complimentaryStates[key] = nil
                } else {
                    let blockers = unresolvedComplimentaryBlockerIds.filter {
                        $0 != key
                    }
                    updated.source = blockers.isEmpty
                        ? .immediateFlash
                        : .deferredFlash
                    updated.blockerScanIds = blockers
                }
            } else {
                continue
            }
            fundingReservations[key] = updated
            changes.append(updated)
        }
        return changes
    }

    /// A successful response proves the final server funding class and whether
    /// a complimentary hold was consumed or released (for example, after a
    /// purchase completed before settlement).
    func recordCompletedFunding(
        planUsed: String,
        creditConsumed: Bool,
        scanId: String
    ) {
        let key = scanId.lowercased()
        let wasComplimentaryBlocker =
            fundingReservations[key]?.source == .complimentaryPro ||
            legacyPotentialBlockers[key] != nil
        if planUsed == "pro_complimentary" && creditConsumed {
            complimentaryStates[key] = .consumed
        } else if planUsed == "pro_complimentary" || wasComplimentaryBlocker {
            complimentaryStates[key] = .released
        }
        fundingReservations[key] = nil
        legacyPotentialBlockers[key] = nil
        pendingTerminalSettlementRefreshScanIds.remove(key)
    }

    func invalidateComplimentaryProofAfterPaymentRequired() {
        isVerifiedForCurrentLaunch = false
        RevenueCatManager.shared.synchronizeFunctionalEntitlement()
    }

    @discardableResult
    func refreshCurrentSession() async -> Bool {
        guard let sessionUserID else { return false }
        return await beginSession(
            userID: sessionUserID,
            client: SupabaseManager.shared.client
        )
    }

    /// Resets proof when the account changes, then verifies against the private
    /// ledger. A failed refresh never creates complimentary offline access.
    @discardableResult
    func beginSession(
        userID: UUID,
        client: SupabaseClient,
        authTransitionOwner: AuthTransitionToken? = nil
    ) async -> Bool {
        let supabaseManager = SupabaseManager.shared
        let accountWorkLease: AccountBoundWorkLease?
        if let authTransitionOwner {
            guard supabaseManager.ownsAuthTransition(authTransitionOwner) else {
                return false
            }
            accountWorkLease = nil
        } else {
            guard let admitted = try? supabaseManager
                .beginUnownedAccountBoundWork(expectedUserID: userID) else {
                return false
            }
            accountWorkLease = admitted
        }
        defer {
            if let accountWorkLease {
                supabaseManager.finishAccountBoundWork(accountWorkLease)
            }
        }

        if sessionUserID != userID {
            resetState(sessionUserID: userID)
        }
        let generation = sessionGeneration
        OfflineQueueManager.shared.restoreFundingReservationsForCurrentAccount()

        do {
            let rows: [EntitlementSnapshotDTO] = try await client
                .rpc("get_my_entitlement")
                .execute()
                .value
            let accountContextIsCurrent: Bool
            if let authTransitionOwner {
                accountContextIsCurrent = supabaseManager
                    .ownsAuthTransition(authTransitionOwner)
                    && supabaseManager.client.auth.currentSession?.user.id
                        == userID
            } else if let accountWorkLease {
                accountContextIsCurrent = supabaseManager
                    .isAccountBoundWorkLeaseCurrent(accountWorkLease)
            } else {
                accountContextIsCurrent = false
            }
            guard Self.acceptsSessionVerificationResult(
                accountContextIsCurrent: accountContextIsCurrent,
                expectedUserID: userID,
                activeUserID: sessionUserID,
                requestGeneration: generation,
                activeGeneration: sessionGeneration,
                rowCount: rows.count
            ) else { return false }
            return apply(rows[0], for: userID)
        } catch {
            MerianLog.auth.debug(
                "Complimentary entitlement verification failed; kind=\(MerianLog.errorKind(error), privacy: .public)."
            )
            return false
        }
    }

    nonisolated static func acceptsSessionVerificationResult(
        accountContextIsCurrent: Bool,
        expectedUserID: UUID,
        activeUserID: UUID?,
        requestGeneration: UUID,
        activeGeneration: UUID,
        rowCount: Int
    ) -> Bool {
        accountContextIsCurrent
            && activeUserID == expectedUserID
            && requestGeneration == activeGeneration
            && rowCount == 1
    }

    /// Establishes the current-launch server baseline, then reconciles any scan
    /// response that arrived while that verification request was in flight.
    @discardableResult
    func apply(_ snapshot: EntitlementSnapshotDTO, for userID: UUID? = nil) -> Bool {
        if let userID, userID != sessionUserID { return false }
        guard sessionUserID != nil, installVerified(snapshot) else { return false }

        // A scan may finish while the launch-baseline RPC is in flight. Buffer
        // that response until this server proof arrives, then apply it only if
        // its version is at least as new as the verified baseline.
        if let pendingScanSnapshot {
            self.pendingScanSnapshot = nil
            _ = installVerified(pendingScanSnapshot)
        }
        return true
    }

    @discardableResult
    func apply(_ metadata: ScanEntitlementMetadataDTO) -> Bool {
        guard let userID = UUID(uuidString: metadata.userID) else {
            return false
        }
        guard userID == sessionUserID,
              Self.isValid(metadata.entitlementAfter) else {
            return false
        }

        // Stored idempotent replay envelopes retain their original entitlement
        // snapshot. They must never establish current-launch proof on their
        // own; wait for get_my_entitlement() to establish the current version.
        guard isVerifiedForCurrentLaunch else {
            if let pendingScanSnapshot {
                if metadata.entitlementAfter.entitlementVersion >=
                    pendingScanSnapshot.entitlementVersion {
                    self.pendingScanSnapshot = metadata.entitlementAfter
                }
            } else {
                pendingScanSnapshot = metadata.entitlementAfter
            }
            return false
        }
        return installVerified(metadata.entitlementAfter)
    }

    func handleSignOut() {
        resetState(sessionUserID: nil)
    }

    #if DEBUG
    func resetForTesting(userID: UUID? = nil) {
        resetState(sessionUserID: userID)
    }
    #endif

    private func resetState(sessionUserID: UUID?) {
        self.sessionUserID = sessionUserID
        sessionGeneration = UUID()
        currentPlan = "free"
        currentTier = "free"
        isPaid = false
        scansRemaining = 0
        scansAvailableToStart = 0
        inFlightCount = 0
        entitlementVersion = 0
        isVerifiedForCurrentLaunch = false
        pendingScanSnapshot = nil
        fundingReservations = [:]
        complimentaryStates = [:]
        legacyPotentialBlockers = [:]
        pendingTerminalSettlementRefreshScanIds = []
        RevenueCatManager.shared.synchronizeFunctionalEntitlement()
    }

    @discardableResult
    private func installVerified(_ snapshot: EntitlementSnapshotDTO) -> Bool {
        guard Self.isValid(snapshot),
              snapshot.entitlementVersion >= entitlementVersion else {
            return false
        }

        currentPlan = snapshot.currentPlan
        currentTier = snapshot.currentTier
        isPaid = snapshot.isPaid
        scansRemaining = snapshot.scansRemaining
        scansAvailableToStart = snapshot.scansAvailableToStart
        inFlightCount = snapshot.inFlightCount
        entitlementVersion = snapshot.entitlementVersion
        isVerifiedForCurrentLaunch = true
        RevenueCatManager.shared.synchronizeFunctionalEntitlement()
        return true
    }

    private static func isValid(_ snapshot: EntitlementSnapshotDTO) -> Bool {
        let plans = Set(["free", "pro_paid", "pro_trial", "pro_complimentary"])
        guard plans.contains(snapshot.currentPlan),
              snapshot.currentTier == "free" || snapshot.currentTier == "pro",
              snapshot.scansRemaining >= 0 && snapshot.scansRemaining <= 3,
              snapshot.scansAvailableToStart >= 0,
              snapshot.scansAvailableToStart <= snapshot.scansRemaining,
              snapshot.inFlightCount >= 0,
              snapshot.scansAvailableToStart + snapshot.inFlightCount == snapshot.scansRemaining,
              snapshot.entitlementVersion >= 1,
              (snapshot.currentPlan == "free") == (snapshot.currentTier == "free"),
              (snapshot.currentPlan == "pro_paid") == snapshot.isPaid else {
            return false
        }
        return true
    }

    private var hasVerifiedComplimentaryAccessForAdmission: Bool {
        isVerifiedForCurrentLaunch && currentPlan == "pro_complimentary"
    }

    private var hasPaidProAccessForAdmission: Bool {
        RevenueCatManager.shared.isSubscribed ||
            (isVerifiedForCurrentLaunch &&
                (currentPlan == "pro_paid" || currentPlan == "pro_trial"))
    }

    private var unresolvedLocalComplimentaryCount: Int {
        let reservedScanIds = fundingReservations.values.compactMap { reservation -> String? in
            guard reservation.accountId == sessionUserID,
                  reservation.source == .complimentaryPro else {
                return nil
            }
            return reservation.scanId.lowercased()
        }
        // Active pre-protocol-3 jobs have no durable classification. Treat each
        // as a possible complimentary claim until terminal server proof settles
        // it; temporary under-admission is safer than allocating the same credit.
        return Set(reservedScanIds + Array(legacyPotentialBlockers.keys)).count
    }

    private var unresolvedComplimentaryBlockerIds: [String] {
        let local = fundingReservations.values.compactMap { reservation ->
            (String, Date)? in
            guard reservation.accountId == sessionUserID,
                  reservation.source == .complimentaryPro,
                  complimentaryStates[reservation.scanId.lowercased()] == nil else {
                return nil
            }
            return (reservation.scanId.lowercased(), reservation.createdAt)
        }
        let legacy = legacyPotentialBlockers.compactMap { key, createdAt -> (String, Date)? in
            guard complimentaryStates[key.lowercased()] == nil else { return nil }
            return (key, createdAt)
        }
        return (local + legacy)
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0 < rhs.0 }
                return lhs.1 < rhs.1
            }
            .map(\.0)
    }
}
