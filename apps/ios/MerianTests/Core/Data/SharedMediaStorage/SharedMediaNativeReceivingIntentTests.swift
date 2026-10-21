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
