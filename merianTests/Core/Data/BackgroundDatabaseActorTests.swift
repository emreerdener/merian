import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct BackgroundDatabaseActorTests {
    
    // Helper to create an isolated SwiftData container caching out to disk due to iOS 18 simulator array appending bugs.
    @MainActor
    private func createIsolatedContainer() throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    }

    @Test func testBackgroundActorIsolatesSendablePayloadsDynamically() async throws {
        // Arrange
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        
        let queuedScan = OfflineQueuedScan(localImagePaths: ["isolation_1.jpg", "isolation_2.jpg"])
        context.insert(queuedScan)
        try context.save()
        
        // Act: Invoke the actor entirely abstracted off the @MainActor through Task.detached
        let payloads = await Task.detached {
            let actor = BackgroundDatabaseActor(modelContainer: container)
            return await actor.fetchPendingScans(limit: 5)
        }.value
        
        // Assert: Ensure execution directly mapped Offline queues into Sendable structs correctly preventing Main Thread locks
        #expect(payloads.count == 1, "Background actor MUST safely extract database references natively")
        #expect(payloads.first?.localImagePaths.count == 2, "Actor isolation boundary MUST preserve deeply nested Array metadata cleanly")
        #expect(payloads.first?.id == queuedScan.id, "Sendable Payload struct MUST explicitly carry the offline scan UUID")
    }
}
