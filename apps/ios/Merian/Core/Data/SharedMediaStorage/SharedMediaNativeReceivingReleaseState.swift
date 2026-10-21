import Foundation

/// Exact value expectation for the future sealed release writer. Unlike the
/// capacity projection, this removes every settled package membership ID.
/// No row, file, saved-transition or mutation authority is established here.
enum SharedMediaNativeReceivingReleaseState {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Facts = SharedMediaNativeAppMetadataFacts
    typealias Intent = SharedMediaNativeReceivingIntent
    private typealias Groups = [SharedMediaMembership.Kind: Set<UUID>]

    struct Expected: Equatable, Sendable {
        let package: Facts.Package
        let member: Facts.Member
        let slotRevision: Int64
        let minimumInventoryRevision: Int64
        let completedSteps: Int64

        /// Scalar comparison only. The caller still owes the live raw-row,
        /// ownership, transition-attestation and aggregate revision audits.
        func require(package: Facts.Package, member: Facts.Member,
                     slotRevision: Int64, inventoryRevision: Int64) throws {
            guard self.package == package, self.member == member,
                  self.slotRevision == slotRevision,
                  inventoryRevision >= minimumInventoryRevision else {
                throw SharedMediaStorageFailure.stale
            }
        }
    }

    static func expected(_ progress: Values.Progress, prepared: Intent.Prepared,
                         received: Intent.Received) throws -> Expected {
        try progress.validate()
        let plan = progress.plan
        try plan.requireMatch(prepared: prepared, received: received,
            acquisitionIDs: plan.targets.map(\.acquisitionID))
        let transaction = try received.reconstruct(prepared)
        var package = try transaction.frozenPackage(), member = transaction.member
        let cohort = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        var initial: Groups = [:], current: Groups = [:]
        var initialBytes: Int64 = 0, remainingBytes: Int64 = 0, steps: Int64 = 0
        for (index, target) in plan.targets.enumerated() {
            let intent = try SharedMediaNativeDerivativeIntent.decode(cohort.entries[index].intent.bytes)
            let state = progress.targets[index]
            let originalBytes = intent.preparation.original.byteCount
            let outputBytes = try SharedMediaStoragePolicy.add(intent.ai.byteCount, intent.display.byteCount)
            initialBytes = try PhotoPreparationPolicy.add([initialBytes, originalBytes, outputBytes])
            try includeOriginal(target, in: &initial)
            try includePair(target, in: &initial)
            if state.stage != .removed {
                try includeOriginal(target, in: &current)
                remainingBytes = try SharedMediaStoragePolicy.add(remainingBytes, originalBytes)
            }
            if state.stage == .readyPair || state.stage == .retiringPair {
                try includePair(target, in: &current)
                remainingBytes = try SharedMediaStoragePolicy.add(remainingBytes, outputBytes)
            }
            if state.stage == .retiringPair {
                for output in [target.ai, target.display] {
                    try insert(output.leaseID, kinds: [.work, .lease], in: &current)
                }
            }
            // The original-retirement save advances membership revision even
            // while retaining the same retired reference and physical IDs.
            let count: Int64
            switch state.stage {
            case .readyPair: count = 0
            case .retiringPair: count = 1
            case .pairGoneOriginalLive: count = 2
            case .originalRetiring: count = 3
            case .removed: count = state.original?.disposition == .shared ? 3 : 4
            }
            steps = try SharedMediaStoragePolicy.add(steps, count)
        }
        // This cohort owns exactly these package IDs and logical bytes. A
        // different acquisition identity or unrelated membership cannot vanish
        // simply because the proposed final membership looks self-consistent.
        guard try encode(initial) == member.bytes, initialBytes == package.allocated,
              remainingBytes <= initialBytes else { throw SharedMediaStorageFailure.conflict }
        let bytes = try encode(current)
        for _ in 0..<steps {
            package = try package.successor(package.envelope, allocated: remainingBytes)
            member = try member.successor(bytes)
        }
        return Expected(package: package, member: member,
            slotRevision: try SharedMediaStoragePolicy.add(plan.releasingRevision, steps),
            minimumInventoryRevision: try PhotoPreparationPolicy.add([plan.preHeader.inventory.revision, 1, steps]),
            completedSteps: steps)
    }

    private static func includeOriginal(_ target: Values.Target, in groups: inout Groups) throws {
        try insert(target.original.assetID, kinds: [.asset, .allocation], in: &groups)
        try insert(target.original.referenceID, kinds: [.reference, .edge], in: &groups)
        try insert(target.acquisitionID, kinds: [.lease], in: &groups)
    }
    private static func includePair(_ target: Values.Target, in groups: inout Groups) throws {
        try insert(target.pairID, kinds: [.pair], in: &groups)
        for output in [target.ai, target.display] {
            try insert(output.workID, kinds: [.derivative], in: &groups)
            try insert(output.assetID, kinds: [.asset, .allocation], in: &groups)
            try insert(output.referenceID, kinds: [.reference, .edge], in: &groups)
        }
    }
    private static func insert(_ id: UUID, kinds: [SharedMediaMembership.Kind], in groups: inout Groups) throws {
        for kind in kinds {
            guard groups[kind, default: []].insert(id).inserted else { throw SharedMediaStorageFailure.conflict }
        }
    }
    private static func encode(_ groups: Groups) throws -> Data {
        try SharedMediaMembership(groups: groups.map { kind, ids in
            .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
        }.sorted { $0.kind.rawValue < $1.kind.rawValue }).encoded()
    }
}
