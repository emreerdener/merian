import Foundation
import Testing
@testable import Merian

struct SpeciesDataTests {

    @Test func testSpeciesDataInitialization() {
        // Arrange
        let insightData = InsightData(
            aiReasoning: "A small, glowing beetle.",
            hazardType: "none"
        )
        
        let taxonomyData = TaxonomyData(
            kingdom: "Animalia",
            phylum: "Arthropoda",
            className: "Insecta",
            order: "Coleoptera",
            family: "Lampyridae",
            genus: "Photinus"
        )
        
        // Act
        let species = SpeciesData(
            scanId: "scan_12345",
            commonName: "Firefly",
            scientificName: "Lampyridae",
            insightData: insightData,
            confidenceScore: 0.98,
            wikipediaUrl: "https://en.wikipedia.org/wiki/Firefly",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            taxonomy: taxonomyData
        )
        
        // Assert
        #expect(species.scanId == "scan_12345")
        #expect(species.commonName == "Firefly")
        #expect(species.scientificName == "Lampyridae")
        #expect(species.confidenceScore == 0.98)
        #expect(species.isBiological == true)
        #expect(species.isNewDiscovery == false, "Default or explicitly set state should be honored")
        
        #expect(species.insightData.hazardType == "none")
        #expect(species.taxonomy?.family == "Lampyridae")
    }
    
    @Test func testSpeciesDataMutability() {
        // Arrange
        let insightData = InsightData(
            aiReasoning: "Default description",
            hazardType: "poisonous"
        )

        var species = SpeciesData(
            scanId: nil,
            commonName: "Unknown",
            scientificName: "Unknownidae",
            insightData: insightData,
            confidenceScore: 0.5,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: true,
            ecologyType: "Unknown"
        )

        // Act
        // Verify default state
        #expect(species.isNewDiscovery == false, "New discoveries default to false")

        // Mutate the explicitly var declared property
        species.isNewDiscovery = true

        // Assert
        #expect(species.isNewDiscovery == true, "isNewDiscovery should be fully mutable explicitly bridging state payloads")
    }

    // MARK: - Premium Insights: default nil state

    @Test func testPremiumFieldsDefaultToNilWhenOmitted() {
        let insightData = InsightData(aiReasoning: "A beetle.", hazardType: "none")
        let species = SpeciesData(
            commonName: "Firefly",
            scientificName: "Photinus pyralis",
            insightData: insightData,
            confidenceScore: 0.90
        )

        #expect(species.aiReasoning == nil, "aiReasoning must default to nil for non-Pro / legacy scans")
        #expect(species.habitatDescription == nil, "habitatDescription must default to nil")
    }

    @Test func testPremiumFieldsMutability() {
        let insightData = InsightData(aiReasoning: "A beetle.", hazardType: "none")
        var species = SpeciesData(
            commonName: "Firefly",
            scientificName: "Photinus pyralis",
            insightData: insightData,
            confidenceScore: 0.90
        )

        species.aiReasoning = "The bioluminescent abdomen confirms Photinus pyralis."
        species.habitatDescription = "Warm temperate meadows near water."

        #expect(species.aiReasoning?.contains("Photinus pyralis") == true)
        #expect(species.habitatDescription?.contains("meadows") == true)
    }

    @Test func testPremiumFieldsRoundTripThroughInit() {
        let insightData = InsightData(aiReasoning: "A monarch.", hazardType: "none")
        let species = SpeciesData(
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            insightData: insightData,
            confidenceScore: 0.98,
            aiReasoning: "The orange-black wing pattern is diagnostic.",
            habitatDescription: "Open fields with milkweed."
        )

        #expect(species.aiReasoning == "The orange-black wing pattern is diagnostic.")
        #expect(species.habitatDescription == "Open fields with milkweed.")
    }

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

    // MARK: - Identification Review: aiScientificName & override fields

    @Test func testAIScientificNameSetFromEdgeResponseInit() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "is_biological_subject": true,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.98,
                "insight_data": { "ai_reasoning": "A butterfly.", "hazard_type": "none" }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let species = SpeciesData(fromEdgeResponse: wrapper.data, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)

        #expect(species.aiScientificName == "Danaus plexippus", "aiScientificName must mirror scientific_name from the edge response")
        #expect(species.userIdentificationOverride == nil, "Override must be nil on fresh inference — no user action has occurred")
        #expect(species.userConfirmedIdentification == false, "Confirmed must be false on fresh inference")
        #expect(species.isFlagged == false, "isFlagged must be false on fresh inference")
    }

    @Test func testMemberwiseInitAIScientificNameFallsBackToScientificName() {
        // When aiScientificName is omitted (empty default), memberwise init falls back to scientificName.
        // This ensures load(from:) callers don't need to guard against empty aiScientificName.
        let insightData = InsightData(aiReasoning: "A raccoon.", hazardType: "none")
        let species = SpeciesData(
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: insightData,
            confidenceScore: 0.92
            // aiScientificName omitted — defaults to "" which triggers the fallback
        )

        #expect(species.aiScientificName == "Procyon lotor", "Empty aiScientificName must fall back to scientificName in memberwise init")
    }

    @Test func testMemberwiseInitAIScientificNameIsPreservedWhenExplicit() {
        // When both scientificName (display) and aiScientificName (AI original) are provided
        // — the override scenario — aiScientificName must not be overwritten.
        let insightData = InsightData(aiReasoning: "A raccoon.", hazardType: "none")
        let species = SpeciesData(
            commonName: "Crab-eating Raccoon",
            scientificName: "Procyon cancrivorus",   // patched to override species
            insightData: insightData,
            confidenceScore: 0.92,
            aiScientificName: "Procyon lotor"        // AI's original, preserved independently
        )

        #expect(species.aiScientificName == "Procyon lotor", "Explicit aiScientificName must not be overwritten by scientificName")
        #expect(species.scientificName == "Procyon cancrivorus", "scientificName holds the override (display) name")
    }

    @Test func testReviewFieldDefaultsInMemberwiseInit() {
        let insightData = InsightData(aiReasoning: "A butterfly.", hazardType: "none")
        let species = SpeciesData(
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            insightData: insightData,
            confidenceScore: 0.98
        )

        #expect(species.userIdentificationOverride == nil)
        #expect(species.userConfirmedIdentification == false)
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

    @Test func testTaxonomyDataTreatsUnknownAsMissingForLookalikeValidation() {
        let taxonomy = TaxonomyData(
            kingdom: "Unknown",
            phylum: nil,
            className: nil,
            order: "Malvales",
            family: nil,
            genus: nil
        )

        #expect(taxonomy.hasUsableLookalikeValidation == false)
    }

    @Test func testTaxonomyDataRequiresRealKingdomAndOrderOrFamily() {
        let familyGrounded = TaxonomyData(
            kingdom: "Plantae",
            phylum: nil,
            className: nil,
            order: nil,
            family: "Malvaceae",
            genus: "Sida"
        )
        let orderGrounded = TaxonomyData(
            kingdom: "Animalia",
            phylum: nil,
            className: nil,
            order: "Scorpaeniformes",
            family: nil,
            genus: nil
        )

        #expect(familyGrounded.hasUsableLookalikeValidation == true)
        #expect(orderGrounded.hasUsableLookalikeValidation == true)
    }

    // MARK: - Identification Candidates: IdentificationCandidate

    @Test func testIdentificationCandidateRoundTrip() throws {
        let candidates: [IdentificationCandidate] = [
            IdentificationCandidate(scientificName: "Procyon cancrivorus", confidenceScore: 0.71),
            IdentificationCandidate(scientificName: "Bassariscus astutus", confidenceScore: 0.65)
        ]

        let encoded = try JSONEncoder().encode(candidates)
        let decoded = try JSONDecoder().decode([IdentificationCandidate].self, from: encoded)

        #expect(decoded.count == 2)
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].confidenceScore == 0.71)
        #expect(decoded[1].scientificName == "Bassariscus astutus")
        #expect(decoded[1].confidenceScore == 0.65)
    }

    @Test func testCandidatesMappedFromEdgeResponse() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "candidates_spec_scan",
                "is_biological_subject": true,
                "scientific_name": "Procyon lotor",
                "common_name": "Raccoon",
                "confidence_score": 0.78,
                "insight_data": { "ai_reasoning": "A procyonid.", "hazard_type": "none" },
                "candidates": [
                    { "scientific_name": "Procyon cancrivorus", "confidence_score": 0.71 },
                    { "scientific_name": "Bassariscus astutus", "confidence_score": 0.65 }
                ]
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let species = SpeciesData(fromEdgeResponse: wrapper.data, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)

        let candidates = try #require(species.candidates, "SpeciesData must map candidates array from edge response")
        #expect(candidates.count == 2)
        #expect(candidates[0].scientificName == "Procyon cancrivorus")
        #expect(candidates[0].confidenceScore == 0.71)
    }

    @Test func testNilCandidatesOnHighConfidenceEdgeResponse() throws {
        // Server strips candidates before sending when confidence >= diagnosticTrigger.
        let jsonString = """
        {
            "success": true,
            "data": {
                "is_biological_subject": true,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.97,
                "insight_data": { "ai_reasoning": "Distinctive wings.", "hazard_type": "none" }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let species = SpeciesData(fromEdgeResponse: wrapper.data, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)

        #expect(species.candidates == nil, "Absent candidates key must produce nil — not an empty array")
    }
}
