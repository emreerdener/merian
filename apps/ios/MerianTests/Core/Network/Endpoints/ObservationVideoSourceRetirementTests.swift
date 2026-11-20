import Foundation
@testable import Merian
import Testing

@Suite("Prepared video source retirement parity")
struct ObservationVideoSourceRetirementTests {
    private let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000090")!
    private let operation = UUID(uuidString: "00000000-0000-4000-8000-000000000080")!
    private func fixtures(_ name: String) throws -> [[String: Any]] {
        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: "services/supabase/functions/_shared/analysisHistory/fixtures/\(name).json")
        return try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
    }
    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private func identity(_ index: Int = 0) throws -> ObservationVideoSourceIdentity {
        try .init(input: data(#require(fixtures("video-source-fingerprint-v1")[index]["input"])))
    }
    private func vector(_ key: String, _ index: Int = 0) throws -> [String: Any] {
        try #require(fixtures("video-source-retirement-v2")[index][key] as? [String: Any])
    }

    @Test func sharedAudioSilentAndUnicodeRequestAndReceiptParity() throws {
        let vectors = try fixtures("video-source-retirement-v2")
        #expect(vectors.count == 3)
        #expect(ObservationVideoSourceRetirementRequest.readerVersion == 12)
        for index in vectors.indices {
            let target = try identity(index)
            let request = try ObservationVideoSourceRetirementRequest(identity: target, operationID: operation)
            #expect(request.body == (try data(vector("request", index))))
            let bytes = try data(vector("receipt", index))
            let receipt = try ObservationVideoSourceRetirementReceipt(data: bytes, request: request, ownerID: owner)
            #expect(receipt.request == request && receipt.ownerID == owner && receipt.data == bytes)
            #expect(throws: (any Error).self) {
                try ObservationVideoSourceReservationReply(data: bytes, identity: target, ownerID: owner)
            }
        }
    }

    @Test func restorationRetainsOriginalFormattingAndOperation() throws {
        let target = try identity()
        let pretty = try JSONSerialization.data(withJSONObject: vector("request"), options: [.prettyPrinted, .sortedKeys])
        let request = try ObservationVideoSourceRetirementRequest(savedBody: pretty, identity: target)
        #expect(request.body == pretty && request.operationID == operation)
        #expect(try ObservationVideoSourceRetirementRequest(savedBody: request.body, identity: target) == request)
        let receiptBytes = try JSONSerialization.data(withJSONObject: vector("receipt"), options: [.prettyPrinted])
        #expect(try ObservationVideoSourceRetirementReceipt(data: receiptBytes, request: request, ownerID: owner).data == receiptBytes)
        #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementRequest(savedBody: pretty, identity: identity(1)) }
    }

    @Test func everyRequestAndReceiptFieldMustMatchOriginalAssociation() throws {
        let target = try identity(), request = try ObservationVideoSourceRetirementRequest(identity: target, operationID: operation)
        for key in try vector("request").keys {
            for value in [NSNull(), "wrong"] as [Any] {
                var row = try vector("request"); row[key] = value
                #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementRequest(savedBody: data(row), identity: target) }
            }
            var missing = try vector("request"); missing.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementRequest(savedBody: data(missing), identity: target) }
        }
        for key in try vector("receipt").keys {
            var row = try vector("receipt"); row[key] = "wrong"
            #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementReceipt(data: data(row), request: request, ownerID: owner) }
            row.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementReceipt(data: data(row), request: request, ownerID: owner) }
        }
        let other = try ObservationVideoSourceRetirementRequest(identity: target, operationID: UUID())
        #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementReceipt(data: data(vector("receipt")), request: other, ownerID: owner) }
        #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementReceipt(data: data(vector("receipt")), request: request, ownerID: UUID()) }
    }

    @Test func operationCannotAliasAnyTargetAndClosedShapeRejectsLegacyAndCoercion() throws {
        let target = try identity(), request = try ObservationVideoSourceRetirementRequest(identity: target, operationID: operation)
        for id in [target.observationID, target.sourceAnalysisID, target.analysisID] {
            #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementRequest(identity: target, operationID: id) }
        }
        let patches: [[String: Any]] = [["schema_version": 1], ["schema_version": true], ["schema_version": 2.5],
            ["fingerprint_version": true], ["fingerprint_version": "1"], ["extra": "no"], ["operation_id": 7]]
        for patch in patches {
            #expect(throws: (any Error).self) {
                try ObservationVideoSourceRetirementRequest(savedBody: data(vector("request").merging(patch) { _, new in new }), identity: target)
            }
            #expect(throws: (any Error).self) {
                try ObservationVideoSourceRetirementReceipt(data: data(vector("receipt").merging(patch) { _, new in new }), request: request, ownerID: owner)
            }
        }
        for state in ["retired_unfunded", "retired_before_dispatch", "reserved", "held", "unavailable", "complete", "dispatched"] {
            var row = try vector("receipt"); row["state"] = state
            #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementReceipt(data: data(row), request: request, ownerID: owner) }
        }
    }

    @Test func boundedUTF8OnlyForRequestsAndReceipts() throws {
        let target = try identity(), request = try ObservationVideoSourceRetirementRequest(identity: target, operationID: operation)
        let invalid = [Data(), Data(repeating: 32, count: 2049), Data([0xc3, 0x28]), Data("[]".utf8), Data("{".utf8)]
        for bytes in invalid {
            #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementRequest(savedBody: bytes, identity: target) }
            #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementReceipt(data: bytes, request: request, ownerID: owner) }
        }
        for encoding in [String.Encoding.utf16, .utf32, .utf16LittleEndian, .utf32LittleEndian] {
            let requestBytes = try #require(String(decoding: request.body, as: UTF8.self).data(using: encoding))
            let receiptBytes = try #require(String(decoding: data(vector("receipt")), as: UTF8.self).data(using: encoding))
            #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementRequest(savedBody: requestBytes, identity: target) }
            #expect(throws: (any Error).self) { try ObservationVideoSourceRetirementReceipt(data: receiptBytes, request: request, ownerID: owner) }
        }
    }
}
