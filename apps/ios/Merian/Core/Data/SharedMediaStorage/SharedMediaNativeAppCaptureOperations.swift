import Foundation
import SwiftData

/// Fixed Capture endpoints borrowed only while the repository holds the native
/// namespace. The private state never exposes files, grants or a repository.
/// The repository invalidates the authority when the invocation returns.
@MainActor
final class SharedMediaNativeAppCaptureOperations {
    struct Hooks {
        #if DEBUG
        var debug: SharedMediaNativeDebugHooks?
        #endif
    }
    /// Escaped endpoint objects do not retain the namespace or repository.
    private weak var borrow: Borrow?

    @MainActor
    private final class Borrow {
        let container: ModelContainer
        let capture: SharedMediaCaptureArtifactFiles
        let authority: SharedMediaNativeAppOperationAuthority
        let availableBytes: () throws -> Int64
        let qualifyRoot: () async throws -> Void
        let hooks: Hooks
        private var closed = false, running = false
        private var drain: CheckedContinuation<Void, Never>?
        var cancelEnteredWork: (() -> Void)?
        #if DEBUG
        var debug: SharedMediaNativeDebugHooks? { hooks.debug }
        #endif

        init(container: ModelContainer, capture: SharedMediaCaptureArtifactFiles,
             authority: SharedMediaNativeAppOperationAuthority,
             availableBytes: @escaping () throws -> Int64,
             qualifyRoot: @escaping () async throws -> Void, hooks: Hooks) {
            self.container = container; self.capture = capture; self.authority = authority
            self.availableBytes = availableBytes; self.qualifyRoot = qualifyRoot; self.hooks = hooks
        }
        func validate() throws {
            guard !closed else { throw SharedMediaStorageFailure.closed }
            _ = try authority.header(container); try capture.check()
        }
        func enter() throws {
            try validate()
            guard !running else { throw SharedMediaStorageFailure.busy }
            running = true
        }
        func leave() {
            cancelEnteredWork = nil; running = false; drain?.resume(); drain = nil
        }
        func close(revoke: () -> Void) async {
            closed = true; revoke(); cancelEnteredWork?()
            // Cancellation cannot release files while entered I/O still uses them.
            if running { await withCheckedContinuation { drain = $0 } }
        }
    }

    private init(_ borrow: Borrow) { self.borrow = borrow }

    static func withValidatedFiles<T: Sendable>(
        container: ModelContainer,
        capture: SharedMediaCaptureArtifactFiles, authority: SharedMediaNativeAppOperationAuthority,
        availableBytes: @escaping () throws -> Int64, qualifyRoot: @escaping () async throws -> Void,
        hooks: Hooks, revoke: () -> Void,
        body: @MainActor (SharedMediaNativeAppCaptureOperations) async throws -> T
    ) async throws -> T {
        let scope = Borrow(container: container, capture: capture, authority: authority,
            availableBytes: availableBytes, qualifyRoot: qualifyRoot, hooks: hooks)
        try scope.validate()
        let result: T
        do { result = try await body(.init(scope)) } catch {
            await scope.close(revoke: revoke); throw error
        }
        await scope.close(revoke: revoke)
        return result
    }

    private func withFiles<T: Sendable>(
        _ body: @escaping @MainActor (Borrow, SharedMediaCaptureArtifactFiles, SharedMediaNativeAppOperationAuthority) async throws -> T
    ) async throws -> T {
        guard let scope = borrow else { throw SharedMediaStorageFailure.closed }
        try scope.enter()
        defer { scope.leave() }
        let work = Task { @MainActor in
            try Task.checkCancellation()
            return try await body(scope, scope.capture, scope.authority)
        }
        scope.cancelEnteredWork = { work.cancel() }
        let result = try await withTaskCancellationHandler {
            try await work.value
        } onCancel: { work.cancel() }
        if work.isCancelled { throw CancellationError() }
        return result
    }
    func acceptAppCaptureDraft(plan: CaptureInitialEvidencePlan, context: SharedMediaCaptureSubmissionContext,
                               expectedJournal: SharedMediaCaptureDraftJournalReceipt.Snapshot? = nil,
                               readArtifact: @escaping SharedMediaCaptureDraftAcceptance.ReadArtifact) async throws -> SharedMediaCaptureSubmissionAcceptance {
        try await withFiles { scope, capture, authority in
            let read = ModelContext(scope.container); read.autosaveEnabled = false
            let format = SharedMediaCaptureSubmission.Format.v1.rawValue
            if try read.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(predicate: #Predicate { $0.formatRaw == format })) > 0
                || read.fetchCount(FetchDescriptor<SharedMediaOrdinaryArtifactRecord>()) > 0
                || read.fetchCount(FetchDescriptor<SharedMediaCaptureDraftJournalRecord>()) > 0 {
                _ = try SharedMediaCaptureDispatchQualification.pendingGenerations(container: scope.container,
                    profile: authority.profile, rootBindingSHA256: capture.rootBindingSHA256, checkpoint: { try scope.validate() })
            }
            return try await SharedMediaCaptureDraftAcceptance.accept(plan: plan, context: context,
                expectedJournal: expectedJournal,
                container: scope.container, authority: authority, files: capture, availableBytes: { try scope.availableBytes() },
                readArtifact: readArtifact, reservationBoundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSubmissionWriteFault?(point)
                    #endif
                }, artifactBoundary: { point in
                    #if DEBUG
                    try scope.debug?.captureArtifactWriteFault?(point)
                    #endif
                })
        }
    }
    func stageAppCaptureSubmission(scanID: UUID, generation: UUID, transport: CaptureStageTransport) async throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        try await withFiles { scope, capture, authority in
            // UploadWorker proves the exact accepted target before any network
            // request, while this same grant and namespace remain held.
            return try await SharedMediaCaptureUploadWorker.stage(scanID: scanID, generation: generation,
                container: scope.container, authority: authority, files: capture, transport: transport,
                availableBytes: { try scope.availableBytes() }, validateAttempt: { try scope.validate() }, qualifyRoot: {
                    try await scope.qualifyRoot()
                }, boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSubmissionWriteFault?(point)
                    #endif
                })
        }
    }
    func completeAppCaptureSubmission(scanID: UUID, submissionGeneration: UUID, attemptGeneration: UUID,
                                      resultData: Data, account: InferenceCompletionAccountScope,
                                      funding: SharedMediaCaptureFundingSettlement.Delivery) async throws -> SharedMediaCaptureResultWriter.Outcome {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureResultWriter.complete(scanID: scanID, submissionGeneration: submissionGeneration,
                attemptGeneration: attemptGeneration, resultData: resultData, account: account, container: scope.container,
                authority: authority, files: capture, availableBytes: { try scope.availableBytes() }, funding: funding, boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSubmissionWriteFault?(point)
                    #endif
                })
        }
    }
    func releaseAppCaptureSubmission(scanID: UUID, generation: UUID) async throws -> SharedMediaCaptureAcceptedRelease {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureAcceptedReleaseWriter.release(scanID: scanID, generation: generation,
                container: scope.container, authority: authority, files: capture, availableBytes: { try scope.availableBytes() },
                boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureAcceptedReleaseFault?(point)
                    #endif
                })
        }
    }
    func captureCompletedRecoveryPage(after cursor: String?) async throws -> SharedMediaCaptureCompletedRecovery.Page {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureCompletedRecovery.page(after: cursor, container: scope.container, authority: authority, files: capture)
        }
    }
    func inspectCompletedAppCapture(_ candidate: SharedMediaCaptureCompletedRecovery.Candidate) async throws -> SharedMediaCaptureCompletedRecovery.Candidate {
        try await withFiles { scope, capture, authority in
            try ConfirmedSpeciesReviewPersistence.transaction {
                let context = ModelContext(scope.container); context.autosaveEnabled = false
                return try SharedMediaCaptureCompletedRecovery.refresh(candidate, context: context, authority: authority, files: capture)
            }
        }
    }
    func captureFundingRecoveryPage(after cursor: String?) async throws -> SharedMediaCaptureFundingRecovery.Page {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureFundingRecovery.page(after: cursor, container: scope.container, authority: authority, files: capture)
        }
    }
    func captureExecutionRecoveryPage(after cursor: String?) async throws -> SharedMediaCaptureExecutionRecovery.Page {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureExecutionRecovery.page(after: cursor, container: scope.container, authority: authority, files: capture)
        }
    }
    func beginAppCaptureExecution(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate, now: Date) async throws -> SharedMediaCaptureExecutionRecovery.Candidate {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureExecutionRecovery.begin(candidate, now: now, container: scope.container,
                authority: authority, files: capture, boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSubmissionWriteFault?(point)
                    #endif
                })
        }
    }
    func capturePreparationFunding(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate) async throws -> ScanFundingReservation {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureExecutionRecovery.preparationFunding(candidate, container: scope.container,
                authority: authority, files: capture)
        }
    }
    func restoreCaptureAdmissionFunding() async throws {
        try await withFiles { scope, capture, authority in
            try SharedMediaCaptureFundingQualification.restore(container: scope.container, authority: authority, files: capture)
        }
    }
    func captureFundingOwnership(_ reservation: ScanFundingReservation) async throws -> [String: SharedMediaCaptureFundingQualification.Entry] {
        try await withFiles { scope, capture, authority in
            try SharedMediaCaptureFundingQualification.entries(Set(reservation.blockerScanIds + [reservation.scanId]),
                normalizing: reservation.scanId, container: scope.container, authority: authority, files: capture)
        }
    }
    func resolveCaptureFunding(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate,
                               decision: CaptureDeferredFundingDecision,
                               requireEvidence: @escaping @MainActor () throws -> Void) async throws -> SharedMediaCaptureExecutionRecovery.Candidate {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureExecutionRecovery.resolveFunding(candidate, decision: decision,
                requireEvidence: requireEvidence, container: scope.container, authority: authority, files: capture,
                boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSubmissionWriteFault?(point)
                    #endif
                })
        }
    }
    func postponeAppCaptureExecution(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate, until due: Date) async throws -> SharedMediaCaptureExecutionRecovery.Candidate {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureExecutionRecovery.postpone(candidate, until: due, container: scope.container,
                authority: authority, files: capture, boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSubmissionWriteFault?(point)
                    #endif
                })
        }
    }
    func reserveAppCaptureDispatch(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate) async throws -> SharedMediaCaptureExecutionRecovery.Candidate {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureExecutionRecovery.reserveDispatch(candidate, container: scope.container,
                authority: authority, files: capture, boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSubmissionWriteFault?(point)
                    #endif
                })
        }
    }
    /// The native root remains borrowed through request termination and local
    /// settlement. No SwiftData transaction remains open across the network.
    func executeAppCapture(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate,
                           network: MerianNetworkClient, account: InferenceCompletionAccountScope,
                           funding: SharedMediaCaptureFundingSettlement.Delivery) async throws -> SharedMediaCaptureResultWriter.Outcome {
        try await withFiles { scope, capture, authority in
            let saved = try await SharedMediaCaptureExecutionRecovery.ready(candidate, container: scope.container,
                authority: authority, files: capture)
            let plan = try saved.submission.plan()
            let validate: @MainActor @Sendable () throws -> Void = {
                try account.validate(); try scope.validate(); try capture.check()
                _ = try authority.header(scope.container)
            }
            let result: Data
            var dispatched = candidate
            if candidate.dispatch != nil {
                guard let recovered = try await network.captureCompletionTransport().recover(plan, validate: validate) else {
                    throw SharedMediaStorageFailure.unavailable
                }
                result = recovered
            } else {
                let request = try await network.buildPrivateCaptureRequest(plan: plan,
                    context: saved.submission.context, validateAttempt: validate)
                result = try await network.capturePrimaryTransport().submit(request, plan: plan, validate: validate) {
                    try validate()
                    guard try await SharedMediaCaptureExecutionRecovery.ready(candidate, container: scope.container,
                        authority: authority, files: capture) == saved else { throw SharedMediaStorageFailure.stale }
                    dispatched = try await SharedMediaCaptureExecutionRecovery.reserveDispatch(candidate,
                        container: scope.container, authority: authority, files: capture, boundary: { point in
                            #if DEBUG
                            try scope.debug?.captureSubmissionWriteFault?(point)
                            #endif
                        })
                    try validate()
                }
            }
            #if DEBUG
            try scope.debug?.captureExecutionResponseReceived?()
            #endif
            let claim = dispatched
            // Once a complete response wins, finish the same claim in a joined
            // settlement task. Dispatch cancellation does not cancel this task;
            // account/root replacement still invalidates every owning grant.
            let settlement = Task { @MainActor in
                try validate()
                guard try await SharedMediaCaptureExecutionRecovery.ready(claim, container: scope.container,
                    authority: authority, files: capture) == saved else { throw SharedMediaStorageFailure.stale }
                return try await SharedMediaCaptureResultWriter.complete(scanID: candidate.scanID,
                    submissionGeneration: candidate.generation, attemptGeneration: candidate.generation,
                    resultData: result, account: account, container: scope.container, authority: authority,
                    files: capture, availableBytes: { try scope.availableBytes() }, funding: funding,
                    boundary: { point in
                        #if DEBUG
                        try scope.debug?.captureSubmissionWriteFault?(point)
                        #endif
                    })
            }
            return try await settlement.value
        }
    }

    func postponeAppCaptureFunding(_ candidate: SharedMediaCaptureFundingRecovery.Candidate, until due: Date) async throws {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureFundingRecovery.postpone(candidate, until: due,
                container: scope.container, authority: authority, files: capture)
        }
    }
    func recoverAppCaptureFunding(scanID: UUID, submissionGeneration: UUID, account: InferenceCompletionAccountScope,
                                  funding: SharedMediaCaptureFundingSettlement.Delivery) async throws {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureResultWriter.recoverFunding(scanID: scanID, generation: submissionGeneration,
                account: account, container: scope.container, authority: authority, files: capture, funding: funding)
        }
    }
    func acceptAppCaptureSubmission(scanID: UUID, generation: UUID) async throws -> SharedMediaCaptureSubmissionAcceptance {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureAcceptance.accept(scanID: scanID, generation: generation,
                container: scope.container, authority: authority, files: capture,
                availableBytes: { try scope.availableBytes() }, boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSubmissionWriteFault?(point)
                    #endif
                })
        }
    }
    func reserveAppCaptureSubmission(_ plan: CaptureInitialEvidencePlan, context: SharedMediaCaptureSubmissionContext) async throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        return try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureSubmissionWriter.reserve(plan: plan, context: context, container: scope.container,
                authority: authority, files: capture, availableBytes: {
                    let actual = try scope.availableBytes()
                    #if DEBUG
                    return min(actual, scope.debug?.captureSubmissionAvailableBytes ?? actual)
                    #else
                    return actual
                    #endif
                }, boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSubmissionWriteFault?(point)
                    #endif
                })
        }
    }
    func saveAppCaptureDraftJournal(scanID: UUID, generation: UUID,
                                    replacing expected: SharedMediaCaptureDraftJournalReceipt.Snapshot?,
                                    sources: [SharedMediaCaptureDraftJournal.Source], items: [SharedMediaCaptureDraftJournal.Item],
                                    phase: SharedMediaCaptureDraftJournal.Phase) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        try await withFiles { scope, capture, authority in
            let value = SharedMediaCaptureDraftJournal(format: .v1, profile: authority.profile,
                rootBindingSHA256: capture.rootBindingSHA256, scanID: scanID, generation: generation,
                revision: expected.map { $0.value.revision + 1 } ?? 0, phase: phase, sources: sources, items: items,
                frozenObservation: nil, frozenContext: nil, abortedPreparations: expected?.value.abortedPreparations)
            return try await SharedMediaCaptureDraftJournalStore.saveEditing(value, replacing: expected,
                container: scope.container, authority: authority, files: capture, availableBytes: { try scope.availableBytes() },
                boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureDraftJournalFault?(point)
                    #endif
                })
        }
    }
    func readAppCaptureDraftJournal(scanID: UUID, generation: UUID) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot? {
        try await withFiles { scope, capture, authority in
            _ = try await SharedMediaCaptureBudget.evaluate(scope.container, authority: authority, files: capture)
            let context = ModelContext(scope.container); context.autosaveEnabled = false
            return try SharedMediaCaptureDraftJournalReceipt.matching(scanID: scanID, generation: generation, context: context)
        }
    }

    func discardAppCaptureDraftItem(itemID: UUID, expected: SharedMediaCaptureDraftJournalReceipt.Snapshot) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        try await withFiles { scope, capture, authority in
            let read = ModelContext(scope.container); read.autosaveEnabled = false
            let current = try SharedMediaCaptureDraftJournalReceipt.matching(scanID: expected.value.scanID,
                generation: expected.value.generation, context: read)
            if current == expected {
                let members = expected.value.sources.filter { $0.itemID == itemID }
                guard !members.isEmpty, members.allSatisfy({ $0.state == .discarding }) else { throw SharedMediaStorageFailure.closed }
                for member in members {
                    try await SharedMediaCaptureSourceDiscard.discard(member.input, container: scope.container,
                        authority: authority, files: capture)
                }
            }
            return try await SharedMediaCaptureDraftJournalStore.finishDiscard(itemID: itemID, expected: expected,
                container: scope.container, authority: authority, files: capture, availableBytes: { try scope.availableBytes() },
                boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureDraftJournalFault?(point)
                    #endif
                })
        }
    }

    func capturePreparationAbortRecovery() async throws -> [SharedMediaCaptureAbortRecovery.Handle] {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureAbortRecovery.discover(container: scope.container, authority: authority, files: capture)
        }
    }

    func abortAppCapturePreparation(_ handle: SharedMediaCaptureAbortRecovery.Handle) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        let expected = SharedMediaCaptureAbortRecovery.expected(handle)
        return try await abortAppCapturePreparation(expected)
    }

    func abortAppCapturePreparation(_ expected: SharedMediaCaptureDraftJournalReceipt.Snapshot) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCapturePreparationAbort.abort(expected, container: scope.container,
                authority: authority, files: capture, availableBytes: { try scope.availableBytes() },
                journalBoundary: { point in
                    #if DEBUG
                    try scope.debug?.captureDraftJournalFault?(point)
                    #endif
                }, artifactBoundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSourceDiscardFault?(point)
                    #endif
                })
        }
    }

    func captureDraftJournalPage(after cursor: String?) async throws -> SharedMediaCaptureDraftJournalRecovery.Page {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureDraftJournalRecovery.page(after: cursor, container: scope.container,
                authority: authority, files: capture)
        }
    }

    func recoverReadyAppCaptureDraft(_ expected: SharedMediaCaptureDraftJournalReceipt.Snapshot) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureDraftJournalRecovery.recoverReady(expected, container: scope.container,
                authority: authority, files: capture, availableBytes: { try scope.availableBytes() },
                boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureDraftJournalFault?(point)
                    #endif
                })
        }
    }

    func materializeAppCaptureSource(_ input: SharedMediaCaptureDraftSourceInput, bytes: Data) async throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        try await withFiles { scope, capture, authority in
            #if DEBUG
            capture.afterWriteChunk = scope.debug?.captureArtifactWritePause
            #endif
            return try await SharedMediaCaptureArtifactWriter.materializeSource(input, bytes: bytes,
                container: scope.container, authority: authority, files: capture,
                availableBytes: { try scope.availableBytes() }, boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureArtifactWriteFault?(point)
                    #endif
                })
        }
    }
    func discardAppCaptureSource(_ input: SharedMediaCaptureDraftSourceInput) async throws {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureSourceDiscard.discard(input, container: scope.container,
                authority: authority, files: capture, boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureSourceDiscardFault?(point)
                    #endif
                })
        }
    }
    func readAppCaptureSource(_ expected: SharedMediaCaptureDraftSourceInput) async throws -> Data {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureDraftSourceRecovery.read(expected, container: scope.container,
                authority: authority, files: capture)
        }
    }
    func captureDraftSourcePage(after cursor: String?) async throws -> SharedMediaCaptureDraftSourceRecovery.Page {
        try await withFiles { scope, capture, authority in
            try await SharedMediaCaptureDraftSourceRecovery.page(after: cursor, container: scope.container,
                authority: authority, files: capture)
        }
    }
    func materializeAppCaptureArtifact(_ input: SharedMediaCaptureArtifactInput, bytes: Data) async throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        return try await withFiles { scope, capture, authority in
            #if DEBUG
            capture.afterWriteChunk = scope.debug?.captureArtifactWritePause
            #endif
            return try await SharedMediaCaptureArtifactWriter.materialize(input, bytes: bytes, container: scope.container,
                authority: authority, files: capture, availableBytes: { try scope.availableBytes() }, boundary: { point in
                    #if DEBUG
                    try scope.debug?.captureArtifactWriteFault?(point)
                    #endif
                })
        }
    }
}
