import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite("Inference identification-review persistence snapshots")
struct InferenceReviewSnapshotServiceTests {
    @Test func liveServiceReadsTheBoundedDurableFields() throws {
        let context = try makeContext()
        context.insert(LocalScanRecord(
            id: "review-snapshot",
            speciesId: "species-record-id",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            aiReasoning: "Durable reasoning"
        ))
        try context.save()

        let snapshot = try InferenceReviewSnapshotService.live
            .load("review-snapshot", context)

        #expect(snapshot == InferenceReviewSnapshot(
            speciesId: "species-record-id",
            aiReasoning: "Durable reasoning"
        ))
    }

    @Test func liveServiceReturnsNilWhenTheRecordIsAbsent() throws {
        let context = try makeContext()

        let snapshot = try InferenceReviewSnapshotService.live
            .load("missing-review-snapshot", context)

        #expect(snapshot == nil)
    }

    @Test func confirmationFailsClosedWhenDurableStateIsUnreadable() async throws {
        let engine = makeEngineWithFailingSnapshotRead()
        engine.speciesData = speciesData(
            scanId: "confirm-unreadable",
            scientificName: "Procyon lotor"
        )

        await engine.confirmAIIdentification(
            modelContext: try makeContext()
        )

        #expect(engine.speciesData?.userConfirmedIdentification == false)
        #expect(engine.speciesData?.scientificName == "Procyon lotor")
    }

    @Test func resetFailsClosedWhenDurableStateIsUnreadable() async throws {
        let engine = makeEngineWithFailingSnapshotRead()
        engine.speciesData = speciesData(
            scanId: "reset-unreadable",
            scientificName: "Procyon cancrivorus",
            aiScientificName: "Procyon lotor",
            userIdentificationOverride: "Procyon cancrivorus",
            referenceImageURL: "https://example.com/override.jpg"
        )

        await engine.resetIdentificationReview(
            modelContext: try makeContext()
        )

        #expect(
            engine.speciesData?.userIdentificationOverride ==
                "Procyon cancrivorus"
        )
        #expect(engine.speciesData?.scientificName == "Procyon cancrivorus")
        #expect(
            engine.speciesData?.referenceImageUrl ==
                "https://example.com/override.jpg"
        )
    }

    private func makeEngineWithFailingSnapshotRead() -> InferenceEngine {
        InferenceEngine(
            identificationReviewSnapshotService:
                InferenceReviewSnapshotService { _, _ in
                    throw SnapshotReadError.unreadableStore
                }
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }

    private func speciesData(
        scanId: String,
        scientificName: String,
        aiScientificName: String? = nil,
        userIdentificationOverride: String? = nil,
        referenceImageURL: String? = nil
    ) -> SpeciesData {
        SpeciesData(
            scanId: scanId,
            commonName: scientificName,
            scientificName: scientificName,
            insightData: InsightData(
                aiReasoning: "Presented reasoning",
                hazardType: "none"
            ),
            confidenceScore: 0.92,
            referenceImageUrl: referenceImageURL,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            aiScientificName: aiScientificName ?? scientificName,
            userIdentificationOverride: userIdentificationOverride
        )
    }

    private enum SnapshotReadError: Error {
        case unreadableStore
    }
}
