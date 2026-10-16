import Foundation
@testable import Merian
import Testing

@Suite("Held video cohort inventory parity")
struct ObservationVideoCohortInventoryTests {
    private func fixtures(_ name: String) throws -> [[String: Any]] {
        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: "services/supabase/functions/_shared/analysisHistory/fixtures/\(name).json")
        return try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
    }
    private func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private func input(_ index: Int = 0) throws -> [String: Any] {
        try #require(fixtures("video-source-fingerprint-v1")[index]["input"] as? [String: Any])
    }
    private func expected(_ index: Int = 0) throws -> [[String: Any]] {
        try #require(fixtures("video-cohort-inventory-v1")[index]["items"] as? [[String: Any]])
    }

    @Test func sharedGoldenInventoriesMatchWithoutRewritingRequests() throws {
        for i in 0..<3 {
            let bytes = try data(input(i)), inventory = try ObservationVideoCohortInventory(input: bytes)
            try inventory.validate(items: data(expected(i)))
            #expect(inventory.items.count == (i == 0 ? 7 : 6))
            #expect(inventory.items.first?.role == .source)
            #expect(inventory.items[1...5].map(\.index) == [0, 1, 2, 3, 4])
            #expect(inventory.items[1...5].allSatisfy { $0.role == .frame })
            #expect(inventory.items.last?.role == (i == 0 ? .audio : .frame))
            #expect(try ObservationVideoCohortInventory(input: JSONSerialization.data(withJSONObject: input(i), options: [.prettyPrinted])) == inventory)
        }
    }

    @Test func partialReorderedAndUnknownMetadataFails() throws {
        let inventory = try ObservationVideoCohortInventory(input: data(input())), rows = try expected()
        for invalid in [Array(rows.dropFirst()), rows + [rows[0]], Array(rows.reversed()), []] {
            #expect(throws: (any Error).self) { try inventory.validate(items: data(invalid)) }
        }
        var extra = rows; extra[0]["object_id"] = "unexpected"
        #expect(throws: (any Error).self) { try inventory.validate(items: data(extra)) }
        for i in rows.indices {
            for key in rows[i].keys {
                var changed = rows
                changed[i][key] = changed[i][key] is NSNull ? 0 : NSNull()
                #expect(throws: (any Error).self) { try inventory.validate(items: data(changed)) }
                changed[i].removeValue(forKey: key)
                #expect(throws: (any Error).self) { try inventory.validate(items: data(changed)) }
            }
        }
        #expect(throws: (any Error).self) { try inventory.validate(items: data(expected(1))) }
    }

    @Test func numericTypesAndByteBoundsAreStrict() throws {
        let inventory = try ObservationVideoCohortInventory(input: data(input())), rows = try expected()
        for invalid: Any in [true, "0", 0.5] {
            var changed = rows; changed[1]["index"] = invalid
            #expect(throws: (any Error).self) { try inventory.validate(items: data(changed)) }
        }
        var bool = rows; bool[0]["byte_count"] = true
        #expect(throws: (any Error).self) { try inventory.validate(items: data(bool)) }
        #expect(throws: (any Error).self) { try inventory.validate(items: Data()) }
        #expect(throws: (any Error).self) { try inventory.validate(items: Data(repeating: 0x20, count: 4097)) }
        #expect(throws: (any Error).self) { try inventory.validate(items: Data("{}".utf8)) }
        var equivalent = rows; equivalent[1]["index"] = -0.0
        try inventory.validate(items: data(equivalent))
    }

    @Test func fullInputValidationPrecedesProjection() throws {
        var row = try input(); row["schema_version"] = 3
        #expect(throws: (any Error).self) { try ObservationVideoCohortInventory(input: data(row)) }
        row = try input(); row["source_analysis_id"] = row["observation_id"]
        #expect(throws: (any Error).self) { try ObservationVideoCohortInventory(input: data(row)) }
        #expect(throws: (any Error).self) { try ObservationVideoCohortInventory(input: Data()) }
    }
}
