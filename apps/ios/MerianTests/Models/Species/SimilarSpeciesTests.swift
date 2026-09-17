import Foundation
@testable import Merian
import Testing

struct SimilarSpeciesTests {
    // MARK: - Similar Species: SimilarSpecies + SimilarSpeciesEntry

    @Test func testSimilarSpeciesBackwardsCompatAccessor() {
        // Arrange: three rich entries covering the common case from the join table
        let entries = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: "Crab-eating Raccoon", referenceImageUrl: "https://example.com/cancrivorus.jpg", iucnRedListStatus: "LC"),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: "Ringtail", referenceImageUrl: nil, iucnRedListStatus: "LC"),
            SimilarSpeciesEntry(scientificName: "Nasua nasua", commonName: "South American Coati", referenceImageUrl: nil, iucnRedListStatus: nil)
        ]
        let similar = SimilarSpecies(entries: entries)

        // Act
        let names = similar.lookalikes

        // Assert: backwards-compat accessor returns flat scientific name strings in order
        #expect(names.count == 3)
        #expect(names[0] == "Procyon cancrivorus")
        #expect(names[1] == "Bassariscus astutus")
        #expect(names[2] == "Nasua nasua")
    }

    @Test func testSimilarSpeciesEntriesWithPartialEnrichment() {
        // Arrange: historical records wrapped with nil enrichment (load(from:) path)
        let entries = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)
        ]
        let similar = SimilarSpecies(entries: entries)

        // Assert: partial entries are valid and accessible; nil fields don't crash
        #expect(similar.entries.count == 2)
        #expect(similar.entries[0].commonName == nil)
        #expect(similar.entries[0].referenceImageUrl == nil)
        #expect(similar.entries[0].iucnRedListStatus == nil)
        #expect(similar.lookalikes == ["Procyon cancrivorus", "Bassariscus astutus"])
    }

    @Test func testSimilarSpeciesMutability() {
        let insightData = InsightData(aiReasoning: "A procyonid.", hazardType: "none")
        var species = SpeciesData(
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: insightData,
            confidenceScore: 0.94
        )

        // Initial state: no lookalikes
        #expect(species.similarSpecies == nil)

        // Act: patch in similar species (mirrors fetchAndApplyEnrichment async path)
        species.similarSpecies = SimilarSpecies(entries: [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: "Crab-eating Raccoon", referenceImageUrl: nil, iucnRedListStatus: "LC")
        ])

        // Assert
        #expect(species.similarSpecies?.entries.count == 1)
        #expect(species.similarSpecies?.entries[0].scientificName == "Procyon cancrivorus")
        #expect(species.similarSpecies?.lookalikes == ["Procyon cancrivorus"])
    }

    @Test func testSimilarSpeciesFilteredEntriesExcludeCurrentSpeciesAndDuplicates() {
        let similar = SimilarSpecies(entries: [
            SimilarSpeciesEntry(scientificName: "Opuntia engelmannii", commonName: "Texas Prickly Pear", referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "  ", commonName: "Ignored", referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "Opuntia lindheimeri", commonName: "Texas Prickly Pear", referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "opuntia lindheimeri", commonName: "Duplicate casing", referenceImageUrl: nil, iucnRedListStatus: nil)
        ])

        let filtered = similar.filteredEntries(excludingScientificName: "Opuntia engelmannii")

        #expect(filtered.count == 1)
        #expect(filtered.first?.scientificName == "Opuntia lindheimeri")
    }

    @Test func testSimilarSpeciesEntryDisplayCommonNameSuppressesDuplicateCurrentCommonName() {
        let entry = SimilarSpeciesEntry(
            scientificName: "Opuntia lindheimeri",
            commonName: "Texas Prickly Pear",
            referenceImageUrl: nil,
            iucnRedListStatus: nil
        )

        #expect(entry.displayCommonName(comparedTo: "Texas Prickly Pear") == nil)
        #expect(entry.displayCommonName(comparedTo: "Cane Cholla") == "Texas Prickly Pear")
    }

    @Test func testSimilarSpeciesKeepsDistinctSpeciesWithTheSameCommonName() {
        let similar = SimilarSpecies(entries: [
            SimilarSpeciesEntry(scientificName: "Pyracantha angustifolia", commonName: "Firethorn", referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "Pyracantha coccinea", commonName: "Firethorn", referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "Pyracantha fortuneana", commonName: " firethorn ", referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: " PYRACANTHA\n  COCCINEA ", commonName: "Duplicate", referenceImageUrl: nil, iucnRedListStatus: nil)
        ])

        let filtered = similar.filteredEntries(excludingScientificName: "Pyracantha angustifolia")

        #expect(filtered.map(\.scientificName) == ["Pyracantha coccinea", "Pyracantha fortuneana"])
        #expect(filtered.allSatisfy { $0.displayCommonName(comparedTo: "Firethorn") == nil })
    }

    @Test func testSimilarSpeciesExcludesCanonicalSelfAndDuplicateIdentitiesAcrossNames() {
        let currentId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let relatedId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let similar = SimilarSpecies(entries: [
            SimilarSpeciesEntry(scientificName: "Current species alias", commonName: "Shared label", referenceImageUrl: nil, iucnRedListStatus: nil, speciesId: currentId.uppercased()),
            SimilarSpeciesEntry(scientificName: "Related species", commonName: "Shared label", referenceImageUrl: nil, iucnRedListStatus: nil, speciesId: relatedId),
            SimilarSpeciesEntry(scientificName: "Related species alias", commonName: "Another label", referenceImageUrl: nil, iucnRedListStatus: nil, speciesId: " \(relatedId.uppercased()) ")
        ])

        let filtered = similar.filteredEntries(
            excludingScientificName: "Current species",
            excludingSpeciesId: currentId
        )

        #expect(filtered.map(\.scientificName) == ["Related species"])
    }

    @Test func testSimilarSpeciesFallsBackToScientificNamesForMissingOrInvalidIDs() {
        let similar = SimilarSpecies(entries: [
            SimilarSpeciesEntry(scientificName: "Pyracantha coccinea", commonName: "Firethorn", referenceImageUrl: nil, iucnRedListStatus: nil, speciesId: "unresolved"),
            SimilarSpeciesEntry(scientificName: "Pyracantha fortuneana", commonName: "Firethorn", referenceImageUrl: nil, iucnRedListStatus: nil, speciesId: "unresolved"),
            SimilarSpeciesEntry(scientificName: "Pyracantha koidzumii", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)
        ])

        #expect(similar.filteredEntries(excludingScientificName: "Pyracantha angustifolia").count == 3)
    }

    // MARK: - SimilarSpeciesEntry: common name JSON round-trip

    @Test func testSimilarSpeciesEntryRoundTripWithCommonName() throws {
        // Verifies the Codable contract that lookalikesData persistence and
        // the needsEnrichment gate both depend on.
        let entry = SimilarSpeciesEntry(
            scientificName: "Procyon cancrivorus",
            commonName: "Crab-eating Raccoon",
            referenceImageUrl: "https://example.com/img.jpg",
            iucnRedListStatus: "LC"
        )
        let data = try JSONEncoder().encode([entry])
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].commonName == "Crab-eating Raccoon")
        #expect(decoded[0].referenceImageUrl == "https://example.com/img.jpg")
        #expect(decoded[0].iucnRedListStatus == "LC")
    }

    @Test func testSimilarSpeciesEntryRoundTripWithNilCommonName() throws {
        // Nil commonName must survive a round-trip as nil (not empty string or missing key).
        // The needsEnrichment gate uses allSatisfy { $0.commonName == nil } — a silent
        // coercion to "" would break the gate and prevent common-name back-fill from firing.
        let entry = SimilarSpeciesEntry(
            scientificName: "Bassariscus astutus",
            commonName: nil,
            referenceImageUrl: nil,
            iucnRedListStatus: nil
        )
        let data = try JSONEncoder().encode([entry])
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: data)

        #expect(decoded[0].commonName == nil, "nil commonName must decode as nil — not empty string")
        #expect(decoded[0].referenceImageUrl == nil)
        #expect(decoded[0].iucnRedListStatus == nil)
    }

    @Test func testSimilarSpeciesEntryDecodesDeniedCachedReferenceImageAsAbsent() throws {
        let data = Data("""
        [
            {
                "scientificName": "Felis silvestris",
                "commonName": "European wildcat",
                "referenceImageUrl": "https://inaturalist-open-data.s3.amazonaws.com/photos/605615444/medium.jpg?size=500",
                "iucnRedListStatus": "LC"
            },
            {
                "scientificName": "Lynx rufus",
                "commonName": "Bobcat",
                "referenceImageUrl": "https://example.com/bobcat.jpg",
                "iucnRedListStatus": "LC"
            }
        ]
        """.utf8)

        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: data)

        #expect(decoded[0].referenceImageUrl == nil)
        #expect(decoded[1].referenceImageUrl == "https://example.com/bobcat.jpg")
    }

    @Test func testSimilarSpeciesEntryRoundTripWithRelationMetadata() throws {
        let entry = SimilarSpeciesEntry(
            scientificName: "Limenitis archippus",
            commonName: "Viceroy",
            referenceImageUrl: "https://example.com/viceroy.jpg",
            iucnRedListStatus: "least_concern",
            speciesId: "species-viceroy",
            similarityReason: "Similar orange-and-black wing pattern.",
            visualTraits: ["orange wings", "dark venation"],
            similarityConfidence: 0.86,
            relationshipSource: "model_enrichment",
            reviewStatus: "unreviewed",
            isBidirectional: false,
            sortOrder: 1
        )

        let data = try JSONEncoder().encode([entry])
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: data)

        #expect(decoded[0].similarityReason == "Similar orange-and-black wing pattern.")
        #expect(decoded[0].visualTraits == ["orange wings", "dark venation"])
        #expect(decoded[0].similarityConfidence == 0.86)
        #expect(decoded[0].relationshipSource == "model_enrichment")
        #expect(decoded[0].reviewStatus == "unreviewed")
        #expect(decoded[0].isBidirectional == false)
        #expect(decoded[0].sortOrder == 1)
    }

    @Test func testSimilarSpeciesEntryDecodesLegacyBlobWithoutRelationMetadata() throws {
        let data = Data("""
        [
            {
                "scientificName": "Bassariscus astutus",
                "commonName": null,
                "referenceImageUrl": null,
                "iucnRedListStatus": null
            }
        ]
        """.utf8)

        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: data)

        #expect(decoded[0].visualTraits.isEmpty)
        #expect(decoded[0].similarityReason == nil)
        #expect(decoded[0].similarityConfidence == nil)
    }

    @Test func testAllNullCommonNamesDetection() throws {
        // Directly validates the allSatisfy check used in load(from:)'s needsEnrichment gate.
        let staleEntries = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)
        ]
        let data = try JSONEncoder().encode(staleEntries)
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: data)

        let lookalikesHaveNoCommonNames = !decoded.isEmpty && decoded.allSatisfy { $0.commonName == nil }
        #expect(lookalikesHaveNoCommonNames == true, "All-null entries must trigger the enrichment gate")
    }

    @Test func testPartialCommonNamesDoNotTriggerEnrichmentGate() throws {
        // Mixed entries (some nil, some non-nil) must NOT trigger needsEnrichment.
        let mixedEntries = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: "Crab-eating Raccoon", referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)
        ]
        let data = try JSONEncoder().encode(mixedEntries)
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: data)

        let lookalikesHaveNoCommonNames = !decoded.isEmpty && decoded.allSatisfy { $0.commonName == nil }
        #expect(lookalikesHaveNoCommonNames == false, "At least one non-nil commonName must suppress enrichment re-trigger")
    }

}
