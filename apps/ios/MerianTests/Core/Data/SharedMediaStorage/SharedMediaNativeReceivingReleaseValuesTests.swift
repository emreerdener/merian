import Foundation
import Testing
@testable import Merian

@Suite("Native held-release values and slot size proof", .serialized)
@MainActor
struct SharedMediaNativeReceivingReleaseValuesTests {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Fixture = SharedMediaNativeReceivingTestFixture

    @Test(arguments: [1, 2])
    func emptySupportBoundsEveryTerminalDisposition(_ count: Int) async throws {
        let fixture = try await Fixture.load(count: count).freshP2().context([])
        let p = try Intent.Prepared(fixture.request)
        let received = try Intent.Received(prepared: p, request: fixture.request)
        let acquisitionIDs = try originals(fixture, p)
        let header = try SharedMediaNativeAppMetadataFacts.successor(fixture.request.header)
        let plan = try Values.Plan(prepared: p, received: received, header: header,
            releaseID: UUID(), acquisitionIDs: acquisitionIDs)
        let bytes = try plan.encoded(), bound = try Values.slotBound(plan: plan, prepared: p,
            received: received, acquisitionIDs: acquisitionIDs)
        #expect(try Values.Plan.decode(bytes) == plan)
        #expect(bound.charged <= bound.replacedBytes)
        #expect(bound.planBytes <= PhotoPreparationPolicy.metadata)
        #expect(bound.maximumReleasedBytes <= PhotoPreparationPolicy.metadata)
        #expect(bound.reserved == bound.maximumReleasedBytes - bound.planBytes)
        #expect(plan.jobID == fixture.request.jobID)
        #expect(plan.targets.map(\.acquisitionID) == acquisitionIDs)
        #expect(plan.targets.map(\.original) == (try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes)
            .entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).preparation.original.reference }))
        for mask in 0..<(1 << count) {
            let outcomes = plan.targets.enumerated().map { index, target in
                outcome(target, removed: mask & (1 << index) != 0)
            }
            let terminal = try Values.Released(plan: plan, inventoryRevision: .max, outcomes: outcomes)
            let encoded = try terminal.encoded()
            #expect(Int64(encoded.count) <= bound.maximumReleasedBytes)
            #expect(try Values.Released.decode(encoded) == terminal)
            #expect(throws: (any Error).self) { _ = try Values.Released.decode(Data(" ".utf8) + encoded) }
        }
        print("Release slot size: originals=\(count), replaced=\(bound.replacedBytes), plan=\(bound.planBytes), terminalMaximum=\(bound.maximumReleasedBytes)")

        // A changed but syntactically valid identity never matches its saved
        // origin. Structural decoding is deliberately not an ownership proof.
        let otherIDs = acquisitionIDs.map { _ in UUID() }
        #expect(throws: (any Error).self) {
            try plan.requireMatch(prepared: p, received: received, acquisitionIDs: otherIDs)
        }
        #expect(throws: (any Error).self) {
            _ = try Values.Plan(prepared: p, received: received, header: received.preHeader,
                releaseID: UUID(), acquisitionIDs: acquisitionIDs)
        }
        for change: [String: Any] in [
            ["format": "nativeReceivingReleasingV9"],
            ["preparedRevision": -1],
            ["preparedRevision": Int64.max - 2],
            ["releaseID": plan.queueID.uuidString],
            ["preparedSHA256": "invalid"]
        ] {
            #expect(throws: (any Error).self) {
                let altered: Values.Plan = try Fixture.copy(plan, changes: change)
                _ = try altered.encoded()
            }
        }
        var noncanonical = try Fixture.object(plan)
        noncanonical["unrecognized"] = true
        #expect(throws: (any Error).self) {
            _ = try Values.Plan.decode(JSONSerialization.data(withJSONObject: noncanonical, options: [.sortedKeys]))
        }
        #expect(throws: (any Error).self) { _ = try Values.Plan.decode(Data(" ".utf8) + bytes) }
        #expect(throws: (any Error).self) {
            _ = try Values.Released(plan: plan, inventoryRevision: plan.preHeader.inventory.revision,
                outcomes: plan.targets.map { outcome($0, removed: true) })
        }
        let shared = outcome(plan.targets[0], removed: false)
        let contradictory = try Fixture.copy(shared, changes: ["originalRetirementID": UUID().uuidString])
        #expect(throws: (any Error).self) { try contradictory.validate() }
        if count == 2 {
            #expect(throws: (any Error).self) {
                _ = try Values.Released(plan: plan, inventoryRevision: .max, outcomes: [shared, shared])
            }
        }
    }

    @Test func wideScalarsAndEscapedSupportPreserveSlotBoundWithoutAdmittingRelease() async throws {
        let fixture = try await Fixture.load(count: 2).freshP2().context(String(repeating: "\"\\\n🦋", count: 200))
        let prepared = try Intent.Prepared(fixture.request)
        let p = try Fixture.copy(prepared, changes: ["intentRevision": Int64.max - 3,
            "restagedFromSHA256": String(repeating: "a", count: 64)])
        let receivedHeader = try Fixture.copy(fixture.request.header,
            changes: ["bootstrapRevision": Int64.max])
        let request = try p.descriptorForTransaction(header: receivedHeader)
        let received = try Intent.Received(prepared: p, request: request)
        let header = Fixture.maximumHeader(p)
        let ids = try originals(fixture, p)
        let plan = try Values.Plan(prepared: p, received: received, header: header,
            releaseID: UUID(), acquisitionIDs: ids)
        let bound = try Values.slotBound(plan: plan, prepared: p, received: received, acquisitionIDs: ids)
        let terminal = try Values.Released(plan: plan, inventoryRevision: .max,
            outcomes: plan.targets.map { outcome($0, removed: true) })
        #expect(try plan.releasingRevision == Int64.max - 1)
        #expect(Int64(try terminal.encoded().count) <= bound.maximumReleasedBytes)
        #expect(bound.charged <= bound.replacedBytes)
        #expect(bound.planBytes <= PhotoPreparationPolicy.metadata)
        #expect(bound.maximumReleasedBytes <= PhotoPreparationPolicy.metadata)
        // This intentionally proves only a serialized slot bound. The header
        // has insufficient room for full cleanup; no owner accepts this value.
        print("Release wide slot: replaced=\(bound.replacedBytes), maximum=\(bound.charged)")
    }

    private func originals(_ fixture: Fixture, _ p: Intent.Prepared) throws -> [UUID] {
        try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes).entries.map { entry in
            let assetID = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes).preparation.original.reference.assetID
            return try #require(fixture.receipts.first { $0.0.assetID == assetID }).0.operationID
        }
    }

    private func outcome(_ target: Values.Target, removed: Bool) -> Values.Outcome {
        .init(pairID: target.pairID, pairRetirementID: UUID(), pairClosureSHA256: String(repeating: "a", count: 64),
            original: removed ? .removed : .shared, originalRetirementID: removed ? UUID() : nil,
            originalClosureSHA256: String(repeating: "b", count: 64))
    }
}
