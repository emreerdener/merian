import SwiftData
import Testing

@testable import Merian

@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct QueueActorCacheTests {
    @Test func cacheTracksModelContainerIdentity() throws {
        let schema = Schema([LocalScanRecord.self])
        let firstContainer = try makeContainer(schema: schema)
        let secondContainer = try makeContainer(schema: schema)
        let manager = OfflineQueueManager.shared

        let firstActor = manager.resolvedQueueDbActor(
            container: firstContainer
        )
        let reusedActor = manager.resolvedQueueDbActor(
            container: firstContainer
        )
        let replacementActor = manager.resolvedQueueDbActor(
            container: secondContainer
        )

        #expect(firstActor === reusedActor)
        #expect(firstActor !== replacementActor)
    }

    private func makeContainer(schema: Schema) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
