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
        #expect(bound.reserved == bound.charged - bound.planBytes)
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

    @Test(arguments: [1, 2])
    func progressRetainsProofsAcrossEveryStageAndSharingDisposition(_ count: Int) async throws {
        let fixture = try await Fixture.load(count: count).freshP2().context([])
        let p = try Intent.Prepared(fixture.request), received = try Intent.Received(prepared: p, request: fixture.request)
        let ids = try originals(fixture, p)
        let plan = try Values.Plan(prepared: p, received: received,
            header: SharedMediaNativeAppMetadataFacts.successor(fixture.request.header),
            releaseID: UUID(), acquisitionIDs: ids)
        let bound = try Values.slotBound(plan: plan, prepared: p, received: received, acquisitionIDs: ids)
        let initial = try Values.Progress(plan: plan)
        #expect(try initial.remainingAdvances == Int64(4 * count + 2))
        let pairs = plan.targets.map { _ in Values.PairAssertion(retirementID: UUID(), closureSHA256: String(repeating: "a", count: 64)) }
        let originals = plan.targets.map { _ in Values.OriginalAssertion(disposition: .removed,
            retirementID: UUID(), closureSHA256: String(repeating: "b", count: 64)) }
        let combinations = count == 1 ? 6 : 36
        var largest = 0
        // 0 ready; 1 retiring pair; 2 pair gone; 3 original retiring;
        // 4 removed last; 5 removed shared. Include both processing orders.
        for code in 0..<combinations {
            let stages = count == 1 ? [code] : [code % 6, code / 6]
            var forward = initial, reverse = initial
            for index in 0..<count {
                forward = try advance(forward, index: index, destination: stages[index], pair: pairs[index], original: originals[index])
            }
            for index in (0..<count).reversed() {
                reverse = try advance(reverse, index: index, destination: stages[index], pair: pairs[index], original: originals[index])
            }
            #expect(forward == reverse)
            let bytes = try forward.encoded()
            largest = max(largest, bytes.count)
            #expect(Int64(bytes.count) <= bound.maximumProgressBytes)
            #expect(try Values.Progress.decode(bytes) == forward)
            #expect(throws: (any Error).self) { _ = try Values.Progress.decode(Data(" ".utf8) + bytes) }
            let remaining = try forward.remainingAdvances
            try forward.requireRevisionCapacity(inventoryRevision: Int64.max - remaining)
            #expect(throws: (any Error).self) {
                try forward.requireRevisionCapacity(inventoryRevision: Int64.max - remaining + 1)
            }
            if stages.allSatisfy({ $0 >= 4 }) {
                let terminal = try Values.Released(progress: forward, inventoryRevision: .max)
                try terminal.requireMatch(forward)
                #expect(Int64(try terminal.encoded().count) <= bound.maximumReleasedBytes)
                #expect(terminal.releasingSHA256 == initial.releasingSHA256)
                #expect(try forward.remainingAdvances == 2)
                #expect(throws: (any Error).self) { try terminal.requireMatch(initial) }
            } else {
                #expect(throws: (any Error).self) { _ = try Values.Released(progress: forward, inventoryRevision: .max) }
            }
        }
        print("Release progress size: originals=\(count), states=\(combinations), observed=\(largest), maximum=\(bound.maximumProgressBytes), replaced=\(bound.replacedBytes)")
        let first = try initial.advancing(.init(pairID: plan.targets[0].pairID, stage: .retiringPair, pair: pairs[0], original: nil))
        #expect(throws: (any Error).self) { _ = try first.advancing(first.targets[0]) }
        #expect(throws: (any Error).self) {
            _ = try first.advancing(.init(pairID: plan.targets[0].pairID, stage: .pairGoneOriginalLive,
                pair: .init(retirementID: UUID(), closureSHA256: pairs[0].closureSHA256), original: nil))
        }
        #expect(throws: (any Error).self) {
            _ = try initial.advancing(.init(pairID: plan.targets[0].pairID, stage: .removed, pair: pairs[0], original: originals[0]))
        }
        for replacement: [String: Any] in [
            ["format": "nativeReceivingReleasingProgressV2"], ["releasingSHA256": String(repeating: "b", count: 64)],
            ["targets": []]
        ] {
            #expect(throws: (any Error).self) {
                let invalid: Values.Progress = try Fixture.copy(first, changes: replacement)
                _ = try invalid.encoded()
            }
        }
        #expect(throws: (any Error).self) {
            _ = try initial.advancing(.init(pairID: plan.targets[0].pairID, stage: .retiringPair,
                pair: .init(retirementID: plan.releaseID, closureSHA256: pairs[0].closureSHA256), original: nil))
        }
        if count == 2 {
            #expect(throws: (any Error).self) {
                _ = try first.advancing(.init(pairID: plan.targets[1].pairID, stage: .retiringPair, pair: pairs[0], original: nil))
            }
            let reordered: Values.Progress = try Fixture.copy(first, changes: ["targets": first.targets.reversed().map(Fixture.object)])
            #expect(throws: (any Error).self) { _ = try reordered.encoded() }
        }
        #expect(throws: (any Error).self) {
            try Values.TargetProgress(pairID: plan.targets[0].pairID, stage: .retiringPair, pair: nil, original: nil).validate()
        }
        #expect(throws: (any Error).self) {
            try Values.TargetProgress(pairID: plan.targets[0].pairID, stage: .originalRetiring, pair: pairs[0],
                original: .init(disposition: .shared, retirementID: nil, closureSHA256: String(repeating: "b", count: 64))).validate()
        }
    }

    @Test(arguments: [1, 2])
    func composedProjectionRecalculatesEverySurvivorAndFitsExistingMetadata(_ count: Int) async throws {
        for support in ["", String(repeating: "\"\\\n🦋", count: 200)] {
            let fixture = try await Fixture.load(count: count).freshP2().context(support)
            let p = try Intent.Prepared(fixture.request), received = try Intent.Received(prepared: p, request: fixture.request)
            let ids = try originals(fixture, p), frozen = try fixture.request.frozenPackage()
            let header = try SharedMediaNativeAppMetadataFacts.successor(fixture.request.header)
            let plan = try Values.Plan(prepared: p, received: received, header: header, releaseID: UUID(), acquisitionIDs: ids)
            let states = fixture.states.map { state in
                let old = state.plan
                let next = SharedMediaNativePairPlan(intent: old.intent, writerEpoch: old.writerEpoch,
                    inventoryID: old.inventoryID, inventoryGeneration: old.inventoryGeneration,
                    inventoryRevision: header.inventory.revision, packageID: old.packageID,
                    draftGeneration: old.draftGeneration, packageRevision: frozen.revision, envelope: frozen.envelope,
                    membershipRevision: old.membershipRevision, membership: old.membership)
                return SharedMediaNativePairFileState(plan: next, phase: state.phase,
                    publishedRevision: state.publishedRevision, allocatedBytes: state.allocatedBytes, work: state.work)
            }
            let current = try SharedMediaNativeReceivingReservation.successor(p, header: fixture.request.header,
                currentMetadata: fixture.metadata(), pairStates: fixture.states)
            let projection = try SharedMediaNativeReceivingReleaseProjection.maximum(plan: plan, prepared: p,
                received: received, acquisitionIDs: ids, currentMetadata: current, pairStates: states)
            try projection.requireExistingReservation()
            #expect(projection.additionalReservation == 0)
            #expect(projection.statesExamined == (count == 1 ? 6 : 36))
            // A larger unchanged residual is retained exactly. This arithmetic
            // cap check is not persisted exact-cap/end-to-end qualification.
            let boundary = try SharedMediaNativeReceivingReleaseProjection.maximum(plan: plan, prepared: p,
                received: received, acquisitionIDs: ids, currentMetadata: PhotoPreparationPolicy.metadata, pairStates: states)
            try boundary.requireExistingReservation()
            #expect(boundary.maximumIntermediateBytes - projection.maximumIntermediateBytes == PhotoPreparationPolicy.metadata - current)
            #expect(throws: (any Error).self) {
                _ = try SharedMediaNativeReceivingReleaseProjection.maximum(plan: plan, prepared: p,
                    received: received, acquisitionIDs: ids, currentMetadata: PhotoPreparationPolicy.metadata + 1, pairStates: states)
            }
            #expect(throws: (any Error).self) {
                _ = try SharedMediaNativeReceivingReleaseProjection.maximum(plan: plan, prepared: p,
                    received: received, acquisitionIDs: ids, currentMetadata: current, pairStates: fixture.states)
            }
            print("Release composed size: originals=\(count), support=\(support.utf8.count), received=\(current), maximum=\(projection.maximumIntermediateBytes), states=\(projection.statesExamined)")
        }
    }

    @Test(arguments: [1, 2])
    func exactReleaseStatePreservesFrozenContentAndSettlesLogicalMembership(_ count: Int) async throws {
        let fixture = try await Fixture.load(count: count).freshP2().context("Submitted support stays immutable")
        let p = try Intent.Prepared(fixture.request), received = try Intent.Received(prepared: p, request: fixture.request)
        let plan = try Values.Plan(prepared: p, received: received,
            header: SharedMediaNativeAppMetadataFacts.successor(fixture.request.header),
            releaseID: UUID(), acquisitionIDs: originals(fixture, p))
        let frozen = try fixture.request.frozenPackage()
        let intents = try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes).entries.map {
            try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes)
        }
        let pairs = plan.targets.map { _ in Values.PairAssertion(retirementID: UUID(), closureSHA256: String(repeating: "a", count: 64)) }
        let originals = plan.targets.map { _ in Values.OriginalAssertion(disposition: .removed,
            retirementID: UUID(), closureSHA256: String(repeating: "b", count: 64)) }
        for code in 0..<(count == 1 ? 6 : 36) {
            let stages = count == 1 ? [code] : [code % 6, code / 6]
            var forward = try Values.Progress(plan: plan), reverse = forward
            for index in 0..<count {
                forward = try advance(forward, index: index, destination: stages[index], pair: pairs[index], original: originals[index])
            }
            for index in (0..<count).reversed() {
                reverse = try advance(reverse, index: index, destination: stages[index], pair: pairs[index], original: originals[index])
            }
            let expected = try SharedMediaNativeReceivingReleaseState.expected(forward, prepared: p, received: received)
            #expect(expected == (try SharedMediaNativeReceivingReleaseState.expected(reverse, prepared: p, received: received)))
            let steps = Int64(stages.map { [0, 1, 2, 3, 4, 3][$0] }.reduce(0, +))
            #expect(expected.completedSteps == steps)
            #expect(expected.package.revision == frozen.revision + steps)
            #expect(expected.member.revision == p.member.revision + steps)
            #expect(expected.slotRevision == plan.preparedRevision + 2 + steps)
            #expect(expected.minimumInventoryRevision == plan.preHeader.inventory.revision + 1 + steps)
            #expect(expected.package.envelope == frozen.envelope && expected.package.phase == "preparedHeld")
            let membership = try SharedMediaMembership.decode(expected.member.bytes)
            var settledBytes: Int64 = 0
            for (index, target) in plan.targets.enumerated() {
                let stage = stages[index], intent = intents[index]
                #expect(membership.ids(.pair).contains(target.pairID) == (stage <= 1))
                for output in [target.ai, target.display] {
                    #expect(membership.ids(.derivative).contains(output.workID) == (stage <= 1))
                    #expect(membership.ids(.asset).contains(output.assetID) == (stage <= 1))
                    #expect(membership.ids(.work).contains(output.leaseID) == (stage == 1))
                    #expect(membership.ids(.lease).contains(output.leaseID) == (stage == 1))
                }
                for kind in [SharedMediaMembership.Kind.asset, .allocation] {
                    #expect(membership.ids(kind).contains(target.original.assetID) == (stage < 4))
                }
                for kind in [SharedMediaMembership.Kind.reference, .edge] {
                    #expect(membership.ids(kind).contains(target.original.referenceID) == (stage < 4))
                }
                #expect(membership.ids(.lease).contains(target.acquisitionID) == (stage < 4))
                if stage >= 2 { settledBytes += intent.ai.byteCount + intent.display.byteCount }
                if stage >= 4 { settledBytes += intent.preparation.original.byteCount }
            }
            #expect(expected.package.allocated == frozen.allocated - settledBytes)
            if stages.allSatisfy({ $0 >= 4 }) { #expect(membership.groups.isEmpty && expected.package.allocated == 0) }
            try expected.require(package: expected.package, member: expected.member,
                slotRevision: expected.slotRevision, inventoryRevision: expected.minimumInventoryRevision + 7)
            #expect(throws: (any Error).self) {
                try expected.require(package: expected.package, member: expected.member,
                    slotRevision: expected.slotRevision, inventoryRevision: expected.minimumInventoryRevision - 1)
            }
        }
    }

    @Test(arguments: ["acquisition", "membership", "allocated"])
    func exactReleaseStateRejectsUnaccountedInitialInputs(_ fault: String) async throws {
        let fixture = try await Fixture.load(count: 1).freshP2()
        var p = try Intent.Prepared(fixture.request)
        if fault == "membership" {
            let initial = try SharedMediaMembership.decode(p.member.bytes)
            let groups = initial.groups.map { group in
                SharedMediaMembership.Group(kind: group.kind,
                    ids: (group.ids + (group.kind == .asset ? [UUID()] : [])).sorted { $0.uuidString < $1.uuidString })
            }
            let member = try Fixture.copy(p.member, changes: ["bytes": SharedMediaMembership(groups: groups).encoded().base64EncodedString()])
            p = try Fixture.copy(p, changes: ["member": Fixture.object(member)])
        } else if fault == "allocated" {
            let package = try Fixture.copy(p.package, changes: ["allocated": p.package.allocated + 1])
            p = try Fixture.copy(p, changes: ["package": Fixture.object(package)])
        }
        let request = try p.descriptorForTransaction(header: fixture.request.header)
        let received = try Intent.Received(prepared: p, request: request)
        let ids = fault == "acquisition" ? [UUID()] : try originals(fixture, p)
        let plan = try Values.Plan(prepared: p, received: received,
            header: SharedMediaNativeAppMetadataFacts.successor(request.header), releaseID: UUID(), acquisitionIDs: ids)
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeReceivingReleaseState.expected(Values.Progress(plan: plan), prepared: p, received: received)
        }
    }

    @Test(arguments: ["slot", "inventory", "package", "member"])
    func exactReleaseStateRejectsRevisionOverflow(_ counter: String) async throws {
        let fixture = try await Fixture.load(count: 1).freshP2()
        var p = try Intent.Prepared(fixture.request)
        if counter == "slot" {
            p = try Fixture.copy(p, changes: ["intentRevision": Int64.max - 3, "restagedFromSHA256": String(repeating: "a", count: 64)])
        } else if counter == "package" {
            let package = try Fixture.copy(p.package, changes: ["revision": Int64.max - 2])
            p = try Fixture.copy(p, changes: ["package": Fixture.object(package)])
        } else if counter == "member" {
            let member = try Fixture.copy(p.member, changes: ["revision": Int64.max - 1])
            p = try Fixture.copy(p, changes: ["member": Fixture.object(member)])
        }
        let request = try p.descriptorForTransaction(header: fixture.request.header)
        let received = try Intent.Received(prepared: p, request: request)
        var header = try SharedMediaNativeAppMetadataFacts.successor(request.header)
        if counter == "inventory" {
            let inventory = try Fixture.copy(header.inventory, changes: ["revision": Int64.max - 2])
            header = try Fixture.copy(header, changes: ["inventory": Fixture.object(inventory)])
        }
        let plan = try Values.Plan(prepared: p, received: received, header: header,
            releaseID: UUID(), acquisitionIDs: originals(fixture, p))
        let first = try Values.Progress(plan: plan).advancing(.init(pairID: plan.targets[0].pairID,
            stage: .retiringPair, pair: .init(retirementID: UUID(), closureSHA256: String(repeating: "a", count: 64)), original: nil))
        _ = try SharedMediaNativeReceivingReleaseState.expected(first, prepared: p, received: received)
        let next = try first.advancing(.init(pairID: plan.targets[0].pairID,
            stage: .pairGoneOriginalLive, pair: first.targets[0].pair, original: nil))
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeReceivingReleaseState.expected(next, prepared: p, received: received)
        }
    }

    private func advance(_ progress: Values.Progress, index: Int, destination: Int,
                         pair: Values.PairAssertion, original: Values.OriginalAssertion) throws -> Values.Progress {
        var next = progress
        let pairID = progress.plan.targets[index].pairID
        if destination >= 1 { next = try next.advancing(.init(pairID: pairID, stage: .retiringPair, pair: pair, original: nil)) }
        if destination >= 2 { next = try next.advancing(.init(pairID: pairID, stage: .pairGoneOriginalLive, pair: pair, original: nil)) }
        if destination == 5 {
            return try next.advancing(.init(pairID: pairID, stage: .removed, pair: pair,
                original: .init(disposition: .shared, retirementID: nil, closureSHA256: original.closureSHA256)))
        }
        if destination >= 3 { next = try next.advancing(.init(pairID: pairID, stage: .originalRetiring, pair: pair, original: original)) }
        if destination >= 4 { next = try next.advancing(.init(pairID: pairID, stage: .removed, pair: pair, original: original)) }
        return next
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
