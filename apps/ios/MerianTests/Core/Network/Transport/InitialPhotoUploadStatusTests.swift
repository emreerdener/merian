import Foundation
@testable import Merian
import Testing

@Suite("Inactive photo upload status")
struct InitialPhotoUploadStatusTests {
    typealias Status = InitialPhotoUploadStatus
    typealias Allocation = SharedMediaNativePhotoAllocation
    private func allocation(receipt: Allocation.Receipt? = nil) throws -> Allocation {
        let fixture = InitialPhotoAllocationRoleReplyTests(), projection = try fixture.projection()
        return try fixture.request().allocation.reservingRoleMapping().enriching(
            receipt ?? projection.receipt, mapping: .init(entries: projection.entries))
    }
    private func row() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(Self.golden.utf8)) as? [String: Any])
    }
    private func bytes(_ row: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: row) }
    private func decode(_ row: [String: Any], allocation: Allocation? = nil, saved: Status? = nil) throws -> Status {
        let allocation = try allocation ?? self.allocation()
        let object = try #require(allocation.roleMapping?.entries.first?.objectID)
        return try Status(data: bytes(row), allocation: allocation, objectID: object, saved: saved)
    }
    @Test func historicalGoldenAndMonotonicFacts() throws {
        var row = try row(), attempt = try #require(row["attempt"] as? [String: Any])
        let bound = try decode(row)
        #expect(bound.attempt?.state == .bound)
        #expect(bound.attempt?.createdAtMilliseconds == 1_793_140_001_000)
        #expect(bound.attempt?.capabilityExpiresAtMilliseconds == 1_793_140_601_000)
        attempt["state"] = "may_have_issued"; row["attempt"] = attempt
        let issued = try decode(row, saved: bound)
        attempt["write_closed"] = true; row["attempt"] = attempt
        let closed = try decode(row, saved: issued)
        #expect(try decode(row, saved: closed) == closed)
        row["attempt"] = NSNull()
        let absent = try decode(row)
        #expect(absent.attempt == nil)
        #expect(try decode(self.row(), saved: absent) == bound)
        #expect(throws: (any Error).self) { _ = try decode(row, saved: closed) }
        #expect(throws: (any Error).self) { _ = try decode(self.row(), saved: issued) }
        attempt["write_closed"] = false; row["attempt"] = attempt
        #expect(throws: (any Error).self) { _ = try decode(row, saved: closed) }
    }
    @Test(arguments: ["version", "authority", "scan", "digest", "object", "extra", "missing", "attemptExtra", "attemptMissing", "id", "uppercase", "state", "boolean", "numericBoolean", "fraction", "before", "expiry", "after", "boundClosed", "array"])
    func malformedProjectionRejected(_ fault: String) throws {
        var row = try row(), attempt = try #require(row["attempt"] as? [String: Any])
        switch fault {
        case "version": row["version"] = 2
        case "authority": row["authority"] = "upload"
        case "scan": row["scan_id"] = row["object_id"]
        case "digest": row["assignment_digest"] = String(repeating: "a", count: 64)
        case "object": row["object_id"] = row["scan_id"]
        case "extra": row["url"] = "forbidden"
        case "missing": row.removeValue(forKey: "attempt")
        case "attemptExtra": attempt["url"] = "forbidden"
        case "attemptMissing": attempt.removeValue(forKey: "write_closed")
        case "id": attempt["attempt_id"] = "invalid"
        case "uppercase": attempt["attempt_id"] = "AAAAAAAA-0000-4000-8000-000000000001"
        case "state": attempt["state"] = "fresh"
        case "boolean": attempt["created_at_ms"] = true
        case "numericBoolean": attempt["write_closed"] = 0
        case "fraction": attempt["created_at_ms"] = 1_793_140_001_000.5
        case "before": attempt["created_at_ms"] = Int64(1_793_139_999_999)
        case "expiry": attempt["capability_expires_at_ms"] = Int64(1_793_140_601_001)
        case "after": attempt["created_at_ms"] = Int64(1_793_141_800_000)
        case "boundClosed": attempt["write_closed"] = true
        case "array": row["attempt"] = []
        default: throw MerianError.invalidResponse
        }
        if fault != "missing" && fault != "array" { row["attempt"] = attempt }
        #expect(throws: (any Error).self) { _ = try decode(row) }
    }
    @Test func attemptIdentityAndClocksCannotRebase() throws {
        let saved = try decode(row())
        for changedID in [false, true] {
            var row = try row(), attempt = try #require(row["attempt"] as? [String: Any])
            if changedID { attempt["attempt_id"] = row["scan_id"] } else {
                attempt["created_at_ms"] = Int64(1_793_140_001_001)
                attempt["capability_expires_at_ms"] = Int64(1_793_140_601_001)
            }
            row["attempt"] = attempt
            #expect(throws: (any Error).self) { _ = try decode(row, saved: saved) }
        }
        var row = try row()
        let allocation = try allocation(), other = try #require(allocation.roleMapping?.entries.last?.objectID)
        row["object_id"] = other.uuidString.lowercased()
        #expect(throws: (any Error).self) { _ = try Status(data: bytes(row), allocation: allocation, objectID: other, saved: saved) }
    }
    @Test func admissionClippingAndMaximumClocks() throws {
        for created in [Int64(1_793_140_000_000), Int64(8_639_999_998_200_000)] {
            let receipt = Allocation.Receipt(assignmentDigest: try allocation().receipt!.assignmentDigest,
                                            createdAtMilliseconds: created, expiresAtMilliseconds: created + 1_800_000)
            var row = try row(), attempt = try #require(row["attempt"] as? [String: Any])
            attempt["created_at_ms"] = created + 1_799_999
            attempt["capability_expires_at_ms"] = receipt.expiresAtMilliseconds; row["attempt"] = attempt
            #expect(try decode(row, allocation: allocation(receipt: receipt)).attempt?.capabilityExpiresAtMilliseconds == receipt.expiresAtMilliseconds)
        }
    }
    @Test func requiresSavedRoleAndBoundsBytes() throws {
        let allocation = try allocation(), object = try #require(allocation.roleMapping?.entries.first?.objectID)
        #expect(Status.maximumBytes == 2048)
        #expect(throws: (any Error).self) { _ = try Status(data: Data(repeating: 32, count: 2049), allocation: allocation, objectID: object) }
        #expect(throws: (any Error).self) {
            _ = try Status(data: Data(Self.golden.utf8), allocation: InitialPhotoAllocationRoleReplyTests().request().allocation, objectID: object)
        }
    }
    @Test func savedObservationCannotCrossOwners() throws {
        let original = try allocation(), saved = try decode(row())
        var claim = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original.claim)) as? [String: Any])
        var profile = try #require(claim["profile"] as? [String: Any])
        profile["ownerID"] = "00000000-0000-4000-8000-000000000999"; claim["profile"] = profile
        let changedClaim = try JSONDecoder().decode(Allocation.Claim.self, from: bytes(claim))
        let other = try Allocation(claim: changedClaim).reservingRoleMapping().enriching(
            #require(original.receipt), mapping: #require(original.roleMapping))
        #expect(throws: (any Error).self) { _ = try decode(row(), allocation: other, saved: saved) }
    }
    // Exact same golden and rejection mutations as cpmPhotoWriteStatus_test.ts.
    private static let golden = #"{"version":1,"authority":"none","scan_id":"00000000-0000-4000-8000-000000000001","assignment_digest":"eb616665a5a98638d564ef78f6aa08899551c0f09b4284fe36bf4c1afa0f7886","object_id":"00000000-0000-4000-8000-000000000200","attempt":{"attempt_id":"00000000-0000-4000-8000-000000000300","state":"bound","created_at_ms":1793140001000,"capability_expires_at_ms":1793140601000,"write_closed":false}}"#
}
