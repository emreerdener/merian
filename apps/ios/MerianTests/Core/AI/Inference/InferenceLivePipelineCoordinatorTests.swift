import Foundation
import Testing

@testable import Merian

/// Shared deterministic fixture for the focused pipeline execution suites.
@MainActor
final class InferenceLivePipelineHarness {
    enum Event: Equatable {
        case claim(String, UUID)
        case admission(
            InferenceLivePipelineCoordinator.AdmissionIssue,
            InferenceLivePipelineCoordinator.Modality
        )
        case circuitCheck
        case encode
        case identify
        case parse
        case emptyEncoding
        case refund(String)
        case release(String, UUID?, String)
        case retire(String, UUID, String)
        case delete(String, UUID)
        case completionPrepared
        case completionCircuitSuccess
        case completionTelemetry
        case commit
        case benchmark(String)
        case milestone
        case notificationPreferenceRead
        case notification
        case hydration
        case localAnalysisCancelled
        case requestBodySent
        case finish(UUID)
        case failureTelemetry
        case failureCircuit
        case failureFeedback
        case failurePresentation
    }

    var claimResult = true
    var circuitIsTripped = false
    var encodedImages = ["encoded-image"]
    var commitResult = true
    var sendsRequestBodyCallback = true
    var parsedResult: InferenceProcessingActor.ParseAndSaveResult
    var parseOperation:
        (@MainActor () async throws
            -> InferenceProcessingActor.ParseAndSaveResult)?
    private(set) var events: [Event] = []

    init() {
        parsedResult = Self.makeParsedResult()
    }

    func resetEvents() {
        events = []
    }

    func makeSystem(
        queueService: InferenceLiveQueueService? = nil,
        requestService: InferenceLiveRequestService? = nil,
        resultService: InferenceLiveResultService? = nil
    ) -> (
        pipeline: InferenceLivePipelineCoordinator,
        attempt: InferenceLiveAttemptCoordinator
    ) {
        let queue = InferenceLiveQueueService(dependencies: .init(
            releaseDeferredUpload: { [self] scanId, generation, reason in
                events.append(.release(scanId, generation, reason))
            },
            retireForegroundInference: { [self] scanId, generation, _, reason in
                events.append(.retire(scanId, generation, reason))
            },
            claimForegroundInferenceStart: { [self] scanId, generation in
                events.append(.claim(scanId, generation))
                return claimResult
            },
            isForegroundInferenceAttemptCurrent: { _, _ in true },
            foregroundInferenceGeneration: { _ in nil },
            deleteQueuedScan: { [self] scanId, _, generation in
                events.append(.delete(scanId, generation))
                return true
            },
            rejectQueuedScan: { _, _, _ in true }
        ))
        let attempt = InferenceLiveAttemptCoordinator(queueService: queueService ?? queue)
        let request = InferenceLiveRequestService(dependencies: .init(
            encodeVisualImages: { [self] _ in
                events.append(.encode)
                return encodedImages
            },
            uploadStagedVideoFiles: { _, _ in [] },
            identify: { [self] _, onRequestBodySent in
                events.append(.identify)
                if sendsRequestBodyCallback {
                    onRequestBodySent?()
                }
                return Data("provider-response".utf8)
            }
        ))
        let result = InferenceLiveResultService(dependencies: .init(
            parseAndSave: { [self] _ in
                events.append(.parse)
                if let parseOperation {
                    return try await parseOperation()
                }
                return parsedResult
            }
        ))
        let completion = InferenceLiveCompletionCoordinator(
            attemptCoordinator: attempt,
            dependencies: .init(
                recordNewSpeciesDiscovered: {},
                transferReplacementMetadataAndDeleteOriginal: { [self] _, _, _ in
                    events.append(.completionPrepared)
                },
                recordCircuitSuccess: { [self] in
                    events.append(.completionCircuitSuccess)
                },
                trackCompletedScan: { [self] _, _ in
                    events.append(.completionTelemetry)
                },
                sendEvent: { _ in },
                notificationsEnabled: { [self] in
                    events.append(.notificationPreferenceRead)
                    return true
                },
                sendInferenceCompleteNotification: { [self] _, _ in
                    events.append(.notification)
                },
                scheduleMilestoneProcessing: { [self] _, _, _ in
                    events.append(.milestone)
                },
                commitFundingSettlement: { _ in true }
            )
        )
        let failure = InferenceLiveFailureCoordinator(
            attemptCoordinator: attempt,
            dependencies: .init(
                trackError: { [self] _ in
                    events.append(.failureTelemetry)
                },
                recordCircuitFailure: { [self] in
                    events.append(.failureCircuit)
                },
                requestPaywall: {},
                triggerErrorFeedback: { [self] in
                    events.append(.failureFeedback)
                },
                logFailure: { _, _, _, _ in },
                logQueueHandoff: {}
            )
        )
        let pipeline = InferenceLivePipelineCoordinator(
            attemptCoordinator: attempt,
            requestService: requestService ?? request,
            resultService: resultService ?? result,
            completionCoordinator: completion,
            failureCoordinator: failure,
            dependencies: .init(
                isCircuitTripped: { [self] in
                    events.append(.circuitCheck)
                    return circuitIsTripped
                },
                refundScan: { [self] scanId in
                    events.append(.refund(scanId))
                },
                logAdmission: { [self] issue, modality in
                    events.append(.admission(issue, modality))
                },
                logEmptyVisualEncoding: { [self] in
                    events.append(.emptyEncoding)
                },
                logBenchmark: { [self] benchmark in
                    events.append(.benchmark(Self.label(for: benchmark)))
                }
            )
        )
        return (pipeline, attempt)
    }

    func callbacks() -> InferenceLivePipelineCoordinator.Callbacks {
        .init(
            finish: { [self] session in
                events.append(.finish(session.attemptGeneration))
            },
            publishCompletion: { [self] _ in
                events.append(.commit)
                return commitResult
            },
            scheduleHydration: { [self] _ in
                events.append(.hydration)
            },
            applyFailure: { [self] action in
                if case .publishFailure = action {
                    events.append(.failurePresentation)
                }
            }
        )
    }

    func visualCallbacks() -> InferenceLivePipelineCoordinator.VisualCallbacks {
        .init(
            shared: callbacks(),
            cancelLocalAnalysis: { [self] in
                events.append(.localAnalysisCancelled)
            },
            markRequestBodySent: { [self] _ in
                events.append(.requestBodySent)
            }
        )
    }

    func visualRequest(
        session: InferenceLivePipelineCoordinator.Session
    ) -> InferenceLivePipelineCoordinator.VisualRequest {
        let timeline: [CaptureSubmissionMediaItem] = [.image(index: 0)]
        return .init(
            session: session,
            compressedImages: [Data([0x01])],
            displayImages: [Data([0x11])],
            submissionProjection: timeline.submissionMediaProjection,
            ownerMediaTimeline: nil,
            mediaTimeline: timeline,
            visualMediaItems: [.image(sourceIndex: 0)],
            telemetry: Self.telemetry,
            preferredGoal: nil,
            modelContext: nil,
            targetEradicationScanId: nil
        )
    }

    func nonVisualRequest(
        session: InferenceLivePipelineCoordinator.Session
    ) -> InferenceLivePipelineCoordinator.NonVisualRequest {
        let timeline: [CaptureSubmissionMediaItem] = [
            .description(ObservationContext(freeText: "three clear notes"))
        ]
        return .init(
            session: session,
            submissionProjection: timeline.submissionMediaProjection,
            ownerMediaTimeline: nil,
            mediaTimeline: timeline,
            telemetry: Self.telemetry,
            modelContext: nil,
            targetEradicationScanId: nil
        )
    }

    private static func label(
        for benchmark: InferenceLivePipelineCoordinator.Benchmark
    ) -> String {
        switch benchmark {
        case .tapToFirstRenderedFrame:
            "first-render"
        case .responseToFirstResult:
            "response"
        case .postFlight:
            "postflight"
        case .total:
            "total"
        }
    }

    private static func makeParsedResult()
        -> InferenceProcessingActor.ParseAndSaveResult {
        .init(
            mappedData: SpeciesData(
                scanId: "result-scan",
                commonName: "Test subject",
                scientificName: "Test species",
                insightData: InsightData(
                    aiReasoning: "Test observation",
                    hazardType: "none"
                ),
                confidenceScore: 0.95,
                isBiological: true,
                inferenceTier: "pro"
            ),
            isNewDiscovery: false,
            savedPaths: ["saved-image.jpg"],
            planUsed: "pro",
            didCompletePersistence: true
        )
    }

    private static var telemetry: CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: "2026-09-13T12:00:00Z",
            zoomFactor: nil,
            estimatedSizeCm: nil
        )
    }
}

@MainActor
@Suite("Inference Live Pipeline Coordinator")
struct InferenceLivePipelineCoordinatorTests {
    @Test func admissionRejectsIncompleteUnavailableAndDuplicateOwners() throws {
        let harness = InferenceLivePipelineHarness()
        let system = harness.makeSystem()
        let generation = UUID()

        #expect(
            system.pipeline.admit(
                scanId: "scan-a",
                foregroundGeneration: nil,
                modality: .visual
            ) == nil
        )
        #expect(
            system.pipeline.admit(
                scanId: nil,
                foregroundGeneration: generation,
                modality: .nonVisual(hasAudio: true)
            ) == nil
        )
        harness.claimResult = false
        #expect(
            system.pipeline.admit(
                scanId: "scan-b",
                foregroundGeneration: generation,
                modality: .visual
            ) == nil
        )
        #expect(harness.events == [
            .admission(
                .missingForegroundOwner(scanId: "scan-a"),
                .visual
            ),
            .admission(
                .foregroundOwnerWithoutScan,
                .nonVisual(hasAudio: true)
            ),
            .claim("scan-b", generation),
            .admission(
                .unavailableForegroundOwner(scanId: "scan-b"),
                .visual
            )
        ])

        harness.claimResult = true
        harness.resetEvents()
        let session = try #require(system.pipeline.admit(
            scanId: "scan-c",
            foregroundGeneration: generation,
            modality: .visual
        ))
        system.pipeline.activate(session)
        harness.resetEvents()

        #expect(
            system.pipeline.admit(
                scanId: "scan-c",
                foregroundGeneration: generation,
                modality: .visual
            ) == nil
        )
        #expect(harness.events == [
            .admission(
                .duplicateForegroundOwner(scanId: "scan-c"),
                .visual
            )
        ])
    }

    @Test func emptyVisualEncodingRefundsAndRetiresExactOwnerInOrder() async throws {
        let harness = InferenceLivePipelineHarness()
        harness.encodedImages = [""]
        let system = harness.makeSystem()
        let generation = UUID()
        let session = try #require(system.pipeline.admit(
            scanId: "scan-a",
            foregroundGeneration: generation,
            modality: .visual
        ))
        system.pipeline.activate(session)
        harness.resetEvents()

        await system.pipeline.executeVisual(
            harness.visualRequest(session: session),
            callbacks: harness.visualCallbacks()
        )

        #expect(harness.events == [
            .circuitCheck,
            .encode,
            .emptyEncoding,
            .refund("scan-a"),
            .release(
                "scan-a",
                generation,
                "live_visual_encoding_empty"
            ),
            .retire("scan-a", generation, "live_visual_encoding_empty"),
            .finish(session.attemptGeneration)
        ])
        #expect(system.attempt.activeScanId == nil)
        #expect(system.attempt.activeAttemptGeneration == nil)
    }

    @Test func queueLessNonvisualSuccessPreservesReviewedFollowUpOrder() async throws {
        let harness = InferenceLivePipelineHarness()
        let system = harness.makeSystem()
        let session = try #require(system.pipeline.admit(
            scanId: nil,
            foregroundGeneration: nil,
            modality: .nonVisual(hasAudio: false)
        ))
        system.pipeline.activate(session)

        await system.pipeline.executeNonVisual(
            harness.nonVisualRequest(session: session),
            callbacks: harness.callbacks()
        )

        #expect(harness.events == [
            .circuitCheck,
            .identify,
            .parse,
            .completionPrepared,
            .completionCircuitSuccess,
            .completionTelemetry,
            .commit,
            .benchmark("response"),
            .benchmark("postflight"),
            .benchmark("total"),
            .milestone,
            .notificationPreferenceRead,
            .notification,
            .hydration,
            .finish(session.attemptGeneration)
        ])
    }

    @Test func queueLessVisualSuccessPreservesReviewedFollowUpOrder() async throws {
        let harness = InferenceLivePipelineHarness()
        harness.sendsRequestBodyCallback = false
        let system = harness.makeSystem()
        let session = try #require(system.pipeline.admit(
            scanId: nil,
            foregroundGeneration: nil,
            modality: .visual
        ))
        system.pipeline.activate(session)

        await system.pipeline.executeVisual(
            harness.visualRequest(session: session),
            callbacks: harness.visualCallbacks()
        )

        #expect(harness.events == [
            .circuitCheck,
            .encode,
            .identify,
            .localAnalysisCancelled,
            .parse,
            .completionPrepared,
            .completionCircuitSuccess,
            .completionTelemetry,
            .commit,
            .benchmark("response"),
            .notificationPreferenceRead,
            .notification,
            .benchmark("postflight"),
            .benchmark("total"),
            .hydration,
            .milestone,
            .finish(session.attemptGeneration)
        ])
    }

    @Test func durableNonvisualSuccessFinalizesBeforeFollowUps() async throws {
        let harness = InferenceLivePipelineHarness()
        let system = harness.makeSystem()
        let generation = UUID()
        let session = try #require(system.pipeline.admit(
            scanId: "scan-a",
            foregroundGeneration: generation,
            modality: .nonVisual(hasAudio: false)
        ))
        system.pipeline.activate(session)
        harness.resetEvents()

        await system.pipeline.executeNonVisual(
            harness.nonVisualRequest(session: session),
            callbacks: harness.callbacks()
        )

        #expect(harness.events == [
            .circuitCheck,
            .identify,
            .parse,
            .completionPrepared,
            .completionCircuitSuccess,
            .completionTelemetry,
            .commit,
            .benchmark("response"),
            .benchmark("postflight"),
            .benchmark("total"),
            .delete("scan-a", generation),
            .milestone,
            .notificationPreferenceRead,
            .notification,
            .hydration,
            .finish(session.attemptGeneration)
        ])
        #expect(system.attempt.activeForegroundGeneration == nil)
    }

    @Test func circuitGateRoutesThroughFailureCoordinator() async throws {
        let harness = InferenceLivePipelineHarness()
        harness.circuitIsTripped = true
        let system = harness.makeSystem()
        let session = try #require(system.pipeline.admit(
            scanId: nil,
            foregroundGeneration: nil,
            modality: .nonVisual(hasAudio: false)
        ))
        system.pipeline.activate(session)

        await system.pipeline.executeNonVisual(
            harness.nonVisualRequest(session: session),
            callbacks: harness.callbacks()
        )

        #expect(harness.events == [
            .circuitCheck,
            .failureTelemetry,
            .failureCircuit,
            .failureFeedback,
            .failurePresentation,
            .finish(session.attemptGeneration)
        ])
    }

    @Test func staleCompletionCannotClearOrPublishOverReplacement() async throws {
        let gate = InferenceOperationGate()
        let harness = InferenceLivePipelineHarness()
        harness.parseOperation = { [parsedResult = harness.parsedResult] in
            await gate.wait()
            return parsedResult
        }
        let system = harness.makeSystem()
        let original = try #require(system.pipeline.admit(
            scanId: nil,
            foregroundGeneration: nil,
            modality: .nonVisual(hasAudio: false)
        ))
        system.pipeline.activate(original)
        let operation = Task { @MainActor in
            await system.pipeline.executeNonVisual(
                harness.nonVisualRequest(session: original),
                callbacks: harness.callbacks()
            )
        }
        await gate.waitUntilStarted()
        let replacement = try #require(system.pipeline.admit(
            scanId: nil,
            foregroundGeneration: nil,
            modality: .nonVisual(hasAudio: true)
        ))
        system.pipeline.activate(replacement)
        await gate.release()
        await operation.value

        #expect(system.attempt.activeScanId == replacement.scanId)
        #expect(
            system.attempt.activeAttemptGeneration ==
                replacement.attemptGeneration
        )
        #expect(
            !harness.events.contains(.finish(original.attemptGeneration))
        )
        #expect(!harness.events.contains(.commit))
        #expect(!harness.events.contains(.hydration))
        #expect(!harness.events.contains(.failurePresentation))
    }
}
