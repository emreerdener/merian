import Foundation
import Testing
@testable import Merian

@Suite("Unconsumed native release request codec", .serialized)
@MainActor
struct SharedMediaNativeReleaseStartRequestTests {
    typealias Request = SharedMediaNativeReleaseStartRequest
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Fixture = SharedMediaNativeReceivingTestFixture

    @Test(arguments: [1, 2])
    func bindsInitialAndRestagedReceivedWithoutChangingHistoricalBytes(_ count: Int) async throws {
        let f = try await Fixture.load(count: count).freshP2().context([])
        for revision: Int64 in [0, 7] {
            let initial = try Intent.Prepared(f.request)
            let p = revision == 0 ? initial : try Fixture.copy(initial, changes: [
                "intentRevision": revision, "restagedFromSHA256": String(repeating: "a", count: 64)])
            let transaction = try p.descriptorForTransaction(header: f.request.header)
            let received = try Intent.Received(prepared: p, request: transaction)
            let beforeP = try p.encoded(), beforeR = try received.encoded(prepared: p)
            let header = try stageHeader(transaction.header, revision: count == 1 ? 99 : 999)
            let value = try Request(prepared: p, received: received, stagePreHeader: header, releaseID: UUID())
            let encoding = try value.encoding()
            #expect(try Request.decode(encoding.data, sha256: encoding.sha256) == value)
            #expect(encoding.metadataBytes == Int64(encoding.data.count + 64))
            #expect(value.receivedRevision == revision + 1)
            #expect(value.receivedSchemaVersion == 2 && value.receivedPhase == "received")
            #expect(value.priorSidecar == .absent)
            #expect(try value.postStageHeader == SharedMediaNativeAppMetadataFacts.successor(header))
            #expect(try value.postStageHeader.inventory.revision == (count == 1 ? 100 : 1000))
            #expect(value.receivingRequestSHA256 == received.requestSHA256)
            #expect(value.preparedSHA256 == SharedMediaAcquisitionEncoding.digest(beforeP))
            #expect(value.receivedSHA256 == SharedMediaAcquisitionEncoding.digest(beforeR))
            try value.requireMatch(prepared: p, received: received)
            #expect(try p.encoded() == beforeP)
            #expect(try received.encoded(prepared: p) == beforeR)

            // Structurally valid altered bindings remain decodable, but cannot
            // establish association with these exact immutable origin values.
            let identities = ["packageID", "draftGeneration", "operationID", "queueID", "observationID", "bindingID", "generation", "eventID"]
            let hashes = ["preparedSHA256", "receivedSHA256", "receivingRequestSHA256", "cohortSHA256"]
            for key in identities + hashes + ["receivedRevision", "profile"] {
                let replacement: Any
                if key == "profile" {
                    var profile = try Fixture.object(value.profile); profile["ownerID"] = UUID().uuidString; replacement = profile
                } else if key == "receivedRevision" { replacement = value.receivedRevision + 1 }
                else if hashes.contains(key) { replacement = String(repeating: "b", count: 64) }
                else { replacement = UUID().uuidString }
                let changed: Request = try Fixture.copy(value, changes: [key: replacement])
                #expect(throws: (any Error).self) { try changed.requireMatch(prepared: p, received: received) }
            }
            for id in [p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID, p.package.id] {
                #expect(throws: (any Error).self) {
                    _ = try Request(prepared: p, received: received, stagePreHeader: header, releaseID: id)
                }
            }
            let entries = try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes).entries
            for entry in entries {
                let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
                let ids = [intent.pairID, intent.preparation.original.reference.assetID, intent.preparation.original.reference.referenceID]
                    + [intent.ai, intent.display].flatMap { [$0.id, $0.assetID, $0.referenceID, $0.leaseID] }
                for id in ids {
                    #expect(throws: (any Error).self) {
                        _ = try Request(prepared: p, received: received, stagePreHeader: header, releaseID: id)
                    }
                }
            }
        }
    }

    @Test func rejectsMalformedEncodingAndHeaderArithmetic() async throws {
        let f = try await Fixture.load(count: 1).freshP2().context([])
        let p = try Intent.Prepared(f.request), received = try Intent.Received(prepared: p, request: f.request)
        let header = try stageHeader(f.request.header, revision: 99)
        let value = try Request(prepared: p, received: received, stagePreHeader: header, releaseID: UUID())
        let encoding = try value.encoding()
        for changes: [String: Any] in [
            ["format": "nativeReceivingReleaseStartV9"], ["priorSidecar": "present"],
            ["receivedSchemaVersion": 1], ["receivedPhase": "prepared"],
            ["receivedRevision": 0], ["receivedRevision": Int64.max],
            ["preparedSHA256": "bad"], ["receivedSHA256": String(repeating: "A", count: 64)],
            ["receivingRequestSHA256": "bad"], ["cohortSHA256": "bad"]
        ] {
            #expect(throws: (any Error).self) {
                let changed: Request = try Fixture.copy(value, changes: changes); _ = try changed.encoded()
            }
        }
        #expect(throws: (any Error).self) { _ = try Request.decode(encoding.data, sha256: String(repeating: "0", count: 64)) }
        #expect(throws: (any Error).self) { _ = try Request.decode(encoding.data, sha256: "bad") }
        #expect(throws: (any Error).self) { _ = try Request.decode(Data(" ".utf8) + encoding.data) }
        #expect(throws: (any Error).self) { _ = try Request.decode(Data(encoding.data.dropLast())) }
        #expect(throws: (any Error).self) { _ = try Request.decode(Data(repeating: 32, count: Int(PhotoPreparationPolicy.metadata) + 1)) }
        var extra = try Fixture.object(value); extra["postStageHeader"] = try Fixture.object(value.postStageHeader)
        #expect(throws: (any Error).self) { _ = try Request.decode(JSONSerialization.data(withJSONObject: extra, options: [.sortedKeys])) }
        for revision in [Int64(-1), .max - 1, .max] {
            #expect(throws: (any Error).self) {
                let invalid = try stageHeader(f.request.header, revision: revision)
                _ = try Request(prepared: p, received: received, stagePreHeader: invalid, releaseID: UUID())
            }
        }
        #expect(throws: (any Error).self) {
            _ = try Request(prepared: p, received: received, stagePreHeader: received.preHeader, releaseID: UUID())
        }
        let widest = try Request(prepared: p, received: received,
            stagePreHeader: stageHeader(f.request.header, revision: .max - 2), releaseID: UUID())
        #expect(try widest.postStageHeader.inventory.revision == Int64.max - 1)
        #expect(try Request.decode(widest.encoded()) == widest)
        // This only leaves arithmetic room for stage/start. It proves neither
        // aggregate cleanup runway nor permission to write at this boundary.
    }

    @Test func externalDecodeIncludesDigestInTheUnchangedMetadataCap() throws {
        let dataCap = PhotoPreparationPolicy.metadata - 64
        #expect(try Request.metadataCharge(dataByteCount: dataCap) == PhotoPreparationPolicy.metadata)
        #expect(throws: SharedMediaStorageFailure.capacity) { _ = try Request.metadataCharge(dataByteCount: dataCap + 1) }
        #expect(throws: (any Error).self) { _ = try Request.metadataCharge(dataByteCount: -1) }
        #expect(throws: (any Error).self) { _ = try Request.metadataCharge(dataByteCount: .max) }
        // A valid V1 has fixed, bounded fields and cannot grow to 1 MiB.
        // Prove external decoding rejects data+digest overflow before parsing;
        // do not invent a padding field or weaken canonical validation.
        let oversized = Data(repeating: 32, count: Int(dataCap + 1))
        #expect(throws: SharedMediaStorageFailure.capacity) {
            _ = try Request.decode(oversized, sha256: SharedMediaAcquisitionEncoding.digest(oversized))
        }
    }

    private func stageHeader(_ source: SharedMediaNativeAppEligibility.Header, revision: Int64) throws -> SharedMediaNativeAppEligibility.Header {
        var inventory = try Fixture.object(source.inventory); inventory["revision"] = revision
        return try Fixture.copy(source, changes: ["inventory": inventory])
    }
}
