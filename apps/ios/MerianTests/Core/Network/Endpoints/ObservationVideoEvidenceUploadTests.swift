import Foundation
@testable import Merian
import Testing

@Suite("Prepared video upload metadata parity")
struct ObservationVideoEvidenceUploadTests {
    private func vectors(_ name: String) throws -> [[String: Any]] {
        let source = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/\(name).json")
        return try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
    }
    private func data(_ row: Any) throws -> Data { try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes]) }
    private func request(_ index: Int = 0) throws -> ObservationVideoEvidenceUploadRequest {
        try .init(input: data(#require(vectors("video-source-fingerprint-v1")[index]["input"])))
    }
    private func row(_ name: String, _ index: Int = 0) throws -> [String: Any] {
        try #require(vectors("video-evidence-v2")[index][name] as? [String: Any])
    }
    private func owner() throws -> UUID { try ObservationHistoryPage.uuid(row("allocated")["owner_id"]) }

    @Test func sharedAudioSilentUnicodeVectorsAndExactSavedBytes() throws {
        #expect(ObservationVideoEvidenceUploadRequest.readerVersion == 12)
        for index in 0..<3 {
            let request = try request(index), owner = try owner()
            #expect(request.body == (try data(row("request", index))))
            let input = try data(#require(vectors("video-source-fingerprint-v1")[index]["input"]))
            let pretty = try JSONSerialization.data(withJSONObject: row("request", index), options: [.prettyPrinted])
            #expect(try ObservationVideoEvidenceUploadRequest(savedBody: pretty, input: input).body == pretty)
            let allocated = try ObservationVideoEvidenceReceipt.allocation(data: data(row("allocated", index)), request: request, ownerID: owner)
            let bytes = try data(row("ready", index))
            let ready = try ObservationVideoEvidenceReceipt(data: bytes, request: request, ownerID: owner, previous: allocated)
            #expect(ready.state == .ready && ready.data == bytes && ready.items.count == allocated.items.count)
            #expect(try ObservationVideoEvidenceReceipt(data: bytes, request: request, ownerID: owner, previous: ready) == ready)
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt.allocation(data: bytes, request: request, ownerID: owner) }
        }
    }

    @Test func closedShapeScopeBoundsAndEncoding() throws {
        let request = try request(), owner = try owner()
        for key in try row("allocated").keys {
            var changed = try row("allocated"); changed[key] = "wrong"
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(changed), request: request, ownerID: owner) }
            changed.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(changed), request: request, ownerID: owner) }
        }
        for bytes in [Data(), Data(repeating: 32, count: 8193), Data([0xc3, 0x28]), Data("[]".utf8)] {
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: bytes, request: request, ownerID: owner) }
        }
        for encoding in [String.Encoding.utf16LittleEndian, .utf32LittleEndian] {
            let bytes = try #require(String(decoding: data(row("allocated")), as: UTF8.self).data(using: encoding))
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: bytes, request: request, ownerID: owner) }
        }
        #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(row("allocated")), request: request, ownerID: UUID()) }
    }

    @Test func wholeInventoryAliasesAndMonotonicReadiness() throws {
        let request = try request(), owner = try owner()
        let allocated = try ObservationVideoEvidenceReceipt.allocation(data: data(row("allocated")), request: request, ownerID: owner)
        let ready = try ObservationVideoEvidenceReceipt(data: data(row("ready")), request: request, ownerID: owner)
        #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: allocated.data, request: request, ownerID: owner, previous: ready) }
        let original = try #require(row("allocated")["items"] as? [[String: Any]])
        for items in [Array(original.dropFirst()), Array(original.reversed()), original + [original[0]]] {
            var changed = try row("allocated"); changed["items"] = items
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(changed), request: request, ownerID: owner) }
        }
        for id in [owner, request.identity.observationID, request.identity.sourceAnalysisID, request.identity.analysisID] + request.inventory.items.map({ $0.artifact.mediaID }) + [allocated.items[1].objectID] {
            var changed = try row("allocated"), items = original
            items[0]["object_id"] = id.uuidString.lowercased(); changed["items"] = items
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(changed), request: request, ownerID: owner) }
        }
        var partial = try row("allocated"), items = original
        items[0]["ready_at"] = ready.items[0].readyAt; partial["items"] = items
        let result = try ObservationVideoEvidenceReceipt(data: data(partial), request: request, ownerID: owner, previous: allocated)
        #expect(result.state == .allocated && result.items.filter { $0.readyAt != nil }.count == 1)
        #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt.allocation(data: data(partial), request: request, ownerID: owner) }
        items[0]["object_id"] = UUID().uuidString.lowercased(); partial["items"] = items
        #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(partial), request: request, ownerID: owner, previous: allocated) }
    }

    @Test func strictUTCMillisecondsAndDeadline() throws {
        let request = try request(), owner = try owner()
        for stamp in ["1500-02-29T00:00:00.000Z", "1900-02-29T00:00:00.000Z", "0000-01-01T00:00:00.000Z", "2026-02-30T00:00:00.000Z", "2026-10-10T00:00:00Z", "2026-10-10T00:00:00.000+00:00", "2026-10-10T00:00:60.000Z"] {
            var changed = try row("allocated"); changed["expires_at"] = stamp
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(changed), request: request, ownerID: owner) }
        }
        var changed = try row("ready"), items = try #require(changed["items"] as? [[String: Any]])
        items[0]["ready_at"] = changed["expires_at"]; changed["items"] = items
        #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(changed), request: request, ownerID: owner) }
    }
    @Test func requestAndItemFieldsCannotBeForgedOrRebound() throws {
        let request = try request(), owner = try owner()
        let input = try data(#require(vectors("video-source-fingerprint-v1")[0]["input"]))
        for key in try row("request").keys {
            var changed = try row("request"); changed[key] = "wrong"
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceUploadRequest(savedBody: data(changed), input: input) }
        }
        for bytes in [Data(repeating: 32, count: 4097), Data([0xc3, 0x28]), Data()] {
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceUploadRequest(savedBody: bytes, input: input) }
        }
        let otherInput = try data(#require(vectors("video-source-fingerprint-v1")[1]["input"]))
        #expect(throws: (any Error).self) { try ObservationVideoEvidenceUploadRequest(savedBody: request.body, input: otherInput) }
        let original = try #require(row("allocated")["items"] as? [[String: Any]])
        for key in original[0].keys {
            var changed = try row("allocated"), items = original
            items[0][key] = "wrong"; changed["items"] = items
            #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(changed), request: request, ownerID: owner) }
        }
        let previous = try ObservationVideoEvidenceReceipt(data: data(row("ready")), request: request, ownerID: owner)
        var changed = try row("ready"); changed["expires_at"] = "2099-01-01T00:00:00.000Z"
        #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(changed), request: request, ownerID: owner, previous: previous) }
        changed = try row("ready"); var items = try #require(changed["items"] as? [[String: Any]])
        items[0]["ready_at"] = "2000-01-01T00:00:00.000Z"; changed["items"] = items
        #expect(throws: (any Error).self) { try ObservationVideoEvidenceReceipt(data: data(changed), request: request, ownerID: owner, previous: previous) }
        for stamp in ["0001-01-01T00:00:00.000Z", "1600-02-29T00:00:00.000Z", "9999-12-31T23:59:59.999Z"] {
            var value = try row("allocated"); value["expires_at"] = stamp
            #expect(try ObservationVideoEvidenceReceipt(data: data(value), request: request, ownerID: owner).expiresAt == stamp)
        }
    }

}
