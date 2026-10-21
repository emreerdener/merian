import Foundation
import Testing
@testable import Merian

@Suite("Native receiving terminal values and phase dispatch", .serialized)
@MainActor
struct SharedMediaNativeReceivingAbandonmentTests {
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Fixture = SharedMediaNativeReceivingTestFixture
    typealias Budget = SharedMediaNativeReceivingReservation

    @Test func terminalValuesPreserveSourceVersionAndExactAcknowledgementFence() async throws {
        let f = try await Fixture.load(count: 1), old = try Intent.Prepared(f.request)
        for p in [old, try p2(old, revision: 4)] {
            let a = try Intent.Abandoned(prepared: p, header: f.request.header)
            #expect(a.version == p.version && a.sourceFormat == p.format)
            #expect(a.revision == (p.intentRevision ?? 0) + 1)
            #expect(a.preparedSHA256 == SharedMediaAcquisitionEncoding.digest(try p.encoded()))
            #expect(try Intent.Abandoned.decode(a.encoded()) == a)
            #expect(try a.encoded().count < p.encoded().count)
            let successor = try p.package.successor(p.package.envelope)
            try a.requireSuccessor(package: successor, member: p.member)
            #expect(throws: (any Error).self) { try a.requireSuccessor(package: p.package, member: p.member) }
            #expect(throws: (any Error).self) {
                try a.requireSuccessor(package: successor.successor(successor.envelope), member: p.member)
            }
            let changed = try Fixture.copy(successor, changes: ["envelope": Data("changed".utf8).base64EncodedString()])
            #expect(throws: (any Error).self) { try a.requireSuccessor(package: changed, member: p.member) }
            let changedMember = try Fixture.copy(p.member, changes: ["revision": p.member.revision + 1])
            #expect(throws: (any Error).self) { try a.requireSuccessor(package: successor, member: changedMember) }
            // The immutable saved header is preserved; this pure check has no
            // current inventory argument that could rebase it during recovery.
            #expect(a.preHeader == f.request.header)
            let json = try Fixture.object(a)
            let package = try #require(json["package"] as? [String: Any])
            let member = try #require(json["member"] as? [String: Any])
            #expect(package["envelope"] == nil && member["bytes"] == nil)
        }
    }

    @Test func malformedTerminalVersionsAndFencesFailClosed() async throws {
        let f = try await Fixture.load(count: 1), p = try p2(Intent.Prepared(f.request), revision: 4)
        let a = try Intent.Abandoned(prepared: p, header: f.request.header)
        let changes: [[String: Any]] = try [
            ["format": "nativeReceivingAbandonedV1"], ["version": 1],
            ["sourceFormat": "nativeReceivingIntentV1"], ["preparedRevision": -1],
            ["preparedRevision": Int64.max], ["revision": 4], ["preparedSHA256": "invalid"],
            ["eventID": a.queueID.uuidString],
            ["package": Fixture.object(Fixture.copy(a.package, changes: ["phase": "preparedHeld"]))],
            ["package": Fixture.object(Fixture.copy(a.package, changes: ["revision": 0]))],
            ["member": Fixture.object(Fixture.copy(a.member, changes: ["bytesSHA256": "invalid"]))],
            ["preHeader": Fixture.object(Fixture.copy(a.preHeader, changes: ["bootstrapContract": 1]))]
        ]
        for change in changes {
            let bad = try Fixture.copy(a, changes: change)
            #expect(throws: (any Error).self) { _ = try bad.encoded() }
        }
        let old = try Intent.Abandoned(prepared: Intent.Prepared(f.request), header: f.request.header)
        let invalidV1 = try Fixture.copy(old, changes: ["preparedRevision": 1, "revision": 2])
        #expect(throws: (any Error).self) { _ = try invalidV1.encoded() }
        let maximum = try p2(Intent.Prepared(f.request), revision: Int64.max - 1)
        #expect(try Intent.Abandoned(prepared: maximum, header: f.request.header).revision == Int64.max)
    }

    @Test func leafSlotRequiresExactPhaseVersionAndBlobShape() async throws {
        let f = try await Fixture.load(count: 1), old = try Intent.Prepared(f.request)
        for p in [old, try p2(old, revision: 4)] {
            let row = try row(p)
            guard case .prepared = try decode(row, p) else { Issue.record("Expected prepared"); return }
            row.schemaVersion = p.version == 1 ? 2 : 1
            #expect(throws: (any Error).self) { _ = try decode(row, p) }
            row.schemaVersion = p.version
            row.resultSHA256 = String(repeating: "a", count: 64)
            #expect(throws: (any Error).self) { _ = try decode(row, p) }
            row.resultSHA256 = nil
            let a = try Intent.Abandoned(prepared: p, header: f.request.header)
            row.phaseRaw = "abandoned"; row.revision = a.revision
            row.resultData = try a.encoded(); row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(try a.encoded())
            #expect(throws: (any Error).self) { _ = try decode(row, p) } // prepared bytes must be released
            row.preparedData = nil
            guard case .abandoned(let saved) = try decode(row, p) else { Issue.record("Expected abandoned"); return }
            #expect(saved == a)
            row.resultSHA256 = String(repeating: "b", count: 64)
            #expect(throws: (any Error).self) { _ = try decode(row, p) }
            row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(try a.encoded())
            row.ownerID = UUID()
            #expect(throws: (any Error).self) { _ = try decode(row, p) }
            row.ownerID = p.profile.ownerID
            row.operationID = UUID()
            #expect(throws: (any Error).self) { _ = try decode(row, p) }
            row.operationID = p.operationID; row.revision -= 1
            #expect(throws: (any Error).self) { _ = try decode(row, p) }
        }
        let p = try p2(old, revision: 4), row = try row(p)
        let result = try Intent.Received(prepared: p, request: p.descriptorForTransaction(header: f.request.header))
        row.phaseRaw = "received"; row.revision = 5
        row.resultData = try result.encoded(prepared: p)
        row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(try result.encoded(prepared: p))
        guard case .received(_, _, let transaction) = try decode(row, p) else { Issue.record("Expected received"); return }
        #expect(try Intent.canonicalRequest(transaction) == Intent.canonicalRequest(p.descriptorForTransaction(header: f.request.header)))
        row.phaseRaw = "abandoned"
        #expect(throws: (any Error).self) { _ = try decode(row, p) }
        row.phaseRaw = "received"; row.preparedData = nil
        #expect(throws: (any Error).self) { _ = try decode(row, p) }
        let legacy = try self.row(old)
        let oldResult = try Intent.Received(prepared: old, request: f.request)
        legacy.phaseRaw = "received"; legacy.revision = 1
        legacy.resultData = try oldResult.encoded(prepared: old)
        legacy.resultSHA256 = SharedMediaAcquisitionEncoding.digest(try oldResult.encoded(prepared: old))
        #expect(throws: (any Error).self) { _ = try decode(legacy, old) }
    }

    @Test func p2ReservationCoversBothTerminalEncodingsWithoutChangingV1() async throws {
        let f = try await Fixture.load(count: 2), old = try Intent.Prepared(f.request), p = try p2(old, revision: 4)
        let metadata = try f.metadata()
        let oldBound = try Budget.maximum(old, currentMetadata: metadata, pairStates: f.states)
        #expect(oldBound.maximumSuccessor == (try Budget.successor(old, header: Fixture.maximumHeader(old),
            currentMetadata: metadata, pairStates: f.states)))
        let bound = try Budget.maximum(p, currentMetadata: metadata, pairStates: f.states)
        let received = try Budget.successor(p, header: Fixture.maximumHeader(p), currentMetadata: metadata, pairStates: f.states)
        let abandoned = try Budget.abandonedSuccessor(p, header: Fixture.maximumHeader(p), currentMetadata: metadata, pairStates: f.states)
        #expect(bound.maximumSuccessor == max(received, abandoned))
        #expect(bound.current == metadata + Int64(try p.encoded().count))
        #expect(try Budget.materializedAbandoned(p, header: f.request.header, currentMetadata: metadata,
            pairStates: f.states, reservation: bound) <= bound.maximumSuccessor)
        #expect(try Budget.materializedAbandoned(old, header: f.request.header, currentMetadata: metadata,
            pairStates: f.states, reservation: oldBound) <= PhotoPreparationPolicy.metadata)
        let atCap = metadata + PhotoPreparationPolicy.metadata - bound.charged
        #expect(try Budget.maximum(p, currentMetadata: atCap, pairStates: f.states).charged == PhotoPreparationPolicy.metadata)
        #expect(throws: (any Error).self) { _ = try Budget.maximum(p, currentMetadata: atCap + 1, pairStates: f.states) }
        #expect(throws: (any Error).self) {
            _ = try Budget.materializedAbandoned(p, header: f.request.header, currentMetadata: metadata + 1,
                pairStates: f.states, reservation: bound)
        }
    }

    private func p2(_ old: Intent.Prepared, revision: Int64) throws -> Intent.Prepared {
        let p = try Fixture.copy(old, changes: ["format": "nativeReceivingIntentV2", "version": 2, "intentRevision": revision])
        _ = try p.encoded()
        return p
    }
    private func row(_ p: Intent.Prepared) throws -> SharedMediaReceivingIntentRecord {
        let row = SharedMediaReceivingIntentRecord(packageID: p.package.id, inventoryID: p.profile.inventoryID,
            inventoryGeneration: p.profile.generation, ownerID: p.profile.ownerID, draftGeneration: p.package.generation,
            operationID: p.operationID, preparedData: try p.encoded(), preparedSHA256: SharedMediaAcquisitionEncoding.digest(try p.encoded()))
        row.schemaVersion = p.version; row.revision = p.intentRevision ?? 0
        return row
    }
    private func decode(_ row: SharedMediaReceivingIntentRecord, _ p: Intent.Prepared) throws -> SharedMediaNativeReceivingSlot {
        try .decode(.init(row), profile: p.profile)
    }
}
