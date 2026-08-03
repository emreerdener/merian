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
            return scansAvailableToStart > 0
        default:
            return false
        }
    }

    var isComplimentaryExhausted: Bool {
        isVerifiedForCurrentLaunch && !isPaid && scansRemaining == 0 && inFlightCount == 0
    }

    /// Resets proof when the account changes, then verifies against the private
    /// ledger. A failed refresh never creates complimentary offline access.
    func beginSession(userID: UUID, client: SupabaseClient) async {
        if sessionUserID != userID {
            resetState(sessionUserID: userID)
        }
        let generation = sessionGeneration

        do {
            let rows: [EntitlementSnapshotDTO] = try await client
                .rpc("get_my_entitlement")
                .execute()
                .value
            guard generation == sessionGeneration,
                  sessionUserID == userID,
                  rows.count == 1 else { return }
            _ = apply(rows[0], for: userID)
        } catch {
            MerianLog.auth.debug(
                "Complimentary entitlement verification failed: \(error.localizedDescription, privacy: .private)"
            )
        }
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
}
