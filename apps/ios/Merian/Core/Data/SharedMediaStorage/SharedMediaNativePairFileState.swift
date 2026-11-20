import Foundation

/// Complete value witness for native output transitions. Decoding this value
/// grants no write, cleanup or inference authority.
struct SharedMediaNativePairFileState: Codable, Equatable, Sendable {
    let plan: SharedMediaNativePairPlan
    let phase: String
    let publishedRevision: Int64?
    let allocatedBytes: Int64
    let work: [Work]

    struct Work: Codable, Equatable, Sendable {
        let id: UUID
        let writerEpoch: UUID
        let phase: String
        let writerState: String
        let device: Int64?
        let inode: Int64?
        let finalIdentity: String?
        let retirementID: UUID?
        let retirementPartial: String?
        let retirementFinal: String?
        let retirementParent: String?
        let retirementNamespace: String?
        let closure: String?
    }

    func intent() throws -> SharedMediaNativeDerivativeIntent {
        try plan.intent.validate()
        return try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes)
    }

    func selected(_ id: UUID) throws -> (Work, SharedMediaDerivativeInput) {
        let intent = try intent()
        guard work.count == 2, Set(work.map(\.id)) == Set([intent.ai.id, intent.display.id]),
              let value = work.first(where: { $0.id == id }),
              let input = [intent.ai, intent.display].first(where: { $0.id == id }),
              value.writerEpoch == plan.writerEpoch else { throw SharedMediaStorageFailure.conflict }
        return (value, input)
    }

    func file(_ id: UUID) throws -> PhotoPreparationFile {
        let (_, input) = try selected(id), original = try intent().preparation.original.reference
        return .init(assetID: input.assetID, generation: input.assetGeneration,
            token: original.ownerID.uuidString.lowercased() + "/" + original.packageID.uuidString.lowercased() + "/" + input.assetID.uuidString.lowercased(),
            byteCount: input.byteCount, sha256: input.sha256, contentType: input.contentType)
    }
}
