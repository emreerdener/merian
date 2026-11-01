import Foundation

/// Pure sizing over a clean metadata snapshot. No admission, reservation,
/// transition, filesystem or database authority is returned. Synthetic future
/// assertions exist only to size valid forward states; they are never saved.
@MainActor
enum SharedMediaNativeReleaseSurvivorProjection {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReleaseMetadataSnapshot.Snapshot

    /// Immutable sizing inputs, without a live-audit witness or database rows.
    /// Constructing these values grants no ownership, reservation or write right.
    /// A prospective start must supply its own exact audited predecessor proof.
    struct Components {
        let progress: Values.Progress
        let prepared: SharedMediaNativeReceivingIntent.Prepared
        let received: SharedMediaNativeReceivingIntent.Received
        let package: SharedMediaNativeAppMetadataFacts.Package
        let member: SharedMediaNativeAppMetadataFacts.Member
        let envelopeBytes: Int64
        let membershipBytes: Int64
        let consumerBytes: Int64
        let executionBytes: Int64
        let slotBytes: Int64
        let pairs: [SharedMediaNativePairFileState]
        let ownedOriginals: [SharedMediaNativeReleaseMetadataSnapshot.Original]
        let targetOrigins: [SharedMediaNativeReleaseMetadataSnapshot.TargetOrigin]
        var recoveryPresentationData: Data?
        var recoveryPresentation: AnalysisRecoveryPresentation.StorageLiability {
            get throws { try SharedMediaNativeReceivingRows.recoveryPresentation(recoveryPresentationData, prepared: prepared) }
        }

        var pairBytes: Int64 {
            get throws { try PhotoPreparationPolicy.add(pairs.map { Int64(try SharedMediaNativeDraftEnvelope.bytes($0).count) }) }
        }
        var packagePayloadBytes: Int64 {
            get throws { try PhotoPreparationPolicy.add([envelopeBytes, membershipBytes, consumerBytes, executionBytes, slotBytes, pairBytes]) }
        }
        var originReceiptBytes: Int64 {
            get throws { try PhotoPreparationPolicy.add(ownedOriginals.map(\.receiptBytes)) }
        }
        var originIdentityBytes: Int64 {
            get throws { try PhotoPreparationPolicy.add(ownedOriginals.map(\.identityBytes)) }
        }
        var currentSerializedBytes: Int64 {
            get throws { try PhotoPreparationPolicy.add([packagePayloadBytes, originReceiptBytes, originIdentityBytes]) }
        }
    }

    static func components(_ snapshot: Snapshot) -> Components {
        .init(progress: snapshot.release.progress, prepared: snapshot.release.origin.prepared,
            received: snapshot.release.origin.received, package: snapshot.release.state.package,
            member: snapshot.release.state.member, envelopeBytes: snapshot.envelopeBytes,
            membershipBytes: snapshot.membershipBytes, consumerBytes: snapshot.consumerBytes,
            executionBytes: snapshot.executionBytes, slotBytes: snapshot.slotBytes,
            pairs: snapshot.pairs, ownedOriginals: snapshot.ownedOriginals, targetOrigins: snapshot.targetOrigins,
            recoveryPresentationData: snapshot.recoveryPresentationData)
    }

    struct Charge: Equatable, Sendable {
        /// 0 ready, 1 pair retiring, 2 pair gone, 3 original retiring,
        /// 4 physically removed, 5 shared logical reference removed.
        let stages: [Int]
        let packageBytes: Int64
        let originReceiptBytes: Int64
        let originIdentityBytes: Int64
        let originBytes: Int64
        let terminal: Bool
        fileprivate init(stages: [Int], packageBytes: Int64, receipts: Int64, identities: Int64, terminal: Bool) throws {
            self.stages = stages; self.packageBytes = packageBytes
            originReceiptBytes = receipts; originIdentityBytes = identities
            originBytes = try PhotoPreparationPolicy.add([receipts, identities]); self.terminal = terminal
        }
        var total: Int64 { get throws { try PhotoPreparationPolicy.add([packageBytes, originBytes]) } }
        /// Same cap categories as the existing Budget: receipt payload belongs
        /// to its live physical-origin package; allocation identity does not.
        /// The terminal slot outlives that package and has its own cap.
        var metadataCapBytes: Int64 {
            get throws { try PhotoPreparationPolicy.add([packageBytes, terminal ? 0 : originReceiptBytes]) }
        }
    }
    struct Projection: Equatable, Sendable {
        let currentBytes: Int64
        let charges: [Charge]
        let maximumBytes: Int64
        let maximumPackagePayloadBytes: Int64
        let maximumLivePackageMetadataBytes: Int64
        let maximumTerminalSlotBytes: Int64
        /// Package payload plus owned receipts only. Global original identity
        /// current bytes/headroom remain the separate asset-owned budget pass.
        let currentIdentityExcludedBytes: Int64
        let maximumIdentityExcludedBytes: Int64
        /// Separate from immutable legacy B/S and terminal payloads. The queue
        /// owns this charge until its atomic removal, including exhausted values.
        let recoveryPresentation: AnalysisRecoveryPresentation.StorageLiability
        var futureGrowthBytes: Int64 { maximumBytes - currentBytes }
        /// Arithmetic feasibility only; no caller can admit or release media
        /// from this result. Global storage and revision gates remain separate.
        func requireMetadataCapacity() throws {
            guard try PhotoPreparationPolicy.add([maximumLivePackageMetadataBytes, recoveryPresentation.chargedBytes]) <= PhotoPreparationPolicy.metadata,
                  maximumTerminalSlotBytes <= PhotoPreparationPolicy.metadata else {
                throw SharedMediaStorageFailure.capacity
            }
        }
    }

    /// One synchronous audit context owns this memo. Only full immutable sizing
    /// values are retained; callers must discard it before any context/page await.
    /// The byte budget covers encoded payload/scalars, not allocator overhead;
    /// entry and array counts bound that overhead separately. Oversize keys simply
    /// use the unchanged uncached computation, never fail media admission.
    final class Memo {
        fileprivate struct Key: Equatable {
            let encoded: [Data]
            let counts: [Int64]
            let originals: [SharedMediaNativeReleaseMetadataSnapshot.Original]
            let origins: [SharedMediaNativeReleaseMetadataSnapshot.TargetOrigin]
            init?(_ s: Components, limit: Int64) throws {
                // Optimization-only limits. Extra physical origins remain valid
                // inputs; they just take the uncached path. At most two targets
                // are supported by Progress, but bound all retained arrays here.
                guard s.ownedOriginals.count <= 2, s.targetOrigins.count <= 2,
                      s.pairs.count <= 2 else { return nil }
                var values: [Data] = []
                var used = Int64(5 * 8 + s.ownedOriginals.count * 64 + s.targetOrigins.count * 256)
                guard used < limit else { return nil }
                func append<T: Encodable>(_ value: T) throws -> Bool {
                    guard used < limit else { return false }
                    let data = try SharedMediaAcquisitionEncoding.encode(value,
                        maximum: Int(min(PhotoPreparationPolicy.metadata, limit - used)))
                    used = try PhotoPreparationPolicy.add([used, Int64(data.count)])
                    values.append(data); return true
                }
                guard try append(s.progress), try append(s.prepared), try append(s.received),
                      try append(s.package), try append(s.member), try append(s.pairs),
                      try append(s.recoveryPresentationData) else { return nil }
                encoded = values
                counts = [s.envelopeBytes, s.membershipBytes, s.consumerBytes, s.executionBytes, s.slotBytes]
                originals = s.ownedOriginals; origins = s.targetOrigins
            }
            var bytes: Int64 {
                get throws {
                    try PhotoPreparationPolicy.add(encoded.map { Int64($0.count) }
                        + [Int64(counts.count) * 8, Int64(originals.count) * 64, Int64(origins.count) * 256])
                }
            }
        }
        private struct Entry { let key: Key; let projection: Projection; let bytes: Int64 }
        private var entries: [Entry] = []
        fileprivate let capacity: Int64
        init(byteLimit: Int64 = Memo.byteLimit) { capacity = max(0, min(byteLimit, Self.byteLimit)) }
        private(set) var hits = 0
        private(set) var retainedBytes: Int64 = 0
        var count: Int { entries.count }
        var isEmpty: Bool { entries.isEmpty }
        static let byteLimit = PhotoPreparationPolicy.metadata * Int64(PhotoPreparationPolicy.maximumPackages)
        fileprivate func lookup(_ key: Key) -> Projection? {
            guard let found = entries.first(where: { $0.key == key }) else { return nil }
            hits += 1; return found.projection
        }
        fileprivate func insert(_ projection: Projection, key: Key) {
            guard let bytes = try? PhotoPreparationPolicy.add([key.bytes, 128]
                + projection.charges.map { 64 + Int64($0.stages.count) * 8 }),
                bytes <= capacity else { return }
            while entries.count >= PhotoPreparationPolicy.maximumPackages || retainedBytes > capacity - bytes {
                retainedBytes -= entries.removeFirst().bytes
            }
            entries.append(.init(key: key, projection: projection, bytes: bytes)); retainedBytes += bytes
        }
    }

    static func maximum(_ snapshot: Snapshot) throws -> Projection {
        try maximum(components(snapshot))
    }

    static func maximum(_ snapshot: Components, memo: Memo? = nil) throws -> Projection {
        try Task.checkCancellation()
        let recoveryPresentation = try snapshot.recoveryPresentation
        let progress = snapshot.progress, plan = progress.plan
        try progress.validate()
        let slot = try Values.slotBound(plan: plan, prepared: snapshot.prepared,
            received: snapshot.received, acquisitionIDs: plan.targets.map(\.acquisitionID))
        try validateOrigins(snapshot)
        let current = try snapshot.currentSerializedBytes
        let replaced = try PhotoPreparationPolicy.add([snapshot.membershipBytes, snapshot.slotBytes,
            snapshot.pairBytes, snapshot.originReceiptBytes, snapshot.originIdentityBytes])
        let residual = try PhotoPreparationPolicy.add([snapshot.envelopeBytes, snapshot.consumerBytes, snapshot.executionBytes])
        guard current >= replaced, current - replaced == residual,
              snapshot.slotBytes == Int64(try progress.encoded().count),
              snapshot.membershipBytes == Int64(snapshot.member.bytes.count) else {
            throw SharedMediaStorageFailure.conflict
        }
        let bounds = try pairBounds(snapshot)
        // Validation above runs even on a hit. No cached graph, funding or
        // authority bypass; all caller postchecks also run after this returns.
        let key = memo.flatMap { try? Memo.Key(snapshot, limit: $0.capacity) }
        try Task.checkCancellation()
        if let key, let hit = memo?.lookup(key) { return hit }
        var combinations: [[Int]] = [[]]
        for target in progress.targets {
            combinations = combinations.flatMap { prefix in options(target).map { prefix + [$0] } }
        }
        var charges: [Charge] = [], maximum = current, maximumPackage = try snapshot.packagePayloadBytes
        var maximumLive = try PhotoPreparationPolicy.add([snapshot.packagePayloadBytes, snapshot.originReceiptBytes])
        let currentIdentityExcluded = maximumLive
        var maximumIdentityExcluded = currentIdentityExcluded
        var maximumTerminal: Int64?
        for stages in combinations {
            let future = try sizingProgress(progress, stages: stages)
            let expected = try SharedMediaNativeReceivingReleaseState.expected(future,
                prepared: snapshot.prepared, received: snapshot.received)
            let pairBytes = try PhotoPreparationPolicy.add(stages.enumerated().compactMap { index, stage in
                stage <= 1 ? bounds[plan.targets[index].pairID] : nil
            })
            let packageBytes = try PhotoPreparationPolicy.add([residual, Int64(expected.member.bytes.count), slot.charged, pairBytes])
            let origin = try originalBytes(snapshot, stages: stages)
            let charge = try Charge(stages: stages, packageBytes: packageBytes,
                receipts: origin.receipts, identities: origin.identities, terminal: false)
            charges.append(charge); maximum = max(maximum, try charge.total); maximumPackage = max(maximumPackage, packageBytes)
            maximumLive = max(maximumLive, try charge.metadataCapBytes)
            maximumIdentityExcluded = max(maximumIdentityExcluded,
                try PhotoPreparationPolicy.add([charge.packageBytes, charge.originReceiptBytes]))
            if stages.allSatisfy({ $0 >= 4 }) {
                // Contract prerequisite: one future atomic save replaces the
                // Progress slot and removes package/member/consumer/execution.
                // No old/new payload overlap is assumed. SQLite/WAL allocation
                // is outside this serialized accounting representation.
                let terminal = try Charge(stages: stages, packageBytes: slot.maximumReleasedBytes,
                    receipts: origin.receipts, identities: origin.identities, terminal: true)
                charges.append(terminal); maximum = max(maximum, try terminal.total)
                maximumPackage = max(maximumPackage, terminal.packageBytes)
                maximumTerminal = max(maximumTerminal ?? 0, try terminal.metadataCapBytes)
                maximumIdentityExcluded = max(maximumIdentityExcluded,
                    try PhotoPreparationPolicy.add([terminal.packageBytes, terminal.originReceiptBytes]))
            }
        }
        guard let maximumTerminal, charges.contains(where: { !$0.terminal }) else { throw SharedMediaStorageFailure.conflict }
        let projection = Projection(currentBytes: current, charges: charges, maximumBytes: maximum,
            maximumPackagePayloadBytes: maximumPackage, maximumLivePackageMetadataBytes: maximumLive,
            maximumTerminalSlotBytes: maximumTerminal,
            currentIdentityExcludedBytes: currentIdentityExcluded,
            maximumIdentityExcludedBytes: maximumIdentityExcluded, recoveryPresentation: recoveryPresentation)
        try Task.checkCancellation()
        if let key { memo?.insert(projection, key: key) }
        return projection
    }

    private static func validateOrigins(_ s: Components) throws {
        let plan = s.progress.plan, targets = plan.targets
        guard s.targetOrigins.map(\.assetID) == targets.map({ $0.original.assetID }),
              s.targetOrigins.map(\.acquisitionID) == targets.map(\.acquisitionID),
              Set(s.ownedOriginals.map(\.assetID)).count == s.ownedOriginals.count else {
            throw SharedMediaStorageFailure.conflict
        }
        for original in s.ownedOriginals {
            guard original.physicalOriginID == plan.package.id, original.receiptBytes > 0,
                  original.identityBytes > 0, original.identityBytes <= 512 else { throw SharedMediaStorageFailure.conflict }
        }
        for (index, origin) in s.targetOrigins.enumerated() {
            let local = s.ownedOriginals.first { $0.assetID == origin.assetID }
            let state = s.progress.targets[index]
            switch origin.location {
            case .present(let packageID):
                guard (packageID == plan.package.id) == (local != nil),
                      !(state.stage == .removed && state.original?.disposition == .removed) else {
                    throw SharedMediaStorageFailure.conflict
                }
                if let local, state.stage != .removed {
                    guard local.retiring == (state.stage == .originalRetiring) else { throw SharedMediaStorageFailure.conflict }
                }
            case .released(let terminal):
                guard local == nil, state.stage == .removed, terminal.operationID == origin.acquisitionID,
                      terminal.inventoryID == plan.profile.inventoryID, terminal.inventoryGeneration == plan.profile.generation,
                      terminal.ownerID == plan.profile.ownerID, SharedMediaAcquisitionEncoding.isHash(terminal.requestFingerprint) else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
        }
    }

    private static func originalBytes(_ s: Components, stages: [Int]) throws -> (receipts: Int64, identities: Int64) {
        var receipts: Int64 = 0, identities: Int64 = 0
        for original in s.ownedOriginals {
            let index = s.progress.plan.targets.firstIndex { $0.original.assetID == original.assetID }
            if let index, stages[index] == 4 { continue }
            // Extra physical origins and shared removals can later retire under
            // another logical owner. Replace today's identity charge with 512;
            // do not add 512 on top. Foreign origins never enter this collection.
            let identity = index.map { stages[$0] >= 3 ? Int64(512) : original.identityBytes } ?? 512
            receipts = try PhotoPreparationPolicy.add([receipts, original.receiptBytes])
            identities = try PhotoPreparationPolicy.add([identities, identity])
        }
        return (receipts, identities)
    }

    private static func pairBounds(_ s: Components) throws -> [UUID: Int64] {
        let plan = s.progress.plan
        var groups = Dictionary(uniqueKeysWithValues: try SharedMediaMembership.decode(s.prepared.member.bytes).groups.map { ($0.kind, Set($0.ids)) })
        for target in plan.targets {
            for output in [target.ai, target.display] {
                groups[.work, default: []].insert(output.leaseID)
                groups[.lease, default: []].insert(output.leaseID)
            }
        }
        // Retained closure bodies may contain the earlier, larger membership.
        let membership = try SharedMediaMembership(groups: groups.map { kind, ids in
            .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
        }.sorted { $0.kind.rawValue < $1.kind.rawValue }).encoded()
        var result: [UUID: Int64] = [:]
        let surviving = Set(s.progress.targets.filter { $0.stage == .readyPair || $0.stage == .retiringPair }.map(\.pairID))
        for state in s.pairs {
            let intent = try state.intent(), id = intent.pairID, p = state.plan
            guard surviving.contains(id), result[id] == nil,
                  let target = plan.targets.first(where: { $0.pairID == id }), target.intentSHA256 == p.intent.sha256,
                  p.packageID == plan.package.id, p.envelope == s.package.envelope,
                  p.membership == s.member.bytes else { throw SharedMediaStorageFailure.conflict }
            _ = try state.selected(intent.ai.id); _ = try state.selected(intent.display.id)
            guard p.inventoryID == plan.profile.inventoryID, p.inventoryGeneration == plan.profile.generation,
                  p.draftGeneration == plan.package.generation,
                  intent.preparation.original.reference == target.original else { throw SharedMediaStorageFailure.conflict }
            let boundPlan = SharedMediaNativePairPlan(intent: p.intent, writerEpoch: p.writerEpoch,
                inventoryID: p.inventoryID, inventoryGeneration: p.inventoryGeneration, inventoryRevision: p.inventoryRevision,
                packageID: p.packageID, draftGeneration: p.draftGeneration, packageRevision: p.packageRevision,
                envelope: p.envelope, membershipRevision: p.membershipRevision, membership: membership)
            let bound = SharedMediaNativePairFileState(plan: boundPlan, phase: state.phase,
                publishedRevision: state.publishedRevision, allocatedBytes: state.allocatedBytes, work: state.work)
            result[id] = try SharedMediaNativePairClosure.maximumStateBytes(bound)
        }
        guard Set(result.keys) == surviving else { throw SharedMediaStorageFailure.conflict }
        return result
    }

    private static func options(_ target: Values.TargetProgress) -> [Int] {
        switch target.stage {
        case .readyPair: return [0, 1, 2, 3, 4, 5]
        case .retiringPair: return [1, 2, 3, 4, 5]
        case .pairGoneOriginalLive: return [2, 3, 4, 5]
        case .originalRetiring: return [3, 4]
        case .removed: return [target.original?.disposition == .shared ? 5 : 4]
        }
    }

    private static func sizingProgress(_ initial: Values.Progress, stages: [Int]) throws -> Values.Progress {
        var progress = initial
        let plan = initial.plan
        var used = Set([plan.releaseID, plan.operationID, plan.queueID, plan.observationID,
            plan.bindingID, plan.generation, plan.eventID] + plan.targets.flatMap(\.identities)
            + initial.targets.flatMap { [$0.pair?.retirementID, $0.original?.retirementID].compactMap { $0 } })
        var counter: UInt64 = 0
        func nextID() throws -> UUID {
            while true {
                counter += 1
                guard let id = UUID(uuidString: String(format: "ffffffff-ffff-ffff-ffff-%012llx", counter)) else {
                    throw SharedMediaStorageFailure.conflict
                }
                if used.insert(id).inserted { return id }
            }
        }
        let hash = String(repeating: "a", count: 64)
        for (index, goal) in stages.enumerated() {
            guard options(initial.targets[index]).contains(goal) else { throw SharedMediaStorageFailure.conflict }
            while true {
                let old = progress.targets[index]
                if options(old).first == goal { break }
                let next: Values.TargetProgress
                switch old.stage {
                case .readyPair:
                    next = .init(pairID: old.pairID, stage: .retiringPair,
                        pair: .init(retirementID: try nextID(), closureSHA256: hash), original: nil)
                case .retiringPair:
                    next = .init(pairID: old.pairID, stage: .pairGoneOriginalLive, pair: old.pair, original: nil)
                case .pairGoneOriginalLive:
                    next = .init(pairID: old.pairID, stage: goal == 5 ? .removed : .originalRetiring, pair: old.pair,
                        original: .init(disposition: goal == 5 ? .shared : .removed,
                            retirementID: goal == 5 ? nil : try nextID(), closureSHA256: hash))
                case .originalRetiring:
                    next = .init(pairID: old.pairID, stage: .removed, pair: old.pair, original: old.original)
                case .removed: throw SharedMediaStorageFailure.conflict
                }
                progress = try progress.advancing(next)
            }
        }
        return progress
    }
}
