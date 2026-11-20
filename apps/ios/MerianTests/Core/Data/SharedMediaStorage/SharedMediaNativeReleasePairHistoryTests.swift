import Foundation
import Testing
@testable import Merian

@Suite("Held-release historical pair proof", .serialized)
@MainActor
struct SharedMediaNativeReleasePairHistoryTests {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Fixture = SharedMediaNativeReceivingTestFixture
    typealias History = SharedMediaNativeReleasePairHistory

    @Test(arguments: [1, 2])
    func completeLegalPredecessorsSurviveLaterInventoryAndSiblingProgress(_ count: Int) async throws {
        let fixture = try await Fixture.load(count: count).freshP2()
        let p = try Intent.Prepared(fixture.request), r = try Intent.Received(prepared: p, request: fixture.request)
        let plan = try makePlan(fixture, p, r), initial = try Values.Progress(plan: plan)
        let siblingPair = Values.PairAssertion(retirementID: UUID(), closureSHA256: String(repeating: "a", count: 64))
        let siblingOriginal = Values.OriginalAssertion(disposition: .removed, retirementID: UUID(), closureSHA256: String(repeating: "b", count: 64))
        for currentStage in (count == 1 ? [0] : Array(0...5)) {
            let path = currentStage == 5 ? [0, 1, 2, 5] : Array(0...currentStage)
            for priorStage in path {
                let prior = count == 1 ? initial : try advance(initial, index: 1, stage: priorStage,
                    pair: siblingPair, original: siblingOriginal)
                let closure = try makeClosure(fixture, prior, p, r)
                let assertion = Values.PairAssertion(retirementID: closure.retirementID,
                    closureSHA256: SharedMediaNativePairClosure.digest(Data(try closure.encoded().utf8)))
                let sibling = count == 1 ? initial : try advance(initial, index: 1, stage: currentStage,
                    pair: siblingPair, original: siblingOriginal)
                let current = try sibling.advancing(.init(pairID: plan.targets[0].pairID,
                    stage: .retiringPair, pair: assertion, original: nil))
                let expected = try SharedMediaNativeReceivingReleaseState.expected(current, prepared: p, received: r)
                let inventory = max(expected.minimumInventoryRevision, closure.previous.inventoryRevision + 1) + 11
                let before = try History.validate(closure, progress: current, prepared: p, received: r, inventoryRevision: inventory)
                #expect(before.plan.membership == closure.previous.membership)
                #expect(before.allocatedBytes == closure.previous.allocatedBytes)
                #expect(before.plan.packageRevision == closure.previous.packageRevision)
                #expect(before.plan.inventoryRevision == closure.previous.inventoryRevision)
                #expect(throws: (any Error).self) {
                    _ = try History.validate(closure, progress: current, prepared: p, received: r,
                        inventoryRevision: closure.previous.inventoryRevision)
                }
                let altered = try Fixture.copy(closure, changes: ["beforeHash": String(repeating: "c", count: 64)])
                #expect(throws: (any Error).self) {
                    _ = try History.validate(altered, progress: current, prepared: p, received: r, inventoryRevision: inventory)
                }
            }
        }
    }

    @Test func canonicalRehashedFaultsCannotInventHistoricalStates() async throws {
        let fixture = try await Fixture.load(count: 2).freshP2()
        let p = try Intent.Prepared(fixture.request), r = try Intent.Received(prepared: p, request: fixture.request)
        let plan = try makePlan(fixture, p, r), initial = try Values.Progress(plan: plan)
        let closure = try makeClosure(fixture, initial, p, r)
        let control = try initial.advancing(.init(pairID: plan.targets[0].pairID, stage: .retiringPair,
            pair: .init(retirementID: closure.retirementID,
                closureSHA256: SharedMediaNativePairClosure.digest(Data(try closure.encoded().utf8))), original: nil))
        _ = try History.validate(closure, progress: control, prepared: p, received: r,
            inventoryRevision: closure.previous.inventoryRevision + 20)
        // Recompute all inner hashes so these cases isolate the frozen-ready
        // boundary rather than incidentally failing on a stale beforeHash.
        for phase in ["writing", "ready"] {
            let previous = try Fixture.copy(closure.previous, changes: ["phase": phase, "publishedRevision": NSNull()])
            let invalid = try rehash(closure, previous: previous, fixture: fixture)
            let current = try initial.advancing(.init(pairID: plan.targets[0].pairID, stage: .retiringPair,
                pair: .init(retirementID: invalid.retirementID,
                    closureSHA256: SharedMediaNativePairClosure.digest(Data(try invalid.encoded().utf8))), original: nil))
            #expect(throws: (any Error).self) {
                _ = try History.validate(invalid, progress: current, prepared: p, received: r,
                    inventoryRevision: closure.previous.inventoryRevision + 20)
            }
        }
        let changes: [[String: Any]] = [
            ["previous": try Fixture.object(Fixture.copy(closure.previous, changes: ["allocatedBytes": closure.previous.allocatedBytes + 1]))],
            ["previous": try Fixture.object(Fixture.copy(closure.previous, changes: ["packageRevision": closure.previous.packageRevision + 1]))],
            ["previous": try Fixture.object(Fixture.copy(closure.previous, changes: ["membershipRevision": closure.previous.membershipRevision + 1]))],
            ["previous": try Fixture.object(Fixture.copy(closure.previous, changes: ["membership": Data().base64EncodedString()]))],
            ["previous": try Fixture.object(Fixture.copy(closure.previous, changes: ["inventoryRevision": -1]))],
            ["previous": try Fixture.object(Fixture.copy(closure.previous, changes: ["inventoryRevision": Int64.max]))],
            ["afterMembershipRevision": closure.afterMembershipRevision + 1],
            ["afterMembershipHash": String(repeating: "d", count: 64)],
            ["beforeHash": String(repeating: "d", count: 64)],
            ["intentHash": String(repeating: "d", count: 64)],
            ["envelopeHash": String(repeating: "d", count: 64)],
            ["inventoryGeneration": UUID().uuidString],
            ["packageID": UUID().uuidString],
            ["draftGeneration": UUID().uuidString]
        ]
        for change in changes {
            let invalid = try Fixture.copy(closure, changes: change)
            let assertion = Values.PairAssertion(retirementID: invalid.retirementID,
                closureSHA256: SharedMediaNativePairClosure.digest(Data(try invalid.encoded().utf8)))
            let current = try initial.advancing(.init(pairID: plan.targets[0].pairID,
                stage: .retiringPair, pair: assertion, original: nil))
            #expect(throws: (any Error).self) {
                _ = try History.validate(invalid, progress: current, prepared: p, received: r,
                    inventoryRevision: closure.previous.inventoryRevision + 20)
            }
        }
        // These fields individually occur in valid predecessor states, but not
        // together. Rehashing this canonical proof does not make it a transition.
        let other = try advance(initial, index: 1, stage: 2,
            pair: .init(retirementID: UUID(), closureSHA256: String(repeating: "a", count: 64)),
            original: .init(disposition: .removed, retirementID: UUID(), closureSHA256: String(repeating: "b", count: 64)))
        let later = try makeClosure(fixture, other, p, r)
        let tornPrevious = try Fixture.copy(later.previous, changes: ["membership": closure.previous.membership.base64EncodedString()])
        let torn = try rehash(later, previous: tornPrevious, fixture: fixture)
        let current = try other.advancing(.init(pairID: plan.targets[0].pairID, stage: .retiringPair,
            pair: .init(retirementID: torn.retirementID, closureSHA256: SharedMediaNativePairClosure.digest(Data(try torn.encoded().utf8))), original: nil))
        #expect(throws: (any Error).self) {
            _ = try History.validate(torn, progress: current, prepared: p, received: r,
                inventoryRevision: torn.previous.inventoryRevision + 20)
        }
    }

    private func rehash(_ closure: SharedMediaNativePairClosure,
                        previous: SharedMediaNativePairClosure.Previous, fixture: Fixture) throws -> SharedMediaNativePairClosure {
        let before = try SharedMediaNativePairFileState(plan: .init(intent: fixture.states[0].plan.intent,
            writerEpoch: closure.writerEpoch, inventoryID: closure.inventoryID,
            inventoryGeneration: closure.inventoryGeneration, inventoryRevision: previous.inventoryRevision,
            packageID: closure.packageID, draftGeneration: closure.draftGeneration,
            packageRevision: previous.packageRevision, envelope: fixture.request.frozenPackage().envelope,
            membershipRevision: previous.membershipRevision, membership: previous.membership),
            phase: previous.phase, publishedRevision: previous.publishedRevision,
            allocatedBytes: previous.allocatedBytes, work: closure.entries.map(\.work))
        return try Fixture.copy(closure, changes: ["previous": Fixture.object(previous),
            "beforeHash": SharedMediaNativePairClosure.digest(SharedMediaNativeDraftEnvelope.bytes(before)),
            "afterMembershipHash": SharedMediaNativePairClosure.digest(SharedMediaNativePairClosure.retirementMembership(before)),
            "afterMembershipRevision": previous.membershipRevision + 1])
    }

    private func makePlan(_ fixture: Fixture, _ prepared: Intent.Prepared, _ received: Intent.Received) throws -> Values.Plan {
        let ids = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes).entries.map { entry in
            let assetID = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes).preparation.original.reference.assetID
            return try #require(fixture.receipts.first { $0.0.assetID == assetID }).0.operationID
        }
        return try Values.Plan(prepared: prepared, received: received,
            header: SharedMediaNativeAppMetadataFacts.successor(fixture.request.header), releaseID: UUID(), acquisitionIDs: ids)
    }

    private func advance(_ progress: Values.Progress, index: Int, stage: Int,
                         pair: Values.PairAssertion, original: Values.OriginalAssertion) throws -> Values.Progress {
        var result = progress
        let sequence: [Values.TargetProgress.Stage] = stage == 5
            ? [.retiringPair, .pairGoneOriginalLive, .removed]
            : Array([.retiringPair, .pairGoneOriginalLive, .originalRetiring, .removed].prefix(stage))
        for value in sequence {
            let proof: Values.OriginalAssertion? = value == .originalRetiring || value == .removed
                ? (stage == 5 ? .init(disposition: .shared, retirementID: nil, closureSHA256: original.closureSHA256) : original) : nil
            result = try result.advancing(.init(pairID: progress.targets[index].pairID, stage: value, pair: pair, original: proof))
        }
        return result
    }

    private func makeClosure(_ fixture: Fixture, _ prior: Values.Progress,
                             _ prepared: Intent.Prepared, _ received: Intent.Received) throws -> SharedMediaNativePairClosure {
        let expected = try SharedMediaNativeReceivingReleaseState.expected(prior, prepared: prepared, received: received)
        let source = fixture.states[0], plan = prior.plan
        let entry = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes).entries[0]
        let old = SharedMediaNativePairFileState(plan: .init(intent: entry.intent, writerEpoch: source.plan.writerEpoch,
            inventoryID: plan.profile.inventoryID, inventoryGeneration: plan.profile.generation,
            inventoryRevision: expected.minimumInventoryRevision + 7, packageID: plan.package.id,
            draftGeneration: plan.package.generation, packageRevision: expected.package.revision,
            envelope: expected.package.envelope, membershipRevision: expected.member.revision, membership: expected.member.bytes),
            phase: "ready", publishedRevision: source.publishedRevision, allocatedBytes: expected.package.allocated, work: source.work)
        let entries = zip(source.work, [entry.aiDescriptor, entry.displayDescriptor]).map { work, descriptor in
            SharedMediaNativePairClosure.Entry(work: work, mode: .bound,
                identity: .init(partial: "absent", final: descriptor.file, parent: descriptor.parent, namespace: descriptor.namespace))
        }
        return SharedMediaNativePairClosure(version: 1, retirementID: UUID(), pairID: plan.targets[0].pairID,
            inventoryID: plan.profile.inventoryID, inventoryGeneration: plan.profile.generation,
            packageID: plan.package.id, draftGeneration: plan.package.generation, writerEpoch: source.plan.writerEpoch,
            beforeHash: SharedMediaNativePairClosure.digest(try SharedMediaNativeDraftEnvelope.bytes(old)),
            intentHash: entry.intent.sha256, envelopeHash: plan.package.envelopeSHA256,
            afterMembershipHash: SharedMediaNativePairClosure.digest(try SharedMediaNativePairClosure.retirementMembership(old)),
            afterMembershipRevision: expected.member.revision + 1,
            previous: .init(inventoryRevision: old.plan.inventoryRevision, packageRevision: expected.package.revision,
                membershipRevision: expected.member.revision, membership: expected.member.bytes,
                phase: "ready", publishedRevision: source.publishedRevision, allocatedBytes: expected.package.allocated), entries: entries)
    }
}
