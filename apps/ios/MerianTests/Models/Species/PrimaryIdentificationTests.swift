import Foundation
import Testing
@testable import Merian

struct PrimaryIdentificationTests {
    @Test(arguments: PrimaryIdentification.Resolution.allCases)
    func everyResolutionRoundTripsWithRequiredNulls(resolution: PrimaryIdentification.Resolution) throws {
        let snapshot = try PrimaryIdentification.Snapshot(resolution: resolution,
            scientificName: resolution.isNamedBiologicalTaxon ? "Examplea" : nil, commonName: nil)
        let primary = try PrimaryIdentification(snapshot: snapshot)
        #expect(PrimaryIdentification(storedData: primary.data).value == snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: primary.data) as? [String: Any])
        #expect(object["common_name"] is NSNull)
    }

    @Test func malformedPresentMetadataNeverBecomesLegacy() throws {
        let valid = Data(#"{"version":1,"resolution":"genus","scientific_name":"Examplea","common_name":null}"#.utf8)
        let damaged = [Data(), Data(repeating: 65, count: 4_097),
            Data(#"{"version":1,"resolution":"genus","scientific_name":"Examplea"}"#.utf8),
            Data(#"{"version":1,"resolution":"species","scientific_name":null,"common_name":null}"#.utf8),
            Data(#"{"version":2,"resolution":"family","scientific_name":"Exampleaceae","common_name":null}"#.utf8)]
        for bytes in damaged {
            let value = PrimaryIdentification(storedData: bytes)
            #expect(value.data == bytes)
            #expect(value.value == nil)
            #expect(throws: PrimaryIdentification.IntegrityError.self) {
                try PrimaryIdentification.merging(stored: bytes, incoming: nil)
            }
        }
        let provenance = IdentificationResultProvenance(storedData: Data(#"{"schema":"merian_identify_primary_v1"}"#.utf8))
        #expect(PrimaryIdentification.restoring(stored: nil, provenance: nil) == nil)
        #expect(PrimaryIdentification.restoring(stored: nil, provenance: provenance)?.value == nil)
        #expect(PrimaryIdentification.restoring(stored: valid, provenance: nil)?.value == nil)
        #expect(PrimaryIdentification.restoring(stored: valid, provenance: provenance)?.value?.resolution == .genus)
    }

    @Test func namesHaveWireBoundsAndMergesAreImmutable() throws {
        for name in ["", " Examplea", "Examplea\n", "Examplea\u{7F}", String(repeating: "🦋", count: 128)] {
            #expect(throws: PrimaryIdentification.IntegrityError.self) {
                try PrimaryIdentification.Snapshot(resolution: .genus, scientificName: name, commonName: nil)
            }
        }
        let first = try PrimaryIdentification(snapshot: .init(resolution: .genus, scientificName: "Examplea", commonName: nil))
        let second = try PrimaryIdentification(snapshot: .init(resolution: .family, scientificName: "Exampleaceae", commonName: nil))
        #expect(try PrimaryIdentification.merging(stored: first.data, incoming: nil) == first.data)
        #expect(try PrimaryIdentification.merging(stored: first.data, incoming: first) == first.data)
        #expect(throws: PrimaryIdentification.IntegrityError.conflictingSnapshot) {
            try PrimaryIdentification.merging(stored: first.data, incoming: second)
        }
    }
}
