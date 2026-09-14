import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import Merian

@MainActor
@Suite(
    "Inference Live Pipeline Presentation Coordinator",
    .timeLimit(.minutes(1))
)
struct InferenceLivePresentationTests {
    @Test func acceptedCompletionPublishesBeforeForegroundEvent() {
        let harness = LivePipelinePresentationHarness()
        let attempt = UUID()
        let session = session(attemptGeneration: attempt)
        harness.attempt.activate(
            scanId: session.scanId,
            attemptGeneration: attempt,
            foregroundGeneration: nil
        )
        harness.state.setProcessing(true)

        let didCommit = harness.callbacks(for: session).publishCompletion(
            .init(
                speciesData: speciesData(),
                savedImagePaths: ["capture.webp"]
            )
        )

        #expect(didCommit)
        #expect(harness.state.speciesData?.scanId == "scan-a")
        #expect(!harness.state.isProcessing)
        #expect(
            harness.state.activeMedia.items == [
                .image("persisted-capture.webp")
            ]
        )
        #expect(harness.events == [
            .foregroundCompletion(
                "scan-a",
                observedPublishedResult: true
            )
        ])
    }

    @Test func staleCompletionCannotProjectMediaPublishOrSendEvent() {
        let harness = LivePipelinePresentationHarness()
        let staleAttempt = UUID()
        let staleSession = session(attemptGeneration: staleAttempt)
        var projectedPaths: [[String]] = []
        harness.attempt.activate(
            scanId: "replacement",
            attemptGeneration: UUID(),
            foregroundGeneration: nil
        )
        harness.state.setProcessing(true)

        let callbacks = harness.callbacks(
            for: staleSession,
            persistedMediaItems: { paths in
                projectedPaths.append(paths)
                return []
            }
        )
        let didCommit = callbacks.publishCompletion(.init(
            speciesData: speciesData(),
            savedImagePaths: ["capture.webp"]
        ))

        #expect(!didCommit)
        #expect(harness.state.speciesData == nil)
        #expect(harness.state.isProcessing)
        #expect(harness.state.activeMedia.items.isEmpty)
        #expect(harness.events.isEmpty)
        #expect(projectedPaths.isEmpty)
    }

    @Test func queueLessCompletionRebindsFirstRenderClockToServerScanID() {
        let harness = LivePipelinePresentationHarness()
        let attempt = UUID()
        let session = InferenceLivePipelineCoordinator.Session(
            scanId: nil,
            resolvedClientScanId: "temporary-scan",
            attemptGeneration: attempt,
            foregroundGeneration: nil,
            modality: .nonVisual(hasAudio: false)
        )
        harness.attempt.activate(
            scanId: nil,
            attemptGeneration: attempt,
            foregroundGeneration: nil
        )
        harness.presentation.beginFirstRenderMetric(
            scanId: session.resolvedClientScanId,
            startedAt: 42
        )

        let didCommit = harness.callbacks(for: session).publishCompletion(
            .init(
                speciesData: speciesData(),
                savedImagePaths: []
            )
        )

        #expect(didCommit)
        #expect(
            harness.presentation.consumeFirstRenderStart(
                scanId: "temporary-scan"
            ) == nil
        )
        #expect(
            harness.presentation.consumeFirstRenderStart(scanId: "scan-a")
                == 42
        )
    }

    @Test func staleQueueLessCompletionCannotRebindFirstRenderClock() {
        let harness = LivePipelinePresentationHarness()
        let staleAttempt = UUID()
        let currentAttempt = UUID()
        let staleSession = InferenceLivePipelineCoordinator.Session(
            scanId: nil,
            resolvedClientScanId: "temporary-scan",
            attemptGeneration: staleAttempt,
            foregroundGeneration: nil,
            modality: .nonVisual(hasAudio: false)
        )
        harness.attempt.activate(
            scanId: nil,
            attemptGeneration: currentAttempt,
            foregroundGeneration: nil
        )
        harness.presentation.beginFirstRenderMetric(
            scanId: staleSession.resolvedClientScanId,
            startedAt: 42
        )

        let didCommit = harness.callbacks(for: staleSession).publishCompletion(
            .init(
                speciesData: speciesData(),
                savedImagePaths: []
            )
        )

        #expect(!didCommit)
        #expect(
            harness.presentation.consumeFirstRenderStart(scanId: "scan-a")
                == nil
        )
        #expect(
            harness.presentation.consumeFirstRenderStart(
                scanId: "temporary-scan"
            ) == 42
        )
    }

    @Test func finishUsesCallbackSessionGeneration() {
        let harness = LivePipelinePresentationHarness()
        let attempt = UUID()
        let callbacks = harness.callbacks(
            for: session(attemptGeneration: attempt)
        )
        harness.presentation.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            modality: .visual
        )
        harness.state.setProcessing(true)

        callbacks.finish(session(attemptGeneration: UUID()))

        #expect(!harness.state.isProcessing)
        #expect(
            harness.presentation.isActiveVisual(
                attemptGeneration: attempt
            )
        )

        harness.state.setProcessing(true)
        callbacks.finish(session(attemptGeneration: attempt))

        #expect(!harness.state.isProcessing)
        #expect(
            !harness.presentation.isActiveVisual(
                attemptGeneration: attempt
            )
        )
    }

    @Test func typedFailuresRetainRecoverablePublishAndQueueState() {
        let harness = LivePipelinePresentationHarness()
        let attempt = UUID()
        let session = session(attemptGeneration: attempt)
        let callbacks = harness.callbacks(for: session)
        harness.attempt.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: nil
        )
        harness.presentation.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            modality: .visual
        )
        harness.state.setProcessing(true)
        harness.state.replaceActiveMedia(
            ActiveScanMedia(items: [.image("capture.webp")])
        )

        callbacks.applyFailure(.retainRecoverableScan("scan-a"))
        #expect(harness.attempt.recoverablePresentationScanId == "scan-a")

        let failure = speciesData(commonName: "Unable to identify")
        callbacks.applyFailure(.publishFailure(failure))
        #expect(harness.state.speciesData?.commonName == "Unable to identify")

        let expectedPhrases = harness.localAnalysis.handoffPhraseDeck
        callbacks.applyFailure(.transitionToQueue(
            scanId: "scan-a",
            attemptGeneration: attempt
        ))

        #expect(harness.state.queuedPresentationScanId == "scan-a")
        #expect(harness.attempt.recoverablePresentationScanId == "scan-a")
        #expect(harness.state.speciesData == nil)
        #expect(!harness.state.isProcessing)
        #expect(harness.presentation.hasVisualQueueHandoff(for: "scan-a"))
        #expect(
            harness.presentation.scanningPhrases(for: "scan-a")
                == expectedPhrases
        )
    }

    @Test func visualCallbacksFenceBodySessionAndPreservePhraseDeck()
        async throws {
        let cueRecorder = LivePipelinePresentationCueRecorder()
        let harness = LivePipelinePresentationHarness(
            foundationCueProvider: cueRecorder,
            foundationCueEligibilityChecker:
                LivePipelinePresentationEligible()
        )
        let attempt = UUID()
        let foreground = UUID()
        let localSession = InferenceLocalAnalysisCoordinator.Session(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )
        let classificationTask = harness.localAnalysis.start(
            imageData: try makeImageData(),
            focusRegion: nil,
            session: localSession,
            isCurrent: { $0 == localSession },
            publishPhrase: { _ in }
        )
        await classificationTask.value

        let callbacks = harness.subject.makeVisualCallbacks(
            for: session(
                attemptGeneration: attempt,
                foregroundGeneration: foreground
            ),
            persistedMediaItems: { _ in nil },
            modelContainer: nil,
            referencePolicy: .none
        )
        callbacks.markRequestBodySent(session(
            attemptGeneration: attempt,
            foregroundGeneration: UUID()
        ))
        await Task.yield()
        #expect(await cueRecorder.count() == 0)

        callbacks.markRequestBodySent(session(
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        ))
        await cueRecorder.waitUntilRequested()
        #expect(await cueRecorder.count() == 1)

        #if DEBUG
        harness.localAnalysis.startDebugProgression(
            session: localSession,
            automaticallyAdvances: false,
            isCurrent: { $0 == localSession },
            publishPhrase: { _ in }
        )
        harness.localAnalysis.advanceDebugProgression()
        let expectedPhrases = harness.localAnalysis.handoffPhraseDeck

        callbacks.cancelLocalAnalysis()

        #expect(harness.localAnalysis.handoffPhraseDeck == expectedPhrases)
        #else
        callbacks.cancelLocalAnalysis()
        #endif
    }

    @Test func hydrationForwardsCapturedPolicyAndModelContainer()
        async throws {
        let hydrationGate = LivePipelinePresentationHydrationGate()
        let persistenceRecorder = LivePresentationPersistenceRecorder()
        let enrichment = InferenceSpeciesEnrichmentService(
            dependencies: .init { _, scope in
                await hydrationGate.wait()
                switch scope {
                case .metadata:
                    return try JSONDecoder().decode(
                        EnrichScanResponse.self,
                        from: Data(
                            """
                            {
                              "success": true,
                              "data": {
                                "habitat_description": "Open meadows"
                              }
                            }
                            """.utf8
                        )
                    )
                case .lookalikes:
                    return EnrichScanResponse(success: true, data: nil)
                }
            }
        )
        let persistence = InferenceHydrationPersistenceService(
            dependencies: .init(
                persistReference: { _, _ in },
                persistMetadata: { _, container in
                    persistenceRecorder.recordMetadataContainer(container)
                },
                persistLookalikes: { _, _ in }
            )
        )
        let harness = LivePipelinePresentationHarness(
            enrichmentService: enrichment,
            persistenceService: persistence
        )
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        var hydratingSpecies = speciesData()
        hydratingSpecies.gbifTaxonKey = 11
        hydratingSpecies.wikipediaOverview = "Cached overview"
        harness.state.replaceSpeciesData(hydratingSpecies)
        let callbacks = harness.callbacks(
            for: session(attemptGeneration: UUID()),
            modelContainer: container,
            referencePolicy: .showLoadingWhenReferenceMissing
        )

        callbacks.scheduleHydration(hydratingSpecies)
        await hydrationGate.waitUntilStarted()

        #expect(harness.state.activeMedia.referenceState == .loading)

        await hydrationGate.release()
        await harness.hydrationTasks.awaitCurrentTask(in: .live)
        await harness.writes.awaitQuiescence()

        #expect(persistenceRecorder.metadataContainers == [
            ObjectIdentifier(container)
        ])
    }

    private func session(
        attemptGeneration: UUID,
        foregroundGeneration: UUID? = nil
    ) -> InferenceLivePipelineCoordinator.Session {
        .init(
            scanId: "scan-a",
            resolvedClientScanId: "scan-a",
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration,
            modality: .visual
        )
    }

    private func speciesData(
        commonName: String = "Monarch"
    ) -> SpeciesData {
        SpeciesData(
            scanId: "scan-a",
            commonName: commonName,
            scientificName: "Danaus plexippus",
            insightData: InsightData(
                aiReasoning: "Orange wings",
                hazardType: "none"
            ),
            confidenceScore: 0.94,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "terrestrial",
            aiScientificName: "Danaus plexippus"
        )
    }

    private func makeImageData() throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try #require(context.makeImage())
        return try #require(UIImage(cgImage: image).pngData())
    }
}
