import SwiftData
import Testing

@testable import Merian

@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct ProfileActorCacheTests {
    @Test func cacheTracksModelContainerIdentity() throws {
        let schema = Schema([LocalScanRecord.self])
        let firstContainer = try makeContainer(schema: schema)
        let secondContainer = try makeContainer(schema: schema)
        let manager = OfflineQueueManager.shared

        let firstActor = manager.resolvedProfileDbActor(
            container: firstContainer
        )
        let reusedActor = manager.resolvedProfileDbActor(
            container: firstContainer
        )
        let replacementActor = manager.resolvedProfileDbActor(
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
