import Foundation
import SwiftData

/// Prepared admission of server-selected state. This never requests selection,
/// enrolls a scan, settles local intent, or supplies a Restore/Undo receipt.
@MainActor
struct ObservationHistoryStateSyncService {
    enum AdmissionError: Error, Equatable {
        case staleRevision, conflictingRevision, pendingReview, selectionProjectionRequired, authorityStorageRequired
    }

    var cloud = ObservationHistoryCloudClient.live

    /// Local, settled display ticket for explicit entry. Does not sync or change selection.
    static func displayBaseline(observation: UUID, container: ModelContainer) throws -> ReviewBaseline {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            let scan = try ObservationHistorySyncService.enrolledScan(observation.uuidString, context: context)
            try ObservationHistorySelectionIntent.requireIdle(scan.id, context: context)
            try requireSettledReview(scan, context: context)
            return ReviewBaseline(scan, displayAnalysisID: observation)
        }
    }

    @discardableResult
    func syncSelected(observationID: String, container: ModelContainer) async throws -> Int {
        let baseline = try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            let scan = try ObservationHistorySyncService.enrolledScan(observationID, context: context)
            try ObservationHistorySelectionIntent.requireIdle(scan.id, context: context)
            try Self.requireSettledReview(scan, context: context)
            return ReviewBaseline(scan)
        }
        guard let ownerID = UUID(uuidString: baseline.owner) else { throw ObservationHistoryError.unavailable }
        let lease = try cloud.begin(ownerID)
        defer { cloud.finish(lease) }
        guard lease.session.userID == ownerID, cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        let request = ObservationHistoryStateRequest(observation_id: observationID.lowercased(), analysis_id: nil)
        let data = try await cloud.fetchState(request)
        try Task.checkCancellation()
        guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        let state = try ObservationHistoryState.decode(data, request: request, ownerID: ownerID)
        return try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
                let scan = try ObservationHistorySyncService.enrolledScan(observationID, context: context)
                guard scan.analysisOwnerAccountID == baseline.owner else { throw ObservationHistoryError.accountChanged }
                try ObservationHistorySelectionIntent.requireIdle(scan.id, context: context)
                try Self.requireSettledReview(scan, context: context)
                guard ReviewBaseline(scan) == baseline else { throw AdmissionError.conflictingRevision }
                try Self.apply(state, to: scan, baseline: baseline, context: context)
                try Task.checkCancellation()
                guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
                if context.hasChanges { try context.save() }
                return state.revision
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    /// Shared projection writer; caller owns account, deletion, baseline, pending-intent and save fences.
    static func apply(_ state: ObservationHistoryState, to scan: LocalScanRecord, baseline: ReviewBaseline, context: ModelContext) throws {
        let ownerID = state.ownerID
        guard state.revision >= baseline.revision else { throw AdmissionError.staleRevision }
        let changesSelection = scan.selectedAnalysisID.flatMap(UUID.init(uuidString:)) != state.selectedAnalysisID
        if changesSelection {
            guard state.revision > baseline.revision else { throw AdmissionError.conflictingRevision }
            let previous = try ObservationHistorySelectionProjection.retainedAuthority(scan: scan, context: context)
            // An unmarked legacy Undo must not become permission to
            // discard the currently visible identification or intent.
            guard scan.localAIIdentificationReview.authority != nil || scan.confirmedSpeciesIdentityData != nil,
                  Self.matches(previous, scan: scan) else { throw AdmissionError.pendingReview }
            try Self.requireRepresentableAuthority(state.review)
        } else {
            try Self.validateAuthority(state.review, against: scan)
            if state.revision == baseline.revision, !Self.matches(state.review, scan: scan) {
                throw AdmissionError.conflictingRevision
            }
        }
        _ = try ObservationHistorySyncService.insert([state.result], into: scan, ownerID: ownerID, context: context)
        let initialSavedDisplay: Data?
        if !changesSelection, Self.matches(state.review, scan: scan), let display = baseline.display {
            initialSavedDisplay = try SavedIdentificationDisplayBaseline.capture(display, matching: state.result)
        } else { initialSavedDisplay = nil }
        let display = try ObservationHistoryStateCache.admit(state, scan: scan, context: context, initialSavedDisplay: initialSavedDisplay)
        if changesSelection {
            guard let display else { throw AdmissionError.selectionProjectionRequired }
            display.apply(to: scan)
            scan.selectedAnalysisID = state.selectedAnalysisID.uuidString.lowercased()
        }
        if state.revision > baseline.revision {
            scan.aiIdentificationReviewData = try LocalAIIdentificationReview(authority: state.review.aiReview).storedData()
            scan.confirmedSpeciesIdentityData = try Self.nativeSpeciesReview(state.review)?.storedData()
            scan.confirmedSpeciesId = state.review.confirmedSpeciesID
            scan.userIdentificationOverride = state.review.override
            scan.userConfirmedIdentification = state.review.confirmed ?? false
            scan.userReviewStateRaw = state.review.state?.rawValue
            scan.observationStateRevision = state.revision
        }
    }

    static func requireSettledReview(_ scan: LocalScanRecord, context: ModelContext) throws {
        let local = scan.localAIIdentificationReview
        guard local.pending == nil, local.optimisticState == nil, !local.needsAttention else { throw AdmissionError.pendingReview }
        let kind = OfflineJobKind.identificationReviewSync.rawValue
        let lower = scan.id.lowercased(), upper = scan.id.uppercased()
        let complete = OfflineJobStatus.complete.rawValue, cancelled = OfflineJobStatus.cancelled.rawValue
        var jobs = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
            $0.kindRaw == kind && ($0.subjectId == lower || $0.subjectId == upper) &&
                $0.statusRaw != complete && $0.statusRaw != cancelled
        })
        jobs.fetchLimit = 1
        guard try context.fetch(jobs).isEmpty else { throw AdmissionError.pendingReview }
        let verified = try ConfirmedSpeciesReview.restoring(scan.confirmedSpeciesIdentityData)
        if let verified {
            guard verified.matchesIntent(override: scan.userIdentificationOverride,
                confirmed: scan.userConfirmedIdentification, state: scan.userReviewState),
                verified.confirmedSpeciesID == scan.confirmedSpeciesId else { throw AdmissionError.pendingReview }
        } else if scan.primaryIdentificationData != nil {
            // The older verified-review path persists intent before dispatch and
            // has no outbox. Without acknowledged authority, defer that intent.
            guard scan.userIdentificationOverride == nil, !scan.userConfirmedIdentification,
                  scan.confirmedSpeciesId == nil, scan.userReviewState == .unreviewed else { throw AdmissionError.pendingReview }
        }
    }

    static func validateAuthority(_ incoming: ObservationHistoryAuthority, against scan: LocalScanRecord) throws {
        try requireRepresentableAuthority(incoming)
        if scan.localAIIdentificationReview.authority == nil, scan.confirmedSpeciesIdentityData == nil,
           !matches(incoming, scan: scan) {
            // A legacy offline Undo can leave exactly the default tuple with
            // no durable pending marker. It is not proof of untouched state.
            throw AdmissionError.pendingReview
        }
        if let old = scan.localAIIdentificationReview.authority {
            guard let new = incoming.aiReview, new.revision >= old.revision else { throw AdmissionError.staleRevision }
            guard new.revision != old.revision || new == old else { throw AdmissionError.conflictingRevision }
        }
        if let old = try ConfirmedSpeciesReview.restoring(scan.confirmedSpeciesIdentityData) {
            guard incoming.identityRevision >= old.revision else { throw AdmissionError.staleRevision }
            guard incoming.identityRevision != old.revision || nativeSpeciesReview(incoming) == old else {
                throw AdmissionError.conflictingRevision
            }
        } else if scan.userIdentificationOverride != nil || scan.userConfirmedIdentification ||
                    scan.confirmedSpeciesId != nil || scan.userReviewState != .unreviewed {
            // Legacy intent has no separate acknowledgement. Do not erase a
            // pre-existing correction merely because no outbox can describe it.
            guard incoming.override == scan.userIdentificationOverride,
                  (incoming.confirmed ?? false) == scan.userConfirmedIdentification,
                  incoming.confirmedSpeciesID == scan.confirmedSpeciesId,
                  (incoming.state ?? .unreviewed) == scan.userReviewState else { throw AdmissionError.pendingReview }
        }
    }

    static func requireRepresentableAuthority(_ incoming: ObservationHistoryAuthority) throws {
        guard incoming.identityRevision == 0 || nativeSpeciesReview(incoming) != nil else {
            // Existing selected-review slots cannot retain this legacy tuple's
            // revision. The raw cache does not fix that active projection gap.
            throw AdmissionError.authorityStorageRequired
        }
    }

    static func matches(_ incoming: ObservationHistoryAuthority, scan: LocalScanRecord) -> Bool {
        let stored = try? ConfirmedSpeciesReview.restoring(scan.confirmedSpeciesIdentityData)
        let speciesMatches = stored.map { nativeSpeciesReview(incoming) == $0 } ??
            (incoming.speciesReview == nil && incoming.identityRevision == 0)
        return incoming.aiReview == scan.localAIIdentificationReview.authority && speciesMatches &&
            incoming.confirmedSpeciesID == scan.confirmedSpeciesId && incoming.override == scan.userIdentificationOverride &&
            (incoming.confirmed ?? false) == scan.userConfirmedIdentification && (incoming.state ?? .unreviewed) == scan.userReviewState
    }

    private static func nativeSpeciesReview(_ incoming: ObservationHistoryAuthority) -> ConfirmedSpeciesReview? {
        if let review = incoming.speciesReview { return review }
        guard let confirmed = incoming.confirmed, let state = incoming.state else { return nil }
        // Preserve revisioned clears when representable. Imported legacy tuples
        // may be inconsistent and must not manufacture a verified identity.
        return try? ConfirmedSpeciesReview(revision: incoming.identityRevision, identity: nil,
            override: incoming.override, confirmed: confirmed, speciesID: incoming.confirmedSpeciesID, state: state)
    }

    /// Re-fetch after suspension, including the legacy review intent that has no
    /// durable outbox. A newer local writer always wins over this response.
    struct ReviewBaseline: Equatable {
        let owner: String
        let selected: String?
        let revision: Int
        let ai: Data?
        let species: Data?
        let speciesID: String?
        let override: String?
        let confirmed: Bool
        let reviewState: String?
        let display: AnalysisDisplaySnapshot?

        /// Enrollment changes owner/selection/revision metadata, never the visible identification.
        func retainsIdentification(of other: Self) -> Bool {
            ai == other.ai && species == other.species && speciesID == other.speciesID
                && override == other.override && confirmed == other.confirmed
                && reviewState == other.reviewState && display == other.display
        }

        init(_ scan: LocalScanRecord, displayAnalysisID: UUID? = nil) {
            owner = scan.analysisOwnerAccountID ?? ""
            selected = scan.selectedAnalysisID
            revision = scan.observationStateRevision ?? 0
            ai = scan.aiIdentificationReviewData
            species = scan.confirmedSpeciesIdentityData
            speciesID = scan.confirmedSpeciesId
            override = scan.userIdentificationOverride
            confirmed = scan.userConfirmedIdentification
            reviewState = scan.userReviewStateRaw
            display = (displayAnalysisID ?? scan.selectedAnalysisID.flatMap(UUID.init(uuidString:))).map { AnalysisDisplaySnapshot(analysisID: $0, record: scan) }
        }
    }
}
