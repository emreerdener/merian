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

    @MainActor
    @Test(arguments: SharedMediaNativePhotoRoleMapping.Role.allCases, [false, true])
    func putRunwayReservesEverySuccessorWithoutIssuanceAuthority(_ role: SharedMediaNativePhotoRoleMapping.Role, maximumClocks: Bool) throws {
        typealias Allocation = SharedMediaNativePhotoAllocation
        var old = try InitialPhotoUploadTicketTests().allocation(role, boundBackend: true, phase: 8)
        if maximumClocks {
            old = try SharedMediaNativeReceivingTestFixture.copy(old, changes: ["receipt": [
                "assignmentDigest": String(repeating: "f", count: 64),
                "createdAtMilliseconds": Int64(8_639_999_998_200_000), "expiresAtMilliseconds": Int64(8_640_000_000_000_000)]])
        }
        let oldBytes = try old.encoded(), reserved = try old.reservingPutStart()
        let requested = try reserved.startingTicketRequest(), receipt = try #require(requested.receipt)
        let attempt = Allocation.RemoteAttempt(id: UUID(), state: .mayHaveIssued,
            createdAtMilliseconds: receipt.expiresAtMilliseconds - 1, capabilityExpiresAtMilliseconds: receipt.expiresAtMilliseconds, writeClosed: false)
        let started = try requested.startingPut(attempt), charge = try reserved.storageCharge
        try old.requireSuccessor(reserved); try reserved.requireSuccessor(requested); try requested.requireSuccessor(started)
        #expect(reserved.remainingAdvances == 5 && requested.remainingAdvances == 4 && started.remainingAdvances == 1)
        for value in [reserved, requested, started] {
            #expect(try value.storageCharge == charge && value.storageCharge >= Int64(value.encoded().count) + 64)
            #expect(value.claim == old.claim && value.receipt == old.receipt && value.backendBinding == old.backendBinding)
            #expect(value.transferReservation == old.transferReservation)
            let bytes = try value.encoded()
            #expect(try Allocation.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes)) == value)
            #expect(throws: SharedMediaStorageFailure.closed) { _ = try InitialPhotoTransferRequest(allocation: value, action: .issue) }
            #expect(try InitialPhotoTransferRequest(allocation: value, action: .status).body == InitialPhotoTransferRequest(allocation: old, action: .status).body)
            #expect(try value.reservingRemoteAttempt() == value)
        }
        // Every monotonic observation stays inside the pre-reserved envelope.
        for seed in [reserved, requested, started] {
            var value = seed
            let states: [(String, Bool)] = seed.version == 12
                ? [("may_have_issued", false), ("may_have_issued", true)]
                : [("bound", false), ("may_have_issued", false), ("may_have_issued", true)]
            for (state, closed) in states {
                let wire: [String: Any] = ["version": 1, "authority": "none", "scan_id": value.claim.observationID.uuidString.lowercased(),
                    "assignment_digest": receipt.assignmentDigest, "object_id": try #require(value.transferReservation).selection.objectID.uuidString.lowercased(),
                    "attempt": ["attempt_id": attempt.id.uuidString.lowercased(), "state": state,
                        "created_at_ms": attempt.createdAtMilliseconds, "capability_expires_at_ms": attempt.capabilityExpiresAtMilliseconds, "write_closed": closed]]
                let observation = try InitialPhotoUploadStatus(data: JSONSerialization.data(withJSONObject: wire), allocation: value,
                    objectID: #require(value.transferReservation).selection.objectID)
                let next = try value.observing(observation)
                if next != value { try value.requireSuccessor(next) }
                value = next
                #expect(try value.storageCharge == charge)
                #expect(throws: SharedMediaStorageFailure.closed) { _ = try value.startingTicketRequest() }
                #expect(throws: SharedMediaStorageFailure.closed) { _ = try value.startingPut(attempt) }
            }
            #expect(value.version == seed.version && value.remoteAttempt?.writeClosed == true)
            #expect(value.remainingAdvances == (seed.version == 10 ? 2 : (seed.version == 11 ? 1 : 0)))
        }
        #expect(try old.encoded() == oldBytes)
        let legacy = try old.startingTicketRequest()
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try legacy.reservingPutStart() }
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try legacy.startingPut(attempt) }
        for phase in [2, 3, 4, 5, 6, 7] {
            let value = try InitialPhotoUploadTicketTests().allocation(role, boundBackend: phase >= 6, phase: phase)
            let bytes = try value.encoded()
            #expect(throws: SharedMediaStorageFailure.closed) { _ = try value.reservingPutStart() }
            #expect(try value.encoded() == bytes)
        }
        let malformed = try SharedMediaNativeReceivingTestFixture.copy(started, changes: ["remoteAttempt": NSNull()])
        #expect(throws: (any Error).self) { _ = try malformed.encoded() }
        for state in [Allocation.RemoteAttemptState.bound, .mayHaveIssued] {
            let invalid = Allocation.RemoteAttempt(id: attempt.id, state: state, createdAtMilliseconds: attempt.createdAtMilliseconds,
                capabilityExpiresAtMilliseconds: attempt.capabilityExpiresAtMilliseconds, writeClosed: state == .mayHaveIssued)
            #expect(throws: SharedMediaStorageFailure.closed) { _ = try requested.startingPut(invalid) }
        }
    }

    // Independently checked by the Deno closed-schema parity test. No credentials.
    static let statusGolden = #"{"action":"status","allocation_created_at_ms":1793140000000,"allocation_expires_at_ms":1793141800000,"assignment_digest":"eb616665a5a98638d564ef78f6aa08899551c0f09b4284fe36bf4c1afa0f7886","object_id":"00000000-0000-4000-8000-000000000200","scan_id":"00000000-0000-4000-8000-000000000001","version":1}"#
}
