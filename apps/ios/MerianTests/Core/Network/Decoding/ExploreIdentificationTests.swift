import Foundation
import Testing
@testable import Merian

struct ExploreIdentificationTests {
    private func decode(_ source: String) throws -> ExploreIdentification {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ExploreIdentification.self, from: Data(source.utf8))
    }

    @Test func broadAndSelectedLabelsPreserveOriginalRank() throws {
        let broad = try decode(#"{"version":1,"rank":"genus","label_source":"ai_primary","original_rank":"genus","original_scientific_name":"Examplea","original_common_name":null}"#)
        #expect(broad.rankDescription == "Genus-level identification")
        #expect(!broad.permitsSpeciesPresentation && broad.originalDescription == nil)
        let selected = try decode(#"{"version":1,"rank":"species","label_source":"verified_selection","original_rank":"genus","original_scientific_name":"Examplea","original_common_name":null}"#)
        #expect(selected.rankDescription == "Species selected by observer")
        #expect(selected.originalDescription == "Original AI identification: Examplea (genus)")
        #expect(selected.permitsSpeciesPresentation)
    }

    @Test func communityAndMalformedLabelsCannotBecomeVerifiedSpecies() throws {
        let community = try decode(#"{"version":1,"rank":"genus","label_source":"community","original_rank":null,"original_scientific_name":null,"original_common_name":null}"#)
        #expect(!community.permitsSpeciesPresentation)
        for value in [
            #"{"version":1,"rank":"species","label_source":"verified_selection","original_rank":"genus","original_scientific_name":"Examplea","original_common_name":null,"extra":true}"#,
            #"{"version":2,"rank":"species","label_source":"verified_selection","original_rank":"genus","original_scientific_name":"Examplea","original_common_name":null}"#,
            #"{"version":1,"rank":"genus","label_source":"verified_selection","original_rank":"genus","original_scientific_name":"Examplea","original_common_name":null}"#,
            #"{"version":1,"rank":"species","label_source":"ai_primary","original_rank":"genus","original_scientific_name":"Examplea","original_common_name":null}"#,
            #"{"version":1,"rank":"genus","label_source":"ai_primary","original_rank":"genus","original_scientific_name":null,"original_common_name":null}"#
        ] { #expect(throws: Error.self) { try decode(value) } }
    }
}
