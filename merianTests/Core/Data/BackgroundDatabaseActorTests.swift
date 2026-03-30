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

    // MARK: - updateScanWithOverride: V29 identification review persistence

    @Test func testUpdateScanWithOverrideSetsOverrideString() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "override-actor-test",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverride(scanId: scanId, override: "Procyon cancrivorus", confirmed: false)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.userIdentificationOverride == "Procyon cancrivorus", "updateScanWithOverride must persist the override name")
        #expect(fetched?.userConfirmedIdentification == false, "confirmed must be false when only override is set")
    }

    @Test func testUpdateScanWithOverrideClearsWithNil() async throws {
        // Simulate resetting a previously-overridden scan.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "clear-override-test",
            scientificName: "Procyon cancrivorus",
            commonName: "Crab-eating Raccoon",
            userIdentificationOverride: "Procyon cancrivorus"
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverride(scanId: scanId, override: nil, confirmed: false)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.userIdentificationOverride == nil, "updateScanWithOverride(override: nil) must clear the override column")
        #expect(fetched?.userConfirmedIdentification == false)
    }

    @Test func testUpdateScanWithOverrideSetsConfirmedTrue() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "confirmed-actor-test",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverride(scanId: scanId, override: nil, confirmed: true)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.userConfirmedIdentification == true, "updateScanWithOverride must persist confirmed=true")
        #expect(fetched?.userIdentificationOverride == nil, "override must remain nil on a confirm-only action")
    }
}
