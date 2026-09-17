import Foundation
@testable import Merian
import Testing

struct SpeciesObservationModelsTests {
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

    @Test func testIdentificationCandidateRoundTrip() throws {
        let candidates: [IdentificationCandidate] = [
            IdentificationCandidate(
                scientificName: "Procyon cancrivorus",
                confidenceScore: 0.71
            ),
            IdentificationCandidate(
                scientificName: "Bassariscus astutus",
                confidenceScore: 0.65
            )
        ]

        let encoded = try JSONEncoder().encode(candidates)
        let decoded = try JSONDecoder().decode(
            [IdentificationCandidate].self,
            from: encoded
        )

        #expect(decoded.count == 2)
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].confidenceScore == 0.71)
        #expect(decoded[1].scientificName == "Bassariscus astutus")
        #expect(decoded[1].confidenceScore == 0.65)
    }

    @Test func testPetIdentificationRoundTripsThroughLocalEncoding() throws {
        let pet = PetIdentification(
            speciesGroup: "cat",
            label: "Brown Tabby",
            labelType: "coat_pattern",
            confidenceScore: 0.88,
            evidence: ["striped coat"]
        )

        let encoded = try JSONEncoder().encode(pet)
        let decoded = try JSONDecoder().decode(
            PetIdentification.self,
            from: encoded
        )

        #expect(decoded == pet)
    }
}
