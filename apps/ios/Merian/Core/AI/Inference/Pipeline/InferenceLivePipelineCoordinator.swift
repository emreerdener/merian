import Foundation
import SwiftData

/// Executes one exact live visual or nonvisual inference session.
///
/// The coordinator owns admission, suspension fences, provider/result order,
/// durable finalization, and failure dispatch. It emits narrow callbacks for
/// the presentation state behind the engine facade and contains no live
/// singleton resolution.
@MainActor
final class InferenceLivePipelineCoordinator {
    struct Dependencies {
        let isCircuitTripped: @MainActor () -> Bool
        let refundScan: @MainActor (String) -> Void
        let logAdmission: @MainActor (AdmissionIssue, Modality) -> Void
        let logEmptyVisualEncoding: @MainActor () -> Void
        let logBenchmark: @MainActor (Benchmark) -> Void
    }

    private let attemptCoordinator: InferenceLiveAttemptCoordinator
    private let requestService: InferenceLiveRequestService
    private let resultService: InferenceLiveResultService
    private let completionCoordinator: InferenceLiveCompletionCoordinator
    private let failureCoordinator: InferenceLiveFailureCoordinator
    private let dependencies: Dependencies

    init(
        attemptCoordinator: InferenceLiveAttemptCoordinator,
        requestService: InferenceLiveRequestService,
        resultService: InferenceLiveResultService,
        completionCoordinator: InferenceLiveCompletionCoordinator,
        failureCoordinator: InferenceLiveFailureCoordinator,
        dependencies: Dependencies
    ) {
        self.attemptCoordinator = attemptCoordinator
        self.requestService = requestService
        self.resultService = resultService
        self.completionCoordinator = completionCoordinator
        self.failureCoordinator = failureCoordinator
        self.dependencies = dependencies
    }

    /// Validates and claims the durable foreground tuple before any existing
    /// local attempt is displaced. Queue-less calls receive a process-local
    /// identity while keeping their provider `clientScanId` behavior intact.
    func admit(
        scanId: String?,
        foregroundGeneration: UUID?,
        modality: Modality
    ) -> Session? {
        var isProFunded = false
        if let scanId {
            guard let foregroundGeneration else {
                dependencies.logAdmission(
                    .missingForegroundOwner(scanId: scanId),
                    modality
                )
                return nil
            }
            guard !attemptCoordinator.isDuplicateActiveForegroundAttempt(
                scanId: scanId,
                generation: foregroundGeneration
            ) else {
                dependencies.logAdmission(
                    .duplicateForegroundOwner(scanId: scanId),
                    modality
                )
                return nil
            }
            guard attemptCoordinator.claimForegroundInferenceStart(
                scanId: scanId,
                generation: foregroundGeneration
            ) else {
                dependencies.logAdmission(
                    .unavailableForegroundOwner(scanId: scanId),
                    modality
                )
                return nil
            }
            isProFunded = attemptCoordinator.isForegroundInferenceProFunded(
                scanId: scanId,
                generation: foregroundGeneration
            )
        } else if foregroundGeneration != nil {
            dependencies.logAdmission(.foregroundOwnerWithoutScan, modality)
            return nil
        }

        return Session(
            scanId: scanId,
            resolvedClientScanId:
                scanId ?? UUID().uuidString.lowercased(),
            attemptGeneration: foregroundGeneration ?? UUID(),
            foregroundGeneration: foregroundGeneration,
            modality: modality,
            isProFunded: isProFunded
        )
    }

    func activate(_ session: Session) {
        attemptCoordinator.activate(
            scanId: session.scanId,
            attemptGeneration: session.attemptGeneration,
            foregroundGeneration: session.foregroundGeneration
        )
    }

    func recordBenchmark(_ benchmark: Benchmark) {
        dependencies.logBenchmark(benchmark)
    }

    func executeVisual(
        _ request: VisualRequest,
        callbacks: VisualCallbacks
    ) async {
        let session = request.session
        let pipelineStartedAt = CFAbsoluteTimeGetCurrent()
        defer { finish(session, callback: callbacks.shared.finish) }

        do {
            try check(session)
            try checkCircuit()

            let durableAttemptCoordinator = attemptCoordinator
            let markRequestBodySent = callbacks.markRequestBodySent
            var uploadFailSafe: Task<Void, Never>?
            defer { uploadFailSafe?.cancel() }

            let requestResponse = try await requestService.dispatchVisual(
                InferenceLiveRequestService.VisualRequest(
                    compressedImages: request.compressedImages,
                    submissionProjection: request.submissionProjection,
                    ownerMediaTimeline: request.ownerMediaTimeline,
                    visualMediaItems: request.visualMediaItems,
                    telemetry: request.telemetry,
                    clientScanId: session.resolvedClientScanId,
                    preferredGoal: request.preferredGoal,
                    durableQueueOwnsRecovery:
                        session.durableQueueOwnsRecovery,
                    pipelineStartedAt: pipelineStartedAt,
                    isProFunded: session.isProFunded
                ),
                validateAttempt: { try self.check(session) },
                onProviderDispatchReady: {
                    uploadFailSafe = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        durableAttemptCoordinator.releaseDeferredUpload(
                            scanId: session.resolvedClientScanId,
                            foregroundGeneration:
                                session.foregroundGeneration,
                            reason: "inline_upload_two_second_failsafe"
                        )
                    }
                },
                onRequestBodySent: {
                    Task { @MainActor in
                        durableAttemptCoordinator.releaseDeferredUpload(
                            scanId: session.resolvedClientScanId,
                            foregroundGeneration:
                                session.foregroundGeneration,
                            reason: "inline_request_body_sent"
                        )
                        markRequestBodySent(session)
                    }
                }
            )
            guard let requestResponse else {
                handleEmptyVisualEncoding(session)
                return
            }

            callbacks.cancelLocalAnalysis()
            let postFlightStartedAt = CFAbsoluteTimeGetCurrent()
            guard let completion = try await processResult(
                InferenceLiveResultService.Request(
                    response: requestResponse,
                    telemetry: request.telemetry,
                    media: .visual(
                        compressedImages: request.compressedImages,
                        displayImages: request.displayImages
                    ),
                    mediaTimeline: request.mediaTimeline,
                    submissionProjection: request.submissionProjection,
                    modelContext: request.modelContext,
                    persistenceFence: session.persistenceFence,
                    expectedScanId: session.resolvedClientScanId
                ),
                session: session,
                targetEradicationScanId:
                    request.targetEradicationScanId,
                modelContext: request.modelContext
            ) else {
                return
            }

            let didCommitResult = callbacks.shared.publishCompletion(
                completion
            )
            let stateCommittedAt = CFAbsoluteTimeGetCurrent()
            dependencies.logBenchmark(
                .responseToFirstResult(
                    stateCommittedAt - requestResponse.receivedAt
                )
            )

            let followUpPermit:
                InferenceLiveCompletionCoordinator.FollowUpPermit? =
                if didCommitResult {
                    await completionCoordinator
                        .finalizeQueueAndAuthorizeFollowUps(
                            scanId: session.scanId,
                            attemptGeneration: session.attemptGeneration,
                            foregroundGeneration: session.foregroundGeneration,
                            mediaPathsToKeep: completion.mediaPathsToKeep,
                            speciesData: completion.speciesData,
                            modelContainer: request.modelContext?.container,
                            fundingSettlement: completion.fundingSettlement
                        )
                } else {
                    nil
                }
            if let followUpPermit {
                completionCoordinator.commitFundingSettlement(followUpPermit)
                completionCoordinator.sendNotificationIfEnabled(
                    followUpPermit
                )
            }

            dependencies.logBenchmark(
                .postFlight(
                    CFAbsoluteTimeGetCurrent() - postFlightStartedAt
                )
            )
            dependencies.logBenchmark(
                .total(CFAbsoluteTimeGetCurrent() - pipelineStartedAt)
            )

            if let followUpPermit {
                callbacks.shared.scheduleHydration(
                    followUpPermit.speciesData
                )
                completionCoordinator.scheduleMilestones(followUpPermit)
            }
        } catch {
            handleFailure(
                error,
                session: session,
                telemetry: request.telemetry,
                applyPresentation: callbacks.shared.applyFailure
            )
        }
    }

    func executeNonVisual(
        _ request: NonVisualRequest,
        callbacks: Callbacks
    ) async {
        let session = request.session
        let pipelineStartedAt = CFAbsoluteTimeGetCurrent()
        defer { finish(session, callback: callbacks.finish) }

        do {
            try check(session)
            try checkCircuit()

            let requestResponse = try await requestService.dispatchNonVisual(
                InferenceLiveRequestService.NonVisualRequest(
                    submissionProjection: request.submissionProjection,
                    ownerMediaTimeline: request.ownerMediaTimeline,
                    telemetry: request.telemetry,
                    clientScanId: session.scanId,
                    durableQueueOwnsRecovery:
                        session.durableQueueOwnsRecovery,
                    isProFunded: session.isProFunded
                ),
                validateAttempt: { try self.check(session) }
            )
            let postFlightStartedAt = CFAbsoluteTimeGetCurrent()
            guard let completion = try await processResult(
                InferenceLiveResultService.Request(
                    response: requestResponse,
                    telemetry: request.telemetry,
                    media: .nonVisual,
                    mediaTimeline: request.mediaTimeline,
                    submissionProjection: request.submissionProjection,
                    modelContext: request.modelContext,
                    persistenceFence: session.persistenceFence,
                    expectedScanId: session.scanId
                ),
                session: session,
                targetEradicationScanId:
                    request.targetEradicationScanId,
                modelContext: request.modelContext
            ) else {
                return
            }

            let didCommitResult = callbacks.publishCompletion(completion)
            let stateCommittedAt = CFAbsoluteTimeGetCurrent()
            dependencies.logBenchmark(
                .responseToFirstResult(
                    stateCommittedAt - requestResponse.receivedAt
                )
            )
            dependencies.logBenchmark(
                .postFlight(stateCommittedAt - postFlightStartedAt)
            )
            dependencies.logBenchmark(
                .total(stateCommittedAt - pipelineStartedAt)
            )

            let followUpPermit: InferenceLiveCompletionCoordinator
                .FollowUpPermit?
            if !didCommitResult {
                followUpPermit = nil
            } else if session.durableQueueOwnsRecovery {
                followUpPermit = await completionCoordinator
                    .finalizeQueueAndAuthorizeFollowUps(
                        scanId: session.scanId,
                        attemptGeneration: session.attemptGeneration,
                        foregroundGeneration: session.foregroundGeneration,
                        mediaPathsToKeep: completion.mediaPathsToKeep,
                        speciesData: completion.speciesData,
                        modelContainer: request.modelContext?.container,
                        fundingSettlement: completion.fundingSettlement
                    )
            } else {
                // Queue-less discovery has no durable queue transition to
                // await. Keep authorization synchronous so another main-actor
                // attempt cannot replace this exact owner between commit and
                // follow-up fencing.
                followUpPermit = completionCoordinator
                    .authorizeQueueLessFollowUps(
                        scanId: session.scanId,
                        attemptGeneration: session.attemptGeneration,
                        speciesData: completion.speciesData,
                        modelContainer: request.modelContext?.container,
                        fundingSettlement: completion.fundingSettlement
                    )
            }
            if let followUpPermit {
                completionCoordinator.commitFundingSettlement(followUpPermit)
                completionCoordinator.scheduleMilestones(followUpPermit)
                if let persistence = completion.comparisonPersistence {
                    completion.comparisonCapture?.finalize(
                        scanId: completion.speciesData.scanId,
                        confidenceScore: completion.speciesData.confidenceScore,
                        isBiological: completion.speciesData.isBiological,
                        persistence: persistence,
                        species: completion.speciesData
                    )
                }
                completionCoordinator.sendNotificationIfEnabled(
                    followUpPermit
                )
                callbacks.scheduleHydration(followUpPermit.speciesData)
            }
        } catch {
            handleFailure(
                error,
                session: session,
                telemetry: request.telemetry,
                applyPresentation: callbacks.applyFailure
            )
        }
    }

    private func check(_ session: Session) throws {
        try attemptCoordinator.checkAttempt(
            scanId: session.scanId,
            attemptGeneration: session.attemptGeneration,
            foregroundGeneration: session.foregroundGeneration
        )
    }

    private func checkCircuit() throws {
        if dependencies.isCircuitTripped() {
            throw URLError(.notConnectedToInternet)
        }
    }

    private func processResult(
        _ request: InferenceLiveResultService.Request,
        session: Session,
        targetEradicationScanId: String?,
        modelContext: ModelContext?
    ) async throws -> InferenceLiveCompletionCoordinator.PreparedCompletion? {
        let outcome = try await resultService.process(
            request,
            validateAttempt: { try self.check(session) }
        )
        guard var completion = completionCoordinator.prepare(
            outcome: outcome,
            targetEradicationScanId: targetEradicationScanId,
            modelContext: modelContext
        ) else {
            attemptCoordinator.retireForegroundInferenceIfCurrent(
                scanId: session.scanId,
                attemptGeneration: session.attemptGeneration,
                foregroundGeneration: session.foregroundGeneration,
                resumeBackground: true,
                reason: session.modality.persistenceRejectionReason
            )
            return nil
        }
        if session.durableQueueOwnsRecovery, modelContext != nil {
            completion.comparisonCapture = request.response.comparisonCapture
            switch outcome {
            case .persisted: completion.comparisonPersistence = .saved
            case .completedWithoutRecord: completion.comparisonPersistence = .completedWithoutRecord
            case .persistenceRejected: break
            }
        }
        return completion
    }

    private func handleEmptyVisualEncoding(_ session: Session) {
        dependencies.logEmptyVisualEncoding()
        dependencies.refundScan(session.resolvedClientScanId)
        attemptCoordinator.releaseDeferredUpload(
            scanId: session.resolvedClientScanId,
            foregroundGeneration: session.foregroundGeneration,
            reason: "live_visual_encoding_empty"
        )
        attemptCoordinator.retireForegroundInferenceIfCurrent(
            scanId: session.scanId,
            attemptGeneration: session.attemptGeneration,
            foregroundGeneration: session.foregroundGeneration,
            resumeBackground: true,
            reason: "live_visual_encoding_empty"
        )
    }

    private func handleFailure(
        _ error: Error,
        session: Session,
        telemetry: CaptureTelemetry,
        applyPresentation:
            (InferenceLiveFailureCoordinator.PresentationAction) -> Void
    ) {
        failureCoordinator.handle(
            error,
            mode: session.modality.failureMode,
            scanId: session.scanId,
            resolvedClientScanId: session.resolvedClientScanId,
            attemptGeneration: session.attemptGeneration,
            foregroundGeneration: session.foregroundGeneration,
            telemetry: telemetry,
            isTaskCancelled: Task.isCancelled,
            applyPresentation: applyPresentation
        )
    }

    private func finish(
        _ session: Session,
        callback: (Session) -> Void
    ) {
        guard attemptCoordinator.clearActiveAttemptIfCurrent(
            scanId: session.scanId,
            attemptGeneration: session.attemptGeneration
        ) else {
            return
        }
        callback(session)
    }
}
