import Foundation
@testable import Merian
import Testing

@Suite("Dormant native photo transfer request")
struct InitialPhotoTransferRequestTests {
    @Test(arguments: SharedMediaNativePhotoRoleMapping.Role.allCases)
    func issueKeepsExactSubmittedCandidateAndSelectedRole(_ role: SharedMediaNativePhotoRoleMapping.Role) throws {
        let allocation = try InitialPhotoUploadTicketTests().allocation(role, boundBackend: true)
        let request = try InitialPhotoTransferRequest(allocation: allocation, action: .issue)
        let row = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(Set(row.keys) == ["version", "action", "scan_id", "assignment_digest", "object_id",
            "allocation_created_at_ms", "allocation_expires_at_ms", "candidate_canonical"])
        #expect(row["version"] as? Int == 1 && row["action"] as? String == "issue")
        #expect(row["candidate_canonical"] as? String == allocation.claim.candidateCanonical)
        #expect(row["scan_id"] as? String == allocation.claim.observationID.uuidString.lowercased())
        #expect(row["object_id"] as? String == allocation.transferReservation?.selection.objectID.uuidString.lowercased())
        #expect(row["assignment_digest"] as? String == allocation.receipt?.assignmentDigest)
        #expect(row["allocation_created_at_ms"] as? Int64 == allocation.receipt?.createdAtMilliseconds)
        #expect(row["allocation_expires_at_ms"] as? Int64 == allocation.receipt?.expiresAtMilliseconds)
        #expect(request.allocation == allocation && request.action == .issue)
        #expect(try InitialPhotoTransferRequest(allocation: allocation, action: .issue).body == request.body)
    }

    @Test(arguments: [4, 5, 8, 9]) func statusNeedsNeitherCandidateNorDestination(_ phase: Int) throws {
        let allocation = try InitialPhotoUploadTicketTests().allocation(boundBackend: phase >= 8, phase: phase)
        let request = try InitialPhotoTransferRequest(allocation: allocation, action: .status)
        let golden = try #require(JSONSerialization.jsonObject(with: Data(Self.statusGolden.utf8)) as? NSDictionary)
        let actual = try #require(JSONSerialization.jsonObject(with: request.body) as? NSDictionary)
        #expect(actual == golden)
        #expect(request.allocation == allocation && request.action == .status)
        #expect(request.body.range(of: Data("candidate_canonical".utf8)) == nil)
    }

    @Test(arguments: [2, 3, 4, 5, 6, 7, 8]) func preTicketAndLegacyCannotConstructIssue(_ phase: Int) throws {
        let allocation = try InitialPhotoUploadTicketTests().allocation(boundBackend: phase >= 6, phase: phase)
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try InitialPhotoTransferRequest(allocation: allocation, action: .issue) }
        if [2, 3, 6, 7].contains(phase) {
            #expect(throws: SharedMediaStorageFailure.closed) { _ = try InitialPhotoTransferRequest(allocation: allocation, action: .status) }
        }
        let unallocated = SharedMediaNativePhotoAllocation(claim: allocation.claim)
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try InitialPhotoTransferRequest(allocation: unallocated, action: .issue) }
    }

    // Independently checked by the Deno closed-schema parity test. No credentials.
    static let statusGolden = #"{"action":"status","allocation_created_at_ms":1793140000000,"allocation_expires_at_ms":1793141800000,"assignment_digest":"eb616665a5a98638d564ef78f6aa08899551c0f09b4284fe36bf4c1afa0f7886","object_id":"00000000-0000-4000-8000-000000000200","scan_id":"00000000-0000-4000-8000-000000000001","version":1}"#
}
