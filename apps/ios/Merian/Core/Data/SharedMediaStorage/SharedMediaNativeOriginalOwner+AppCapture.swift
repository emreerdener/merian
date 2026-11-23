import Foundation

/// Capture endpoint composition owns scan persistence locking and funding
/// reconciliation. Private root/epoch admission stays in the lifecycle owner.
@MainActor
extension SharedMediaNativeOriginalOwner {
    /// A failed handoff preserves the draft, its stable plan and funding. A
    /// cancellation or lost reply is never evidence that reservation was absent.
    func acceptAppCaptureDraft(plan: CaptureInitialEvidencePlan, context: SharedMediaCaptureSubmissionContext,
                               expectedJournal: SharedMediaCaptureDraftJournalReceipt.Snapshot? = nil,
                               readArtifact: @escaping SharedMediaCaptureDraftAcceptance.ReadArtifact) async throws -> SharedMediaCaptureSubmissionAcceptance {
        // A previous failed operation left its liabilities intact. Requalify
        // them before retrying, including when the feature retains this owner.
        if requiresCaptureRecovery { try await resumeAppCaptureRoot() }
        guard isReadyForCaptureDraft else { throw SharedMediaStorageFailure.closed }
        return try await withCapturePersistence(scanID: plan.scanID) { [self] in
            try await captureRootWorkflow(requalify: true) { operations in
                let accepted = try await operations.acceptAppCaptureDraft(plan: plan, context: context,
                    expectedJournal: expectedJournal,
                    readArtifact: readArtifact)
                // Other drafts remain pending. Acceptance proves this exact
                // observation; it need not grant global capture dispatch.
                return accepted
            }
        }
    }
    func stageAppCaptureSubmission(scanID: UUID, generation: UUID,
                                   transport: CaptureStageTransport) async throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        try await withCapturePersistence(scanID: scanID) { [self] in
            try await captureRootWorkflow(requalify: true) { operations in
                // The worker audits the complete root and requires the exact
                // accepted target before transport. Pending siblings confer no
                // authority and do not block an independently accepted target.
                let result = try await operations.stageAppCaptureSubmission(scanID: scanID, generation: generation,
                    transport: transport)
                return result
            }
        }
    }
    func completeAppCaptureSubmission(scanID: UUID, submissionGeneration: UUID, attemptGeneration: UUID,
                                      resultData: Data, account: InferenceCompletionAccountScope,
                                      settleFunding: ((SharedMediaCaptureResultWriter.FundingHandoff) throws -> Void)? = nil) async throws -> SharedMediaCaptureResultWriter.Outcome {
        let funding = try SharedMediaCaptureFundingSettlement.Delivery(testOverride: settleFunding)
        defer { funding.reconcileAfterPersistence() }
        return try await withCapturePersistence(scanID: scanID) { [self] in
            try await captureSettlementWorkflow {
                try await $0.completeAppCaptureSubmission(scanID: scanID, submissionGeneration: submissionGeneration,
                    attemptGeneration: attemptGeneration, resultData: resultData, account: account, funding: funding)
            }
        }
    }
    func releaseAppCaptureSubmission(scanID: UUID, generation: UUID) async throws -> SharedMediaCaptureAcceptedRelease {
        try await withCapturePersistence(scanID: scanID) { [self] in
            try await captureRootWorkflow(requalify: true) { operations in
                let result = try await operations.releaseAppCaptureSubmission(scanID: scanID, generation: generation)
                return result
            }
        }
    }
    func captureCompletedRecoveryPage(after cursor: String? = nil) async throws -> SharedMediaCaptureCompletedRecovery.Page {
        try await captureRootWorkflow(requalify: true) { operations in
            let result = try await operations.captureCompletedRecoveryPage(after: cursor)
            return result
        }
    }
    func inspectCompletedAppCapture(_ candidate: SharedMediaCaptureCompletedRecovery.Candidate) async throws -> SharedMediaCaptureCompletedRecovery.Candidate {
        try await captureRootWorkflow(requalify: true) { operations in
            let current = try await operations.inspectCompletedAppCapture(candidate)
            return current
        }
    }
    func captureFundingRecoveryPage(after cursor: String? = nil) async throws -> SharedMediaCaptureFundingRecovery.Page {
        try await captureSettlementWorkflow { try await $0.captureFundingRecoveryPage(after: cursor) }
    }
    func captureExecutionRecoveryPage(after cursor: String? = nil) async throws -> SharedMediaCaptureExecutionRecovery.Page {
        try await captureSettlementWorkflow { try await $0.captureExecutionRecoveryPage(after: cursor) }
    }
    func capturePreparationFunding(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate) async throws -> ScanFundingReservation {
        try await withCapturePersistence(scanID: candidate.scanID) { [self] in
            try await captureSettlementWorkflow { try await $0.capturePreparationFunding(candidate) }
        }
    }
    func restoreCaptureAdmissionFunding() async throws {
        // The repository reads and restores this bounded snapshot without an
        // intervening suspension. It writes no scan row or dispatch state.
        try await captureSettlementWorkflow { try await $0.restoreCaptureAdmissionFunding() }
    }
    func captureFundingOwnership(_ reservation: ScanFundingReservation) async throws -> [String: SharedMediaCaptureFundingQualification.Entry] {
        try await captureSettlementWorkflow { try await $0.captureFundingOwnership(reservation) }
    }
    func resolveCaptureFunding(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate,
                               decision: CaptureDeferredFundingDecision,
                               requireEvidence: @escaping @MainActor () throws -> Void) async throws -> SharedMediaCaptureExecutionRecovery.Candidate {
        try await withCapturePersistence(scanID: candidate.scanID) { [self] in
            try await captureSettlementWorkflow {
                try await $0.resolveCaptureFunding(candidate, decision: decision, requireEvidence: requireEvidence)
            }
        }
    }
    func beginAppCaptureExecution(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate, now: Date) async throws -> SharedMediaCaptureExecutionRecovery.Candidate {
        try await withCapturePersistence(scanID: candidate.scanID) { [self] in
            try await captureSettlementWorkflow { try await $0.beginAppCaptureExecution(candidate, now: now) }
        }
    }
    func postponeAppCaptureExecution(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate, until due: Date) async throws -> SharedMediaCaptureExecutionRecovery.Candidate {
        try await withCapturePersistence(scanID: candidate.scanID) { [self] in
            try await captureSettlementWorkflow { try await $0.postponeAppCaptureExecution(candidate, until: due) }
        }
    }
    func reserveAppCaptureDispatch(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate) async throws -> SharedMediaCaptureExecutionRecovery.Candidate {
        try await withCapturePersistence(scanID: candidate.scanID) { [self] in
            try await captureSettlementWorkflow { try await $0.reserveAppCaptureDispatch(candidate) }
        }
    }
    func executeAppCapture(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate,
                           network: MerianNetworkClient, account: InferenceCompletionAccountScope) async throws -> SharedMediaCaptureResultWriter.Outcome {
        let funding = try SharedMediaCaptureFundingSettlement.Delivery(testOverride: nil)
        defer { funding.reconcileAfterPersistence() }
        return try await withCapturePersistence(scanID: candidate.scanID) { [self] in
            try await captureSettlementWorkflow {
                try await $0.executeAppCapture(candidate, network: network, account: account, funding: funding)
            }
        }
    }
    func postponeAppCaptureFunding(_ candidate: SharedMediaCaptureFundingRecovery.Candidate, until due: Date) async throws {
        try await withCapturePersistence(scanID: candidate.scanID) { [self] in
            try await captureSettlementWorkflow { try await $0.postponeAppCaptureFunding(candidate, until: due) }
        }
    }
    func recoverAppCaptureFunding(scanID: UUID, submissionGeneration: UUID, account: InferenceCompletionAccountScope,
                                  settleFunding: ((SharedMediaCaptureResultWriter.FundingHandoff) throws -> Void)? = nil) async throws {
        let funding = try SharedMediaCaptureFundingSettlement.Delivery(testOverride: settleFunding)
        defer { funding.reconcileAfterPersistence() }
        try await withCapturePersistence(scanID: scanID) { [self] in
            try await captureSettlementWorkflow {
                try await $0.recoverAppCaptureFunding(scanID: scanID, submissionGeneration: submissionGeneration,
                    account: account, funding: funding)
            }
        }
    }
    #if DEBUG
    func acceptAppCaptureSubmission(scanID: UUID, generation: UUID) async throws -> SharedMediaCaptureSubmissionAcceptance {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        return try await withCapturePersistence(scanID: scanID) { [self] in
            try await captureRootWorkflow {
                try await $0.acceptAppCaptureSubmission(scanID: scanID, generation: generation)
            }
        }
    }
    func reserveAppCaptureSubmission(_ plan: CaptureInitialEvidencePlan,
                                     context: SharedMediaCaptureSubmissionContext) async throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        return try await captureRootWorkflow { try await $0.reserveAppCaptureSubmission(plan, context: context) }
    }
    /// Qualification only until the whole-plan receipt can derive membership.
    /// Exact file custody is not a media-validity or submission capability.
    func materializeAppCaptureArtifact(_ input: SharedMediaCaptureArtifactInput, bytes: Data) async throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        return try await captureRootWorkflow { try await $0.materializeAppCaptureArtifact(input, bytes: bytes) }
    }
    #endif

    func saveAppCaptureDraftJournal(scanID: UUID, generation: UUID,
                                    replacing expected: SharedMediaCaptureDraftJournalReceipt.Snapshot?,
                                    sources: [SharedMediaCaptureDraftJournal.Source], items: [SharedMediaCaptureDraftJournal.Item],
                                    phase: SharedMediaCaptureDraftJournal.Phase = .editing) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        try await withCapturePersistence(scanID: scanID) { [self] in
            try await captureRootWorkflow(requalify: true) { operations in
                let saved = try await operations.saveAppCaptureDraftJournal(scanID: scanID, generation: generation,
                    replacing: expected, sources: sources, items: items, phase: phase)
                return saved
            }
        }
    }
    func readAppCaptureDraftJournal(scanID: UUID, generation: UUID) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot? {
        try await captureRootWorkflow { try await $0.readAppCaptureDraftJournal(scanID: scanID, generation: generation) }
    }

    func captureDraftJournalPage(after cursor: String? = nil) async throws -> SharedMediaCaptureDraftJournalRecovery.Page {
        try await captureRootWorkflow { try await $0.captureDraftJournalPage(after: cursor) }
    }

    func recoverReadyAppCaptureDraft(_ expected: SharedMediaCaptureDraftJournalReceipt.Snapshot) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        try await withCapturePersistence(scanID: expected.value.scanID) { [self] in
            try await captureRootWorkflow(requalify: true) { operations in
                let saved = try await operations.recoverReadyAppCaptureDraft(expected)
                return saved
            }
        }
    }

    func discardAppCaptureDraftItem(itemID: UUID, expected: SharedMediaCaptureDraftJournalReceipt.Snapshot) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        if requiresCaptureRecovery { try await resumeAppCaptureRoot() }
        guard isReadyForCaptureDraft else { throw SharedMediaStorageFailure.closed }
        return try await withCapturePersistence(scanID: expected.value.scanID) { [self] in
            try await captureRootWorkflow(requalify: true) { operations in
                let saved = try await operations.discardAppCaptureDraftItem(itemID: itemID, expected: expected)
                return saved
            }
        }
    }

    func capturePreparationAbortRecovery() async throws -> [SharedMediaCaptureAbortRecovery.Handle] {
        try await captureRootWorkflow { try await $0.capturePreparationAbortRecovery() }
    }

    func abortAppCapturePreparation(_ handle: SharedMediaCaptureAbortRecovery.Handle) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        try await withCapturePersistence(scanID: handle.scanID) { [self] in
            try await captureRootWorkflow(requalify: true) { operations in
                let saved = try await operations.abortAppCapturePreparation(handle)
                return saved
            }
        }
    }

    func abortAppCapturePreparation(_ expected: SharedMediaCaptureDraftJournalReceipt.Snapshot) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        try await withCapturePersistence(scanID: expected.value.scanID) { [self] in
            try await captureRootWorkflow(requalify: true) { operations in
                let saved = try await operations.abortAppCapturePreparation(expected)
                return saved
            }
        }
    }

    func materializeAppCaptureSource(_ input: SharedMediaCaptureDraftSourceInput, bytes: Data) async throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        try await withCapturePersistence(scanID: input.scanID) { [self] in
            try await captureRootWorkflow { try await $0.materializeAppCaptureSource(input, bytes: bytes) }
        }
    }
    func discardAppCaptureSource(_ input: SharedMediaCaptureDraftSourceInput) async throws {
        try await withCapturePersistence(scanID: input.scanID) { [self] in
            try await captureRootWorkflow(requalify: true) { operations in
                try await operations.discardAppCaptureSource(input)

            }
        }
    }
    func readAppCaptureSource(_ expected: SharedMediaCaptureDraftSourceInput) async throws -> Data {
        try await captureRootWorkflow { try await $0.readAppCaptureSource(expected) }
    }
    func captureDraftSourcePage(after cursor: String? = nil) async throws -> SharedMediaCaptureDraftSourceRecovery.Page {
        try await captureRootWorkflow { try await $0.captureDraftSourcePage(after: cursor) }
    }

    private func withCapturePersistence<T: Sendable>(scanID: UUID, _ body: @MainActor () async throws -> T) async throws -> T {
        let key = scanID.uuidString.lowercased()
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: key)
        do {
            try Task.checkCancellation()
            let value = try await body()
            await ScanInferencePersistenceCoordinator.shared.release(scanId: key)
            return value
        } catch {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: key)
            throw error
        }
    }

}
