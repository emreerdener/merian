import Foundation

/// Canonical cleanup-only cursor in the existing inventory row. Normal app
/// eligibility continues to reject every cleanup phase. This value grants no authority
/// to open roots, unlink media, save rows or acknowledge outer account cleanup.
struct SharedMediaNativeLibraryErasureState: Codable, Equatable, Sendable {
    enum Stage: String, Codable, Sendable { case preparing, retiring, complete, cleared }
    let version: Int
    let id: UUID
    let stage: Stage
    let profileSHA256: String
    let manifestSHA256: String
    let sourceRevision: Int64

    var phase: String {
        switch stage {
        case .preparing: "preparingNativeErasureV2"
        case .retiring: "erasingNativeAppV2"
        case .complete: "erasedNativeAppV2"
        case .cleared: "clearedNativeAppV2"
        }
    }
    var revision: Int64 {
        sourceRevision + (stage == .preparing ? 1 : stage == .retiring ? 2 : stage == .complete ? 3 : 4)
    }

    static func intent(id: UUID, profile: SharedMediaNativeAppProfile,
                       manifestSHA256: String, sourceRevision: Int64) throws -> Self {
        guard ![profile.ownerID, profile.inventoryID, profile.generation].contains(id) else {
            throw SharedMediaStorageFailure.invalid
        }
        let value = Self(version: 2, id: id, stage: .preparing,
            profileSHA256: SharedMediaAcquisitionEncoding.digest(try profile.binding),
            manifestSHA256: manifestSHA256, sourceRevision: sourceRevision)
        try value.validate(); return value
    }

    func completed() throws -> Self {
        try advancing(from: .retiring, to: .complete)
    }

    func retiring() throws -> Self {
        try advancing(from: .preparing, to: .retiring)
    }

    func cleared() throws -> Self {
        try advancing(from: .complete, to: .cleared)
    }

    private func advancing(from expected: Stage, to next: Stage) throws -> Self {
        try validate()
        guard stage == expected else { throw SharedMediaStorageFailure.conflict }
        return Self(version: version, id: id, stage: next, profileSHA256: profileSHA256,
            manifestSHA256: manifestSHA256, sourceRevision: sourceRevision)
    }

    func encoded() throws -> String {
        try validate()
        let bytes = try SharedMediaAcquisitionEncoding.encode(self, maximum: SharedMediaStoragePolicy.maximumTokenBytes)
        guard let result = String(data: bytes, encoding: .utf8) else { throw SharedMediaStorageFailure.invalid }
        return result
    }

    @MainActor static func read(_ row: SharedMediaInventoryRecord) throws -> Self {
        guard row.cursor.utf8.count <= SharedMediaStoragePolicy.maximumTokenBytes else {
            throw SharedMediaStorageFailure.capacity
        }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(Data(row.cursor.utf8),
            maximum: SharedMediaStoragePolicy.maximumTokenBytes)
        try value.validate()
        let profile = try SharedMediaNativeAppEligibility.profileAssertion(row)
        guard row.phaseRaw == value.phase, row.revision == value.revision,
              value.profileSHA256 == SharedMediaAcquisitionEncoding.digest(try profile.binding),
              ![profile.ownerID, profile.inventoryID, profile.generation].contains(value.id),
              try value.encoded() == row.cursor else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    private func validate() throws {
        guard version == 2, sourceRevision >= 0, sourceRevision <= Int64.max - 4,
              SharedMediaAcquisitionEncoding.isHash(profileSHA256),
              SharedMediaAcquisitionEncoding.isHash(manifestSHA256) else { throw SharedMediaStorageFailure.invalid }
    }
}
