import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightToolbarRecordSnapshotTests {
    @Test func testToolbarSnapshotSurvivesLocalRecordDeletion() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let collection = ScanCollection(name: "Favorites")
        let record = LocalScanRecord(
            speciesId: "toolbar_snapshot_species",
            scientificName: "Bombus testus",
            commonName: "Test Bumblebee",
            coverImagePath: "scan.webp",
            semanticTags: ["bee", "pollinator"],
            taxonomyKingdom: "Animalia",
            taxonomyClass: "Insecta",
            taxonomyOrder: "Hymenoptera",
            taxonomyFamily: "Apidae",
            habitatDescription: "Meadow edge",
            imageQualityScore: 91
        )
        record.collections = [collection]
        ctx.insert(collection)
        ctx.insert(record)
        try ctx.save()

        let recordId = record.id
        let collectionId = collection.id
        let snapshot = InsightToolbarRecordSnapshot(record: record)
        ctx.delete(record)
        try ctx.save()

        #expect(snapshot.scanId == recordId)
        #expect(snapshot.coverImagePath == "scan.webp")
        #expect(snapshot.semanticTags == ["bee", "pollinator"])
        #expect(snapshot.taxonomyClass == "Insecta")
        #expect(snapshot.habitatDescription == "Meadow edge")
        #expect(snapshot.imageQualityScore == 91)
        #expect(snapshot.collectionIds == Set([collectionId]))
    }

}
