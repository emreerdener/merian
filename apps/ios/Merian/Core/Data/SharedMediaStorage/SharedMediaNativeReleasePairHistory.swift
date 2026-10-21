import Foundation

/// Historical value checks only. The enclosing reader still owes the current
/// slot, complete live rows and aggregate state audit. No save or file authority.
/// Frozen receiving cohorts contain ready/completed pairs only (FreezeFacts and
/// ReceivingIntentGraph). Generic unfinished-pair retirement is a separate path;
/// its writing/unbound closures are intentionally not accepted here.
enum SharedMediaNativeReleasePairHistory {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias State = SharedMediaNativeReceivingReleaseState

    static func validate(_ closure: SharedMediaNativePairClosure, progress: Values.Progress,
                         prepared: Intent.Prepared, received: Intent.Received,
                         inventoryRevision: Int64) throws -> SharedMediaNativePairFileState {
        let current = try State.expected(progress, prepared: prepared, received: received)
        let plan = progress.plan
        guard let index = plan.targets.firstIndex(where: { $0.pairID == closure.pairID }),
              progress.targets[index].stage == .retiringPair,
              let assertion = progress.targets[index].pair,
              assertion.retirementID == closure.retirementID,
              assertion.closureSHA256 == SharedMediaNativePairClosure.digest(Data(try closure.encoded().utf8)),
              inventoryRevision >= current.minimumInventoryRevision,
              closure.previous.inventoryRevision < inventoryRevision else { throw SharedMediaStorageFailure.conflict }
        let cohort = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let entry = cohort.entries[index], intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
        guard closure.inventoryID == plan.profile.inventoryID, closure.inventoryGeneration == plan.profile.generation,
              closure.packageID == plan.package.id, closure.draftGeneration == plan.package.generation,
              closure.intentHash == entry.intent.sha256, closure.envelopeHash == plan.package.envelopeSHA256,
              closure.previous.phase == "ready", let published = closure.previous.publishedRevision,
              published >= (try SharedMediaStoragePolicy.add(intent.preparation.packageRevision, 2)),
              published <= prepared.package.revision,
              closure.entries.map(\.work.id) == [intent.ai.id, intent.display.id] else {
            throw SharedMediaStorageFailure.conflict
        }
        for (item, descriptor) in zip(closure.entries, [entry.aiDescriptor, entry.displayDescriptor]) {
            guard item.mode == .bound, item.work.phase == "completed", item.work.writerState == "closed",
                  item.work.finalIdentity == descriptor.file,
                  item.identity.partial == "absent",
                  item.identity.final == "absent" || item.identity.final == descriptor.file,
                  item.identity.parent == descriptor.parent, item.identity.namespace == descriptor.namespace else {
                throw SharedMediaStorageFailure.conflict
            }
            let parts = descriptor.file.split(separator: ":")
            guard parts.count == 7, item.work.device == Int64(parts[0]), item.work.inode == Int64(parts[1]) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        // One complete predecessor must match. Combining individually matching
        // fields from different legal predecessors would admit a torn proof.
        for previous in try predecessors(progress, retiring: index) {
            let expected = try State.expected(previous, prepared: prepared, received: received)
            guard closure.previous.inventoryRevision >= expected.minimumInventoryRevision,
                  closure.previous.packageRevision == expected.package.revision,
                  closure.previous.membershipRevision == expected.member.revision,
                  closure.previous.membership == expected.member.bytes,
                  closure.previous.allocatedBytes == expected.package.allocated else { continue }
            let before = SharedMediaNativePairFileState(plan: .init(intent: entry.intent,
                writerEpoch: closure.writerEpoch, inventoryID: plan.profile.inventoryID,
                inventoryGeneration: plan.profile.generation, inventoryRevision: closure.previous.inventoryRevision,
                packageID: plan.package.id, draftGeneration: plan.package.generation,
                packageRevision: expected.package.revision, envelope: expected.package.envelope,
                membershipRevision: expected.member.revision, membership: expected.member.bytes),
                phase: "ready", publishedRevision: published, allocatedBytes: expected.package.allocated,
                work: closure.entries.map(\.work))
            let after = try SharedMediaNativePairClosure.retirementMembership(before)
            guard closure.beforeHash == SharedMediaNativePairClosure.digest(try SharedMediaNativeDraftEnvelope.bytes(before)),
                  closure.afterMembershipHash == SharedMediaNativePairClosure.digest(after),
                  closure.afterMembershipRevision == (try SharedMediaStoragePolicy.add(expected.member.revision, 1)),
                  (try SharedMediaStoragePolicy.add(closure.previous.inventoryRevision, 1)) <= inventoryRevision,
                  (try SharedMediaStoragePolicy.add(expected.package.revision, 1)) <= current.package.revision,
                  (try SharedMediaStoragePolicy.add(expected.member.revision, 1)) <= current.member.revision,
                  try closure.encoded().utf8.count + closure.siblingMarker().utf8.count <= SharedMediaNativePairClosure.maximumEncodingBytes(before) else {
                throw SharedMediaStorageFailure.conflict
            }
            return before
        }
        throw SharedMediaStorageFailure.conflict
    }

    /// At most one other target exists. Include its current stage as well as
    /// earlier stages on its actual branch; shared removal has no retirement.
    private static func predecessors(_ progress: Values.Progress, retiring index: Int) throws -> [Values.Progress] {
        let initial = try Values.Progress(plan: progress.plan)
        guard let other = progress.targets.indices.first(where: { $0 != index }) else { return [initial] }
        let target = progress.targets[other]
        var current = initial, result = [initial]
        if target.stage == .readyPair { return result }
        let stages: [Values.TargetProgress.Stage]
        switch target.stage {
        case .readyPair: stages = []
        case .retiringPair: stages = [.retiringPair]
        case .pairGoneOriginalLive: stages = [.retiringPair, .pairGoneOriginalLive]
        case .originalRetiring: stages = [.retiringPair, .pairGoneOriginalLive, .originalRetiring]
        case .removed:
            stages = target.original?.disposition == .shared
                ? [.retiringPair, .pairGoneOriginalLive, .removed]
                : [.retiringPair, .pairGoneOriginalLive, .originalRetiring, .removed]
        }
        for stage in stages {
            current = try current.advancing(.init(pairID: target.pairID, stage: stage, pair: target.pair,
                original: stage == .originalRetiring || stage == .removed ? target.original : nil))
            result.append(current)
        }
        return result
    }
}
