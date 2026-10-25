import Foundation

/// Read-check inputs reconstructed from an already audited frozen cohort.
/// These values cannot authorize unlink, metadata writes or admission.
struct SharedMediaNativeReleasePrefix: Equatable, Sendable {
    enum Check: Equatable, Sendable {
        case absent(PhotoPreparationFile, SharedMediaNativeRetirementIdentity)
        case shared(PhotoPreparationFile, SharedMediaPhotoRetirementIdentity)
        case historicalAbsence(PhotoPreparationFile, SharedMediaPhotoRetirementIdentity)
    }
    let checks: [Check]

    @MainActor
    init(_ snapshot: SharedMediaNativeReleaseMetadataSnapshot.Snapshot) throws {
        let progress = snapshot.release.progress
        let index = try progress.selectedIndex(.readyPair)
        guard index > 0 else { throw SharedMediaStorageFailure.closed }
        try self.init(snapshot, count: index)
    }

    @MainActor
    init(terminal snapshot: SharedMediaNativeReleaseMetadataSnapshot.Snapshot) throws {
        guard snapshot.release.progress.targets.allSatisfy({ $0.stage == .removed }) else { throw SharedMediaStorageFailure.closed }
        try self.init(snapshot, count: snapshot.release.progress.targets.count)
    }

    @MainActor
    private init(_ snapshot: SharedMediaNativeReleaseMetadataSnapshot.Snapshot, count index: Int) throws {
        let progress = snapshot.release.progress
        let cohort = try SharedMediaNativeFrozenCohort.decode(snapshot.release.origin.prepared.cohort.bytes)
        guard cohort.entries.count == progress.targets.count else { throw SharedMediaStorageFailure.conflict }
        var checks: [Check] = []
        for position in 0..<index {
            let entry = cohort.entries[position]
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            let original = intent.preparation.original, target = progress.targets[position]
            guard entry.position == position, intent.pairID == target.pairID,
                  original.reference == progress.plan.targets[position].original,
                  target.stage == .removed, let pair = target.pair, let assertion = target.original else {
                throw SharedMediaStorageFailure.conflict
            }
            for (input, descriptor) in [(intent.ai, entry.aiDescriptor), (intent.display, entry.displayDescriptor)] {
                let file = PhotoPreparationFile(assetID: input.assetID, generation: input.assetGeneration,
                    token: "\(original.reference.ownerID.uuidString.lowercased())/\(original.reference.packageID.uuidString.lowercased())/\(input.assetID.uuidString.lowercased())",
                    byteCount: input.byteCount, sha256: input.sha256, contentType: input.contentType)
                let retirement = try SharedMediaNativeRetirementIdentity(retirementID: pair.retirementID,
                    assetID: input.assetID, assetGeneration: input.assetGeneration,
                    inventoryID: progress.plan.profile.inventoryID, inventoryGeneration: progress.plan.profile.generation,
                    ownerID: original.reference.ownerID, proof: descriptor)
                checks.append(.absent(file, retirement))
            }
            switch assertion.disposition {
            case .removed:
                guard let id = assertion.retirementID else { throw SharedMediaStorageFailure.conflict }
                let retirement = try SharedMediaNativeRetirementIdentity(retirementID: id,
                    assetID: original.reference.assetID, assetGeneration: original.reference.assetGeneration,
                    inventoryID: progress.plan.profile.inventoryID, inventoryGeneration: progress.plan.profile.generation,
                    ownerID: original.reference.ownerID, proof: original.descriptor)
                guard SharedMediaAcquisitionEncoding.digest(Data(try retirement.encoded().utf8)) == assertion.closureSHA256 else {
                    throw SharedMediaStorageFailure.conflict
                }
                checks.append(.absent(original.file, retirement))
            case .shared:
                if case .released = snapshot.targetOrigins[position].location {
                    checks.append(.historicalAbsence(original.file, original.descriptor))
                } else { checks.append(.shared(original.file, original.descriptor)) }
            }
        }
        self.checks = checks
    }

    func verify(files: PhotoPreparationLockedFiles, binding: SharedMediaNativeBinding) throws {
        for check in checks {
            switch check {
            case .absent(let file, let retirement):
                try files.requireNativeAbsence(file, retirement: retirement, binding: binding)
            case .historicalAbsence(let file, let descriptor):
                try files.requireNativeDescriptorAbsence(file, descriptor: descriptor, binding: binding)
            case .shared(let file, let descriptor):
                let proof = try files.inspectSharedRetirement(file)
                guard proof.identity == descriptor, proof.binding == binding.bytes, proof.epoch == binding.epoch else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
        }
    }
}
