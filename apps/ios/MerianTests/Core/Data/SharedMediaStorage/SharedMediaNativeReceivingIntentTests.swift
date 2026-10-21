import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Durable receiving values and complete reservation", .serialized)
@MainActor
struct SharedMediaNativeReceivingIntentTests {
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Budget = SharedMediaNativeReceivingReservation
    typealias Fixture = SharedMediaNativeReceivingTestFixture

    @Test func exactRequestTimestampAndSavedHeaderRecovery() async throws {
        let f = try await Fixture.load(count: 1), r = f.request
        let original = try Intent.Prepared(r)
        #expect(try Intent.canonicalRequest(original.descriptorForTransaction(header: r.header)) == Intent.canonicalRequest(r))
        let exactDate = Date(timeIntervalSinceReferenceDate: 812_345_678.1234567)
        let p = try Fixture.copy(original, changes: ["timestampBits": exactDate.timeIntervalSinceReferenceDate.bitPattern])
        let bytes = try p.encoded(), decoded = try Intent.Prepared.decode(bytes)
        #expect(try decoded.encoded() == bytes)
        let request = try decoded.descriptorForTransaction(header: r.header)
        #expect(request.timestamp.timeIntervalSinceReferenceDate.bitPattern == exactDate.timeIntervalSinceReferenceDate.bitPattern)
        let saved = try Intent.Received(prepared: decoded, request: request)
        let receipt = try saved.encoded(prepared: decoded)
        let cold = try Intent.Received.decode(receipt, prepared: decoded)
        let nextHeader = try SharedMediaNativeAppMetadataFacts.successor(r.header)
        let later = try decoded.descriptorForTransaction(header: nextHeader)
        #expect(try Intent.canonicalRequest(later) != Intent.canonicalRequest(request))
        #expect(try Intent.canonicalRequest(cold.reconstruct(decoded)) == Intent.canonicalRequest(request))
        #expect(try cold.encoded(prepared: decoded) == receipt)
        #expect(throws: (any Error).self) { _ = try Intent.Received.decode(Data(" ".utf8) + receipt, prepared: decoded) }
        #expect(throws: (any Error).self) { _ = try Intent.Received(prepared: decoded, request: r) }
        for changes: [String: Any] in [["format": "nativeReceivingIntentV1"], ["version": 2],
            ["preparedSHA256": String(repeating: "b", count: 64)], ["requestSHA256": String(repeating: "c", count: 64)]] {
            let bad = try Fixture.copy(saved, changes: changes)
            #expect(throws: (any Error).self) { _ = try bad.reconstruct(decoded) }
        }
    }

    @Test func malformedAndChangedLocalIdentityCannotDecode() async throws {
        let f = try await Fixture.load(count: 1), p = try Intent.Prepared(f.request)
        for changes: [String: Any] in [["format": "nativeReceivingResultV1"], ["version": 2],
            ["timestampBits": Double.infinity.bitPattern], ["eventID": p.queueID.uuidString]] {
            let bad = try Fixture.copy(p, changes: changes)
            #expect(throws: (any Error).self) { _ = try bad.encoded() }
        }
        let wrongPackage = try Fixture.copy(p.package, changes: ["ownerID": UUID().uuidString])
        let wrongMember = try Fixture.copy(p.member, changes: ["draftGeneration": UUID().uuidString])
        let wrongProfile = try Fixture.copy(p.profile, changes: ["physicalBinding": "not-a-hash"])
        for changes: [String: Any] in [["package": try Fixture.object(wrongPackage)],
            ["member": try Fixture.object(wrongMember)], ["profile": try Fixture.object(wrongProfile)]] {
            let bad = try Fixture.copy(p, changes: changes)
            #expect(throws: (any Error).self) { _ = try bad.encoded() }
        }
        let canonical = try p.encoded()
        #expect(throws: (any Error).self) { _ = try Intent.Prepared.decode(Data(" ".utf8) + canonical) }
        let badCohort = SharedMediaNativePreparationBlob(bytes: Data("{}".utf8))
        let changed = try Fixture.copy(p, changes: ["cohort": try Fixture.object(badCohort)])
        #expect(throws: (any Error).self) { _ = try changed.encoded() }
        let cohort = try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes)
        let text = try SharedMediaNativeFrozenSupporting(contexts: [.init(freeText: "different")], presentation: []).encoded()
        let changedCohort = try Fixture.copy(cohort, changes: ["supportingBytes": text.base64EncodedString()])
        let changedText = try Fixture.copy(p, changes: ["cohort": try Fixture.object(SharedMediaNativePreparationBlob(bytes: changedCohort.encoded()))])
        #expect(throws: (any Error).self) { _ = try changedText.encoded() }
    }

    @Test func fullTwoPhotoReservationCountsEveryEnvelopeCopyAndRetainsOrder() async throws {
        let f = try await Fixture.load(count: 2), p = try Intent.Prepared(f.request)
        #expect(try f.metadata() == f.auditedMetadata)
        let cohort = try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes)
        let reversed = cohort.entries.reversed().enumerated().map { index, entry in
            SharedMediaNativeFrozenEntry(position: index, intent: entry.intent,
                aiReferenceRevision: entry.aiReferenceRevision, displayReferenceRevision: entry.displayReferenceRevision,
                aiDescriptor: entry.aiDescriptor, displayDescriptor: entry.displayDescriptor)
        }
        let reverseCohort = try Fixture.copy(cohort, changes: ["entries": try reversed.map(Fixture.object)])
        let reverseIntent = try Fixture.copy(p, changes: ["cohort": try Fixture.object(SharedMediaNativePreparationBlob(bytes: reverseCohort.encoded()))])
        #expect(try Intent.Prepared.decode(reverseIntent.encoded()).cohort == reverseIntent.cohort)
        #expect(try reverseIntent.encoded() != p.encoded())
        let reverseRequest = try reverseIntent.descriptorForTransaction(header: f.request.header)
        #expect(reverseRequest.freeze.commit.cohort == reverseIntent.cohort)
        #expect(try Intent.canonicalRequest(reverseRequest) != Intent.canonicalRequest(f.request))
        for entries in [Array(cohort.entries.prefix(1)), [cohort.entries[0], cohort.entries[0]]] {
            let broken = try Fixture.copy(cohort, changes: ["entries": try entries.map(Fixture.object)])
            #expect(throws: (any Error).self) {
                let value = try Fixture.copy(p, changes: ["cohort": try Fixture.object(SharedMediaNativePreparationBlob(bytes: broken.encoded()))])
                _ = try value.encoded()
            }
        }
        try proveBudget(f)
        // Wire-size feasibility only: no large media files, graph writes, or admission.
        let wide = try f.maximumMedia()
        #expect(wide.request.package.allocated == 77 * 1_024 * 1_024)
        try proveBudget(wide)
        let escaped = try wide.context(String(repeating: "\"\\\n🦋", count: 800))
        try proveBudget(escaped)
        // Maximum per-field quotes and the complete 32,000-UTF16-unit context
        // allowance are valid drafts, but still subject to aggregate receiving cap.
        for (label, contexts) in [
            ("maxField", [ObservationContext(freeText: String(repeating: "\"", count: 8_192))]),
            ("maxAggregate", (0..<4).map { _ in ObservationContext(freeText: String(repeating: "\"", count: 8_000)) })
        ] {
            let rich = try wide.context(contexts)
            let richPrepared = try Intent.Prepared(rich.request), richM = try rich.metadata()
            let complete = try Budget.successor(richPrepared, header: Fixture.maximumHeader(richPrepared), currentMetadata: richM, pairStates: rich.states)
            let charge = max(richM + Int64(try richPrepared.encoded().count), complete)
            print("Receiving codec synthetic \(label): current=\(richM), maximumSuccessor=\(complete), charged=\(charge), cap=\(PhotoPreparationPolicy.metadata)")
            if charge > PhotoPreparationPolicy.metadata {
                #expect(throws: (any Error).self) { _ = try Budget.maximum(richPrepared, currentMetadata: richM, pairStates: rich.states) }
            } else { try proveBudget(rich) }
        }
    }

    private func proveBudget(_ f: Fixture) throws {
        let p = try Intent.Prepared(f.request), metadata = try f.metadata()
        let bound = try Budget.maximum(p, currentMetadata: metadata, pairStates: f.states)
        let actual = try Budget.materialized(p, header: f.request.header, currentMetadata: metadata, pairStates: f.states, reservation: bound)
        let frozen = try f.request.frozenPackage()
        let successors = try f.states.map { state in
            let plan = try Fixture.copy(state.plan, changes: ["envelope": frozen.envelope.base64EncodedString(), "packageRevision": frozen.revision])
            return try Fixture.copy(state, changes: ["plan": Fixture.object(plan)])
        }
        let oldPairs = try f.states.reduce(Int64(0)) { try $0 + SharedMediaNativePairClosure.maximumStateBytes($1) }
        let newPairs = try successors.reduce(Int64(0)) { try $0 + SharedMediaNativePairClosure.maximumStateBytes($1) }
        #expect(newPairs > oldPairs)
        let saved = try Intent.Received(prepared: p, request: f.request)
        let scalarOnly = metadata - Int64(p.package.envelope.count) + Int64(frozen.envelope.count)
            + Int64(try p.encoded().count) + Int64(try saved.encoded(prepared: p).count)
            + Int64(try f.request.cohort.encoded().count) + 2 * Int64(f.request.metadata.utf8.count)
        #expect(actual == scalarOnly + newPairs - oldPairs)
        #expect(actual <= bound.maximumSuccessor)
        #expect(bound.charged == max(bound.current, bound.maximumSuccessor))
        #expect(bound.reserved == bound.charged - bound.current)
        try proveArithmeticBoundaryOnly(p, states: f.states, metadata: metadata, bound: bound)
        #expect(throws: (any Error).self) { _ = try Budget.maximum(p, currentMetadata: metadata, pairStates: Array(f.states.dropLast())) }
        var wrong = f.states
        wrong[0] = try Fixture.copy(wrong[0], changes: ["allocatedBytes": wrong[0].allocatedBytes + 1])
        #expect(throws: (any Error).self) { _ = try Budget.maximum(p, currentMetadata: metadata, pairStates: wrong) }
        #expect(try Budget.materialized(p, header: Fixture.maximumHeader(p), currentMetadata: metadata, pairStates: f.states, reservation: bound) == bound.maximumSuccessor)
    }

    // Arithmetic-only boundary test with synthetic additional liability. It does
    // not establish a persisted graph at exactly the cap; that gate belongs to
    // V65 staging/materialization integration. Real graph feasibility is above.
    private func proveArithmeticBoundaryOnly(_ p: Intent.Prepared, states: [SharedMediaNativePairFileState],
                                             metadata: Int64, bound: Budget.Projection) throws {
        let atCap = metadata + PhotoPreparationPolicy.metadata - bound.charged
        #expect(try Budget.maximum(p, currentMetadata: atCap, pairStates: states).charged == PhotoPreparationPolicy.metadata)
        #expect(throws: (any Error).self) { _ = try Budget.maximum(p, currentMetadata: atCap + 1, pairStates: states) }
    }
}

@Suite("Versioned native receiving values without execution authority", .serialized)
@MainActor
struct SharedMediaNativeReceivingVersionTests {
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Fixture = SharedMediaNativeReceivingTestFixture

    @Test func newBindingRoundTripsWithoutReinterpretingV1() async throws {
        let f = try await Fixture.load(count: 1), old = try Intent.Prepared(f.request)
        let oldBytes = try old.encoded(), oldRequest = try old.descriptorForTransaction(header: f.request.header)
        let oldResult = try Intent.Received(prepared: old, request: oldRequest)
        #expect(try Fixture.object(old)["intentRevision"] == nil)
        #expect(try Fixture.object(oldRequest.cohort)["intentBinding"] == nil)
        #expect(try Set(Fixture.object(old).keys) == Set([
            "format", "version", "profile", "package", "member", "cohort", "operationID",
            "queueID", "observationID", "bindingID", "generation", "eventID", "timestampBits"
        ]))
        #expect(try Set(Fixture.object(oldRequest.cohort).keys) == Set([
            "format", "bindingID", "originQueueID", "observationID", "executionKind",
            "inferenceGeneration", "freeze", "membership"
        ]))
        #expect(old.format == .prepared && oldResult.format == .received)
        #expect(try Intent.canonicalRequest(oldRequest) == Intent.canonicalRequest(f.request))

        let fresh = try prepared(old, revision: 2), bytes = try fresh.encoded()
        let decoded = try Intent.Prepared.decode(bytes)
        let request = try decoded.descriptorForTransaction(header: f.request.header)
        let binding = try #require(request.cohort.intentBinding)
        #expect(fresh.format == .preparedV2 && fresh.version == 2)
        #expect(request.cohort.format == .intentReceiving)
        #expect(request.cohort.queueAuthority == "sharedDirectNativeReceivingV2")
        #expect(request.cohort.metadataKey == "native_receiving_v2")
        #expect(binding.packageID == fresh.package.id && binding.operationID == fresh.operationID)
        #expect(binding.preparedRevision == 2)
        #expect(binding.preparedSHA256 == SharedMediaAcquisitionEncoding.digest(bytes))
        #expect(try Intent.Prepared(request).encoded() == bytes)
        #expect(try request.cohort.digest() != oldRequest.cohort.digest())
        #expect(!request.metadata.contains("native_receiving_v1"))
        #expect(!SharedMediaLegacyQueueAccess.permitsMetadata(request.metadata))
        #expect(throws: SharedMediaStorageFailure.conflict) {
            _ = try SharedMediaConsumerAuthority.classify(raw: request.cohort.queueAuthority,
                consumerID: request.cohort.bindingID, record: .queue)
        }
        let result = try Intent.Received(prepared: decoded, request: request)
        #expect(result.format == .receivedV2 && result.version == 2)
        let saved = try result.encoded(prepared: decoded)
        let cold = try Intent.Received.decode(saved, prepared: Intent.Prepared.decode(bytes))
        #expect(try Intent.canonicalRequest(cold.reconstruct(decoded)) == Intent.canonicalRequest(request))
        let later = try decoded.descriptorForTransaction(header: SharedMediaNativeAppMetadataFacts.successor(f.request.header))
        #expect(try Intent.canonicalRequest(later) != Intent.canonicalRequest(cold.reconstruct(decoded)))
        #expect(try old.encoded() == oldBytes)
        #expect(try Intent.Received.decode(oldResult.encoded(prepared: old), prepared: old).reconstruct(old).cohort == oldRequest.cohort)
        #expect(throws: (any Error).self) { _ = try Intent.Received.decode(saved, prepared: old) }
        #expect(throws: (any Error).self) { _ = try Intent.Received(prepared: fresh, request: oldRequest) }
    }

    @Test func versionRevisionAndBindingSubstitutionsFailClosed() async throws {
        let f = try await Fixture.load(count: 1), old = try Intent.Prepared(f.request)
        let fresh = try prepared(old, revision: 0), request = try fresh.descriptorForTransaction(header: f.request.header)
        let result = try Intent.Received(prepared: fresh, request: request)
        for changes: [String: Any] in [
            ["format": "nativeReceivingIntentV1"], ["version": 1], ["intentRevision": NSNull()],
            ["intentRevision": -1], ["intentRevision": Int64.max]
        ] {
            let bad = try Fixture.copy(fresh, changes: changes)
            #expect(throws: (any Error).self) { _ = try bad.encoded() }
        }
        let changed = try prepared(old, revision: 1)
        #expect(throws: (any Error).self) { _ = try result.reconstruct(changed) }
        for changes: [String: Any] in [["format": "nativeReceivingResultV1"], ["version": 1]] {
            let bad = try Fixture.copy(result, changes: changes)
            #expect(throws: (any Error).self) { _ = try bad.reconstruct(fresh) }
        }
        for changes: [String: Any] in [
            ["format": "nativeReceivingV1"], ["intentBinding": NSNull()]
        ] {
            let bad = try Fixture.copy(request.cohort, changes: changes)
            #expect(throws: (any Error).self) { _ = try bad.encoded() }
        }
        let binding = try #require(request.cohort.intentBinding)
        for changes: [String: Any] in [
            ["packageID": UUID().uuidString], ["operationID": UUID().uuidString],
            ["preparedRevision": -1], ["preparedRevision": Int64.max], ["preparedSHA256": "broken"]
        ] {
            let badBinding = try Fixture.copy(binding, changes: changes)
            let bad = try Fixture.copy(request.cohort, changes: ["intentBinding": Fixture.object(badBinding)])
            #expect(throws: (any Error).self) { _ = try bad.encoded() }
        }
        let relabeledOld = try Fixture.copy(f.request.cohort, changes: ["format": "nativeIntentReceivingV2"])
        #expect(throws: (any Error).self) { _ = try relabeledOld.encoded() }
    }

    @Test func newCanonicalBytesAreIncludedInTheUnchangedReservation() async throws {
        let f = try await Fixture.load(count: 2), old = try Intent.Prepared(f.request)
        let fresh = try prepared(old, revision: 0)
        let before = try SharedMediaNativeReceivingReservation.maximum(old, currentMetadata: f.metadata(), pairStates: f.states)
        let after = try SharedMediaNativeReceivingReservation.maximum(fresh, currentMetadata: f.metadata(), pairStates: f.states)
        #expect(after.current - before.current == Int64(try fresh.encoded().count - old.encoded().count))
        let header = Fixture.maximumHeader(fresh)
        let oldRequest = try old.descriptorForTransaction(header: header)
        let newRequest = try fresh.descriptorForTransaction(header: header)
        let oldResult = try Intent.Received(prepared: old, request: oldRequest)
        let newResult = try Intent.Received(prepared: fresh, request: newRequest)
        let delta = try Int64(fresh.encoded().count - old.encoded().count)
            + Int64(newResult.encoded(prepared: fresh).count - oldResult.encoded(prepared: old).count)
            + Int64(newRequest.cohort.encoded().count - oldRequest.cohort.encoded().count)
            + 2 * Int64(newRequest.metadata.utf8.count - oldRequest.metadata.utf8.count)
        #expect(after.maximumSuccessor - before.maximumSuccessor == delta)
        #expect(after.charged <= PhotoPreparationPolicy.metadata && after.charged > before.charged)
        #expect(try SharedMediaNativeReceivingReservation.materialized(fresh, header: f.request.header,
            currentMetadata: f.metadata(), pairStates: f.states, reservation: after) <= after.maximumSuccessor)
    }

    @Test func newCohortCannotEnterTheLegacyConsumerGraph() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let old = try Intent.Prepared(request), fresh = try prepared(old, revision: 0)
        let descriptor = try fresh.descriptorForTransaction(header: request.header)
        _ = try await owner.receiveAppPhotos(request)
        let c = h.context()
        let rows = try #require(try SharedMediaNativeReceivingRows.read(request, in: c, absent: false))
        #expect(try SharedMediaNativeConsumerGraph.validateScoped(rows.consumer, context: c, format: .appV2) == request.cohort)
        rows.consumer.cohortData = try descriptor.cohort.encoded()
        rows.consumer.cohortSHA256 = try descriptor.cohort.digest()
        try c.save()
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeConsumerGraph.validateScoped(rows.consumer, context: c, format: .appV2)
        }
        rows.consumer.contractVersion = descriptor.cohort.format.rawValue
        try c.save()
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeConsumerGraph.validateScoped(rows.consumer, context: c, format: .appV2)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func newPreparedCannotEnterLegacyStagingRecovery() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let helper = SharedMediaNativeReceivingStagingTests()
        let ids = try helper.pairIDs(request)
        let old = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        let fresh = try prepared(old, revision: 0)
        let c = h.context()
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let row = try #require(try c.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
        row.preparedData = try fresh.encoded()
        row.preparedSHA256 = SharedMediaAcquisitionEncoding.digest(try fresh.encoded())
        try c.save()
        let before = SharedMediaNativeReceivingIntentGraph.Row(row)
        let revision = inventory.revision, envelope = try h.package().supportingContextData
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeReceivingIntentGraph.read(c, inventory: inventory)
        }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeReceivingIntentGraph.cohort(fresh, context: c, inventory: inventory)
        }
        await #expect(throws: (any Error).self) { _ = try await owner.inspectApp() }
        await #expect(throws: (any Error).self) {
            _ = try await owner.discoverAppReceivingIntent(packageID: h.packageID)
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        }
        let after = try #require(try h.context().fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
        #expect(SharedMediaNativeReceivingIntentGraph.Row(after) == before)
        #expect(try helper.inventory(h).revision == revision)
        #expect(try h.package().supportingContextData == envelope)
        try helper.noReceivingRows(h)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func prepared(_ old: Intent.Prepared, revision: Int64) throws -> Intent.Prepared {
        try .init(profile: old.profile, package: old.package, member: old.member, cohort: old.cohort,
            operationID: old.operationID, queueID: old.queueID, observationID: old.observationID,
            bindingID: old.bindingID, generation: old.generation, eventID: old.eventID,
            timestamp: Date(timeIntervalSinceReferenceDate: Double(bitPattern: old.timestampBits)), intentRevision: revision)
    }
}
