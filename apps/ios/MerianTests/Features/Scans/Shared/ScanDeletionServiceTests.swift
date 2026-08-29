import SwiftData
import Testing

@testable import Merian

@MainActor
struct ScanDeletionServiceTests {
    @Test func existingRecordTriggersFeedbackBeforeErasure() throws {
        let context = try makeContext()
        let record = LocalScanRecord(
            id: "scan-to-delete",
            speciesId: "species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        let events = DeletionEventRecorder()
        let service = ScanDeletionService(
            dependencies: .init(
                findRecord: { scanID, receivedContext in
                    #expect(scanID == record.id)
                    #expect(receivedContext === context)
                    events.values.append("fetch")
                    return record
                },
                eradicateRecord: { receivedRecord, receivedContext in
                    #expect(receivedRecord === record)
                    #expect(receivedContext === context)
                    events.values.append("eradicate")
                },
                triggerDestructiveFeedback: {
                    events.values.append("feedback")
                }
            )
        )

        let result = service.delete(scanID: record.id, in: context)

        #expect(result == .deleted)
        #expect(result.shouldCompletePresentation)
        #expect(events.values == ["fetch", "feedback", "eradicate"])
    }

    @Test func absentRecordCompletesWithoutMutationEffects() throws {
        let context = try makeContext()
        let events = DeletionEventRecorder()
        let service = ScanDeletionService(
            dependencies: .init(
                findRecord: { _, _ in
                    events.values.append("fetch")
                    return nil
                },
                eradicateRecord: { _, _ in
                    events.values.append("eradicate")
                },
                triggerDestructiveFeedback: {
                    events.values.append("feedback")
                }
            )
        )

        let result = service.delete(scanID: "already-absent", in: context)

        #expect(result == .alreadyAbsent)
        #expect(result.shouldCompletePresentation)
        #expect(events.values == ["fetch"])
    }

    @Test func missingSelectionDoesNotCompleteOrResolveDependencies() throws {
        let context = try makeContext()
        let events = DeletionEventRecorder()
        let service = ScanDeletionService(
            dependencies: .init(
                findRecord: { _, _ in
                    events.values.append("fetch")
                    return nil
                },
                eradicateRecord: { _, _ in
                    events.values.append("eradicate")
                },
                triggerDestructiveFeedback: {
                    events.values.append("feedback")
                }
            )
        )

        let result = service.delete(scanID: nil, in: context)

        #expect(result == .notRequested)
        #expect(!result.shouldCompletePresentation)
        #expect(events.values.isEmpty)
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
}

@MainActor
private final class DeletionEventRecorder {
    var values: [String] = []
}
