import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite("Inference Historical Load Coordinator")
struct InferenceHistoricalLoadCoordinatorTests {
    @Test func publishesProjectionBeforeDeferredHydrationCompletes()
        async throws {
        let gate = HistoricalLoadOperationGate()
        let harness = InferenceHistoricalLoadHarness(
            decodeDeferredContent: { projection in
                await gate.wait()
                return await InferenceHistoricalRecordProjection
                    .decodeDeferredContent(projection.deferredContent)
            }
        )
        harness.lifecycle.state.replaceActiveMedia(
            ActiveScanMedia(items: [.liveImage(Data([0x01]))])
        )
        let record = try makeRecord(
            scanId: "historical-presentation",
            candidate: "Danaus gilippus"
        )

        harness.subject.load(from: record)

        #expect(
            harness.lifecycle.attempt.activeScanId
                == "historical-presentation"
        )
        #expect(harness.lifecycle.state.activeMedia.isEmpty)
        #expect(
            harness.lifecycle.state.speciesData?.scanId
                == "historical-presentation"
        )
        #expect(harness.lifecycle.state.speciesData?.candidates == nil)
        #expect(!harness.lifecycle.state.isProcessing)
        #expect(harness.lifecycle.hydration.hasCurrentTask(in: .historic))

        await gate.waitUntilStarted()
        await gate.release()
        await harness.lifecycle.hydration.awaitCurrentTask(in: .historic)

        #expect(
            harness.lifecycle.state.speciesData?.candidates?.first?
                .scientificName == "Danaus gilippus"
        )
    }

    @Test func authFenceRejectsLoadWithoutChangingPresentation() throws {
        let harness = InferenceHistoricalLoadHarness()
        let existing = inferenceSessionLifecycleSpeciesData(
            scanId: "existing-presentation"
        )
        let liveMedia = ActiveScanMedia(
            items: [.liveImage(Data([0x02]))]
        )
        harness.lifecycle.attempt.setActiveScanId("existing-presentation")
        harness.lifecycle.state.replaceSpeciesData(existing)
        harness.lifecycle.state.replaceActiveMedia(liveMedia)
        #expect(harness.lifecycle.writes.beginAuthTransitionFence())
        defer { harness.lifecycle.writes.finishAuthTransitionFence() }

        harness.subject.load(from: try makeRecord(
            scanId: "rejected-historical",
            candidate: "Danaus gilippus"
        ))

        #expect(
            harness.lifecycle.attempt.activeScanId
                == "existing-presentation"
        )
        #expect(
            harness.lifecycle.state.speciesData?.scanId == existing.scanId
        )
        #expect(
            harness.lifecycle.state.speciesData?.commonName
                == existing.commonName
        )
        #expect(harness.lifecycle.state.activeMedia == liveMedia)
        #expect(!harness.lifecycle.hydration.hasCurrentTask(in: .historic))
    }

    @Test func replacementRejectsCancellationIgnoringPriorDecode()
        async throws {
        let gate = HistoricalLoadOperationGate()
        let oldScanID = "historical-old-presentation"
        let newScanID = "historical-new-presentation"
        let harness = InferenceHistoricalLoadHarness(
            decodeDeferredContent: { projection in
                if projection.scanId == oldScanID {
                    await gate.wait()
                }
                return await InferenceHistoricalRecordProjection
                    .decodeDeferredContent(projection.deferredContent)
            }
        )

        harness.subject.load(from: try makeRecord(
            scanId: oldScanID,
            candidate: "Bassariscus astutus"
        ))
        await gate.waitUntilStarted()

        harness.subject.load(from: try makeRecord(
            scanId: newScanID,
            scientificName: "Nasua narica",
            candidate: "Nasua nasua"
        ))
        await harness.lifecycle.hydration.awaitCurrentTask(in: .historic)

        #expect(harness.lifecycle.state.speciesData?.scanId == newScanID)
        #expect(
            harness.lifecycle.state.speciesData?.candidates?.first?
                .scientificName == "Nasua nasua"
        )

        #expect(harness.lifecycle.hydration.beginAuthTransitionFence())
        await gate.release()
        await harness.lifecycle.hydration.awaitQuiescence()
        harness.lifecycle.hydration.finishAuthTransitionFence()

        #expect(harness.lifecycle.state.speciesData?.scanId == newScanID)
        #expect(
            harness.lifecycle.state.speciesData?.candidates?.first?
                .scientificName == "Nasua nasua"
        )
    }

    @Test func schedulesRequiredLookalikeResetWithRecordContainer()
        async throws {
        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
            ]
        )
        let context = ModelContext(container)
        let record = try makeRecord(
            scanId: "historical-reset",
            candidate: "Danaus gilippus"
        )
        context.insert(record)
        try context.save()
        let harness = InferenceHistoricalLoadHarness(
            needsLookalikeReset: true
        )

        harness.subject.load(from: record)

        #expect(harness.resetRecorder.containers == [
            ObjectIdentifier(container)
        ])
        #expect(
            harness.lifecycle.state.speciesData?.similarSpecies == nil
        )
        await harness.lifecycle.hydration.awaitCurrentTask(in: .historic)
    }

    private func makeRecord(
        scanId: String,
        scientificName: String = "Danaus plexippus",
        candidate: String
    ) throws -> LocalScanRecord {
        let lookalikes = [
            SimilarSpeciesEntry(
                scientificName: "Danaus erippus",
                commonName: "Southern Monarch",
                referenceImageUrl: nil,
                iucnRedListStatus: nil
            )
        ]
        let candidates = [
            IdentificationCandidate(
                scientificName: candidate,
                confidenceScore: 0.7
            )
        ]
        return LocalScanRecord(
            id: scanId,
            speciesId: "species-\(scanId)",
            scientificName: scientificName,
            commonName: "Test Species",
            isBiological: true,
            wikipediaOverview: "Existing overview.",
            referenceImageUrl: "https://example.com/reference.jpg",
            taxonomyKingdom: "Animalia",
            taxonomyOrder: "Lepidoptera",
            lookalikesData: try JSONEncoder().encode(lookalikes),
            candidatesData: try JSONEncoder().encode(candidates),
            habitatDescription: "Open habitat.",
            gbifTaxonKey: 5_137_920
        )
    }
}

/// A one-operation, cancellation-ignoring suspension for replacement tests.
private actor HistoricalLoadOperationGate {
    private var hasStarted = false
    private var isReleased = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        hasStarted = true
        startWaiter?.resume()
        startWaiter = nil
        guard !isReleased else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        isReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
private final class HistoricalLoadResetRecorder {
    private(set) var containers: [ObjectIdentifier] = []

    func record(_ container: ModelContainer) {
        containers.append(ObjectIdentifier(container))
    }
}

@MainActor
private final class InferenceHistoricalLoadHarness {
    let lifecycle = InferenceSessionLifecycleHarness()
    let resetRecorder = HistoricalLoadResetRecorder()
    let subject: InferenceHistoricalLoadCoordinator

    init(
        needsLookalikeReset: Bool = false,
        decodeDeferredContent:
            @escaping @Sendable (InferenceHistoricalRecordProjection) async
                -> InferenceHistoricalRecordProjection.DecodedContent = { projection in
                    await InferenceHistoricalRecordProjection
                        .decodeDeferredContent(projection.deferredContent)
                }
    ) {
        let reviewCoordinator = InferenceIdentificationReviewCoordinator(
            writeCoordinator: lifecycle.writes,
            reviewService: InferenceIdentificationReviewService(
                loadSpecies: { _ in nil },
                loadSpeciesID: { _ in nil },
                syncReview: { _ in }
            ),
            snapshotService: InferenceReviewSnapshotService { _, _ in nil },
            dependencies: .init(
                beginOverride: { _, _, _ in },
                persistReview: { _, _ in },
                clearFlag: { _, _ in },
                persistSpeciesPatch: { _, _, _ in },
                sharedPostID: { _ in nil },
                sendPostRefresh: { _ in },
                processIdentificationUpdate: { _ in },
                logSnapshotFailure: { _, _, _ in },
                logSpeciesLookupFailure: { _ in },
                logSyncFailure: { _ in }
            )
        )
        let speciesHydrationCoordinator =
            InferenceSpeciesHydrationCoordinator(
                taskCoordinator: lifecycle.hydration,
                referenceService: SpeciesReferenceHydrationService { request in
                    guard let url = request.url,
                          let response = HTTPURLResponse(
                              url: url,
                              statusCode: 404,
                              httpVersion: nil,
                              headerFields: nil
                          ) else {
                        throw URLError(.badURL)
                    }
                    return (Data(), response)
                },
                enrichmentService: InferenceSpeciesEnrichmentService(
                    dependencies: .init { _, _ in
                        EnrichScanResponse(success: true, data: nil)
                    }
                ),
                persistenceService: InferenceHydrationPersistenceService(
                    dependencies: .init(
                        persistReference: { _, _ in },
                        persistMetadata: { _, _ in },
                        persistLookalikes: { _, _ in }
                    )
                ),
                dependencies: .init(
                    logWikipediaResponse: { _ in },
                    logWikipediaApplied: { _ in },
                    logGBIFResponse: { _ in },
                    logFailure: { _, _ in }
                )
            )
        let speciesPresentationCoordinator =
            InferenceSpeciesPresentationCoordinator(
                presentationState: lifecycle.state,
                writeCoordinator: lifecycle.writes,
                reviewCoordinator: reviewCoordinator,
                speciesHydrationCoordinator: speciesHydrationCoordinator
            )
        let reviewWorkflowCoordinator = InferenceReviewWorkflowCoordinator(
            reviewCoordinator: reviewCoordinator,
            taskCoordinator: lifecycle.hydration,
            speciesHydrationCoordinator: speciesHydrationCoordinator
        )
        let historicalHydrationCoordinator =
            InferenceHistoricalHydrationCoordinator(
                taskCoordinator: lifecycle.hydration,
                speciesHydrationCoordinator: speciesHydrationCoordinator,
                dependencies: .init(
                    decodeDeferredContent: decodeDeferredContent
                )
            )
        let recorder = resetRecorder
        let resetService = InferenceLookalikeCacheResetService(
            dependencies: .init(
                needsReset: { needsLookalikeReset },
                scheduleReset: { container in
                    recorder.record(container)
                }
            )
        )
        subject = InferenceHistoricalLoadCoordinator(
            attemptCoordinator: lifecycle.attempt,
            sessionLifecycleCoordinator: lifecycle.coordinator,
            presentationState: lifecycle.state,
            writeCoordinator: lifecycle.writes,
            speciesPresentationCoordinator: speciesPresentationCoordinator,
            historicalHydrationCoordinator: historicalHydrationCoordinator,
            lookalikeCacheResetService: resetService,
            reviewWorkflowCoordinator: reviewWorkflowCoordinator
        )
    }
}
