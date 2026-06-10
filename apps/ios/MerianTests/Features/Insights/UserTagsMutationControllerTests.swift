import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
struct UserTagsMutationControllerTests {
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        return ModelContext(container)
    }

    @Test func testAddAndRemoveTagsPersistLocallyWithoutDuplicating() throws {
        let context = try createIsolatedContext()
        let record = LocalScanRecord(speciesId: "tags_test", scientificName: "Danaus plexippus", commonName: "Monarch")
        context.insert(record)
        try context.save()

        #expect(UserTagsMutationController.addTag("  backyard  ", to: record, modelContext: context) == true)
        #expect(record.customTags == ["backyard"])

        #expect(UserTagsMutationController.addTag("backyard", to: record, modelContext: context) == true)
        #expect(record.customTags == ["backyard"])

        #expect(UserTagsMutationController.removeTag("backyard", from: record, modelContext: context) == true)
        #expect(record.customTags.isEmpty)
    }
}
