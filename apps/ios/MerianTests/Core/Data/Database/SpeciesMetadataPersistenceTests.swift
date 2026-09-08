import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Species Metadata Persistence")
struct SpeciesMetadataPersistenceTests {
    @Test func staleSpeciesMetadataCannotOverwriteReplacementIdentification() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "metadata_generation_fence_\(UUID().uuidString.lowercased())"
        context.insert(LocalScanRecord(
            id: scanId,
            speciesId: "replacement-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            isBiological: true,
            isLiveCapture: false
        ))
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let didApplyStaleWikipedia = await actor.updateScanWithWikipedia(
            scanId: scanId,
            extract: "Stale metadata",
            url: "https://example.invalid/stale",
            imageUrl: nil,
            expectedScientificName: "Papilio glaucus"
        )
        #expect(!didApplyStaleWikipedia)
        await actor.updateScanWithEnrichment(
            scanId: scanId,
            habitatDescription: "Stale habitat",
            gbifTaxonKey: 999,
            similarSpeciesJsonData: nil,
            taxonomy: nil,
            expectedScientificName: "Papilio glaucus"
        )

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.wikipediaOverview == nil)
        #expect(persisted.wikipediaUrl == nil)
        #expect(persisted.habitatDescription == nil)
        #expect(persisted.gbifTaxonKey == nil)
    }

    @Test func enrichmentPersistsEveryProvidedFieldForMatchingIdentification() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "metadata_enrichment_\(UUID().uuidString.lowercased())"
        context.insert(LocalScanRecord(
            id: scanId,
            speciesId: "enriched-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            isBiological: true,
            isLiveCapture: false
        ))
        try context.save()

        let taxonomy = try JSONDecoder().decode(
            EdgeResponse.Taxonomy.self,
            from: Data(
                #"{"kingdom":"Animalia","phylum":"Arthropoda","class":"Insecta","order":"Lepidoptera","family":"Nymphalidae","genus":"Danaus"}"#.utf8
            )
        )
        let lookalikesData = Data(#"[{"scientificName":"Danaus gilippus"}]"#.utf8)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithEnrichment(
            scanId: scanId,
            habitatDescription: "Open fields and meadows",
            gbifTaxonKey: 5_137_920,
            similarSpeciesJsonData: lookalikesData,
            taxonomy: taxonomy,
            alternativeCommonNames: ["Milkweed butterfly"],
            expectedScientificName: "Danaus plexippus"
        )

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.habitatDescription == "Open fields and meadows")
        #expect(persisted.gbifTaxonKey == 5_137_920)
        #expect(persisted.lookalikesData == lookalikesData)
        #expect(persisted.taxonomyKingdom == "Animalia")
        #expect(persisted.taxonomyPhylum == "Arthropoda")
        #expect(persisted.taxonomyClass == "Insecta")
        #expect(persisted.taxonomyOrder == "Lepidoptera")
        #expect(persisted.taxonomyFamily == "Nymphalidae")
        #expect(persisted.taxonomyGenus == "Danaus")
        #expect(persisted.alternativeCommonNames == ["Milkweed butterfly"])
    }

    @Test func wikipediaUpdateUsesEffectiveIdentificationAndReportsChanges() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "reference_fallback_\(UUID().uuidString.lowercased())"
        let record = LocalScanRecord(
            id: scanId,
            speciesId: "original-species",
            scientificName: "Lagerstroemia speciosa",
            commonName: "Queen's crape myrtle",
            isBiological: true,
            isLiveCapture: false
        )
        record.userIdentificationOverride = "Lagerstroemia indica"
        context.insert(record)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let rejectedOriginal = await actor.updateScanWithWikipedia(
            scanId: scanId,
            extract: nil,
            url: nil,
            imageUrl: "https://images.example.org/stale.webp",
            expectedScientificName: "Lagerstroemia speciosa"
        )
        #expect(!rejectedOriginal)

        let appliedOverride = await actor.updateScanWithWikipedia(
            scanId: scanId,
            extract: nil,
            url: nil,
            imageUrl: "https://images.example.org/reference.webp",
            expectedScientificName: "Lagerstroemia indica"
        )
        #expect(appliedOverride)

        let repeatedNoOp = await actor.updateScanWithWikipedia(
            scanId: scanId,
            extract: nil,
            url: nil,
            imageUrl: "https://images.example.org/reference.webp",
            expectedScientificName: "Lagerstroemia indica"
        )
        #expect(!repeatedNoOp)

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(
            persisted.referenceImageUrl
                == "https://images.example.org/reference.webp"
        )
    }

    @Test func testClearAllLocalLookalikesCacheClearsBiologicalRecordsAcrossBatchesOnly() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let lookalikeBlob = Data(#"[{"scientificName":"Danaus gilippus"}]"#.utf8)

        for index in 0..<250 {
            context.insert(
                LocalScanRecord(
                    id: "lookalike_batch_\(index)",
                    speciesId: "species_\(index)",
                    scientificName: "Species \(index)",
                    commonName: "Species \(index)",
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                    isBiological: true,
                    similarSpecies: ["Danaus gilippus"],
                    lookalikesData: lookalikeBlob
                )
            )
        }

        context.insert(
            LocalScanRecord(
                id: "lookalike_nonbiological_control",
                speciesId: "nonbio",
                scientificName: "Concrete",
                commonName: "Concrete",
                isBiological: false,
                similarSpecies: ["Should remain"],
                lookalikesData: lookalikeBlob
            )
        )
        try context.save()

        await actor.clearAllLocalLookalikesCache()

        let verificationContext = ModelContext(container)
        let biologicalDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.isBiological == true }
        )
        let biologicalRecords = try verificationContext.fetch(biologicalDescriptor)
        #expect(biologicalRecords.count == 250)
        #expect(biologicalRecords.allSatisfy { $0.lookalikesData == nil })
        #expect(biologicalRecords.allSatisfy { $0.similarSpecies == nil })

        let controlID = "lookalike_nonbiological_control"
        let controlDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == controlID }
        )
        let control = try #require(verificationContext.fetch(controlDescriptor).first)
        #expect(control.lookalikesData == lookalikeBlob)
        #expect(control.similarSpecies == ["Should remain"])
    }

    // MARK: - updateScanWithOverride: V29 identification review persistence

    @Test func testUpdateScanWithOverrideSetsOverrideString() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
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
        await actor.updateScanWithOverride(
            scanId: scanId,
            override: "Procyon cancrivorus",
            confirmed: false,
            newConfirmedSpeciesId: "mock-uuid-overridden",
            userReviewState: .userOverridden
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let verificationContext = ModelContext(container)
        let fetched = try #require(verificationContext.fetch(descriptor).first)
        #expect(fetched.userIdentificationOverride == "Procyon cancrivorus", "updateScanWithOverride must persist the override name")
        #expect(fetched.userConfirmedIdentification == false, "confirmed must be false when only override is set")
        #expect(fetched.confirmedSpeciesId == "mock-uuid-overridden", "new confirmedSpeciesId must be persisted")
        #expect(fetched.userReviewStateRaw == "user_overridden", "userReviewStateRaw must be 'user_overridden'")
    }

    @Test func testUpdateScanWithOverrideClearsWithNil() async throws {
        // Simulate resetting a previously-overridden scan.
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "clear-override-test",
            scientificName: "Procyon lotor",
            commonName: "Crab-eating Raccoon",
            hazardType: "allergenic",
            wikipediaUrl: "https://example.com/rejected-wikipedia",
            wikipediaOverview: "Rejected overview",
            referenceImageUrl: "https://example.com/rejected-reference.jpg",
            taxonomyKingdom: "Animalia",
            taxonomyPhylum: "Chordata",
            taxonomyClass: "Mammalia",
            taxonomyOrder: "Carnivora",
            taxonomyFamily: "Procyonidae",
            taxonomyGenus: "Procyon",
            similarSpecies: ["Rejected species"],
            lookalikesData: Data([0x01]),
            iucnRedListStatus: "LC",
            habitatDescription: "Rejected habitat",
            gbifTaxonKey: 999_999,
            userIdentificationOverride: "Procyon cancrivorus",
            alternativeCommonNames: ["Rejected name"]
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverride(
            scanId: scanId,
            override: nil,
            confirmed: false,
            newConfirmedSpeciesId: nil,
            userReviewState: .unreviewed
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        // The actor saves through its own ModelContext. Verify the committed row
        // through a new context instead of depending on cross-context merge timing
        // in the context that inserted and still registers `record`.
        let verificationContext = ModelContext(container)
        let fetched = try #require(verificationContext.fetch(descriptor).first)
        #expect(fetched.userIdentificationOverride == nil, "updateScanWithOverride(override: nil) must clear the override column")
        #expect(fetched.userConfirmedIdentification == false)
        #expect(fetched.confirmedSpeciesId == nil, "confirmedSpeciesId must be cleared on reset")
        #expect(fetched.userReviewStateRaw == "unreviewed", "userReviewStateRaw must revert to unreviewed")
        #expect(fetched.scientificName == "Procyon lotor")
        #expect(fetched.commonName == "Procyon lotor")
        #expect(fetched.hazardType == "none")
        #expect(fetched.wikipediaUrl == nil)
        #expect(fetched.wikipediaOverview == nil)
        #expect(fetched.referenceImageUrl == nil)
        #expect(fetched.iucnRedListStatus == nil)
        #expect(fetched.habitatDescription == nil)
        #expect(fetched.gbifTaxonKey == nil)
        #expect(fetched.taxonomyKingdom == nil)
        #expect(fetched.taxonomyGenus == nil)
        #expect(fetched.similarSpecies == nil)
        #expect(fetched.lookalikesData == nil)
        #expect(fetched.alternativeCommonNames == nil)
    }

    @Test func testBeginOverrideAtomicallyReplacesPriorIdentity() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let record = LocalScanRecord(
            speciesId: "begin-override-test",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            hazardType: "allergenic",
            wikipediaOverview: "AI overview",
            referenceImageUrl: "https://example.com/ai-reference.jpg",
            taxonomyKingdom: "Animalia",
            taxonomyGenus: "Procyon",
            similarSpecies: ["Nasua nasua"],
            lookalikesData: Data([0x01]),
            habitatDescription: "AI habitat",
            gbifTaxonKey: 5_218_786,
            userConfirmedIdentification: true,
            isFlagged: true,
            alternativeCommonNames: ["Common raccoon"],
            confirmedSpeciesId: "ai-species-id",
            userReviewStateRaw: UserReviewState.aiConfirmed.rawValue
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.beginScanIdentificationOverride(
            scanId: scanId,
            scientificName: "Procyon cancrivorus"
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        let verificationContext = ModelContext(container)
        let fetched = try #require(verificationContext.fetch(descriptor).first)
        #expect(fetched.userIdentificationOverride == "Procyon cancrivorus")
        #expect(!fetched.userConfirmedIdentification)
        #expect(fetched.confirmedSpeciesId == nil)
        #expect(fetched.userReviewState == .userOverridden)
        #expect(!fetched.isFlagged)
        #expect(fetched.commonName == "Procyon cancrivorus")
        #expect(fetched.hazardType == "none")
        #expect(fetched.wikipediaOverview == nil)
        #expect(fetched.referenceImageUrl == nil)
        #expect(fetched.taxonomyKingdom == nil)
        #expect(fetched.taxonomyGenus == nil)
        #expect(fetched.similarSpecies == nil)
        #expect(fetched.lookalikesData == nil)
        #expect(fetched.habitatDescription == nil)
        #expect(fetched.gbifTaxonKey == nil)
        #expect(fetched.alternativeCommonNames == nil)
    }

    @Test func testOverrideSpeciesPlaceholderClearsPriorTaxonFields() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let record = LocalScanRecord(
            speciesId: "override-placeholder-test",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            taxonomyKingdom: "Animalia",
            taxonomyGenus: "Procyon",
            similarSpecies: ["Nasua nasua"],
            lookalikesData: Data([0x01]),
            alternativeCommonNames: ["Common raccoon"]
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverrideSpeciesData(
            scanId: scanId,
            commonName: "Procyon cancrivorus",
            hazardType: "none",
            wikipediaOverview: nil,
            wikipediaUrl: nil,
            referenceImageUrl: nil,
            iucnRedListStatus: nil,
            habitatDescription: nil,
            gbifTaxonKey: nil,
            taxonomy: nil,
            replacingSpeciesIdentity: true
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        let verificationContext = ModelContext(container)
        let fetched = try #require(verificationContext.fetch(descriptor).first)
        #expect(fetched.commonName == "Procyon cancrivorus")
        #expect(fetched.taxonomyKingdom == nil)
        #expect(fetched.taxonomyGenus == nil)
        #expect(fetched.similarSpecies == nil)
        #expect(fetched.lookalikesData == nil)
        #expect(fetched.alternativeCommonNames == nil)
    }

    @Test func testHistoricOverrideRefreshPreservesCurrentTaxonCollections() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let lookalikesData = Data([0x01])
        let record = LocalScanRecord(
            speciesId: "historic-override-refresh-test",
            scientificName: "Procyon lotor",
            commonName: "Crab-eating Raccoon",
            taxonomyKingdom: "Animalia",
            taxonomyGenus: "Procyon",
            similarSpecies: ["Nasua nasua"],
            lookalikesData: lookalikesData,
            userIdentificationOverride: "Procyon cancrivorus",
            alternativeCommonNames: ["South American raccoon"]
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverrideSpeciesData(
            scanId: scanId,
            commonName: "Crab-eating Raccoon",
            hazardType: "none",
            wikipediaOverview: nil,
            wikipediaUrl: nil,
            referenceImageUrl: nil,
            iucnRedListStatus: nil,
            habitatDescription: nil,
            gbifTaxonKey: nil,
            taxonomy: nil,
            replacingSpeciesIdentity: false
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        let verificationContext = ModelContext(container)
        let fetched = try #require(verificationContext.fetch(descriptor).first)
        #expect(fetched.taxonomyKingdom == "Animalia")
        #expect(fetched.taxonomyGenus == "Procyon")
        #expect(fetched.similarSpecies == ["Nasua nasua"])
        #expect(fetched.lookalikesData == lookalikesData)
        #expect(
            fetched.alternativeCommonNames == ["South American raccoon"]
        )
    }

    @Test func testUpdateScanWithOverrideSetsConfirmedTrue() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
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
        await actor.updateScanWithOverride(
            scanId: scanId,
            override: nil,
            confirmed: true,
            newConfirmedSpeciesId: "mock-uuid-confirmed",
            userReviewState: .aiConfirmed
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let verificationContext = ModelContext(container)
        let fetched = try #require(verificationContext.fetch(descriptor).first)
        #expect(fetched.userConfirmedIdentification == true, "updateScanWithOverride must persist confirmed=true")
        #expect(fetched.userIdentificationOverride == nil, "override must remain nil on a confirm-only action")
        #expect(fetched.confirmedSpeciesId == "mock-uuid-confirmed", "confirmedSpeciesId must be explicitly persisted on confirmation")
        #expect(fetched.userReviewStateRaw == "ai_confirmed", "userReviewStateRaw must be 'ai_confirmed'")
    }

    // MARK: - updateScanAsUnflagged: legacy moderation state cleanup

    @Test func testUpdateScanAsUnflaggedRemovesFlag() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "unflag-actor-test",
            scientificName: "Aedes aegypti",
            commonName: "Yellow Fever Mosquito",
            isFlagged: true
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanAsUnflagged(scanId: scanId)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let verificationContext = ModelContext(container)
        let fetched = try verificationContext.fetch(descriptor).first
        #expect(fetched?.isFlagged == false, "updateScanAsUnflagged must persist isFlagged=false")
    }
}
