import Foundation

/// Bounded assertion retained with a prepared pair. Raw before-state belongs
/// only to the active attempt; retaining it here would recursively retain every
/// older edit. Decoding this value grants no mutation or file authority.
struct SharedMediaNativePreparedIdentity: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case identity = "nativePreparedIdentityV1" }
    let format: Format
    let sequence: Int64
    let operationID: UUID
    let writerEpoch: UUID
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let inventoryRevision: Int64
    let packageRevision: Int64
    let membershipRevision: Int64
    let membershipByteCount: Int64
    let membershipSHA256: String
    let previousEnvelopeByteCount: Int64
    let previousEnvelopeSHA256: String
    let original: SharedMediaNativeOriginalIdentity
    let recipe: SharedMediaNativePreparationRecipe

    init(attempt: SharedMediaNativePreparationAttempt) throws {
        try attempt.validate()
        format = .identity; sequence = attempt.sequence; operationID = attempt.operationID
        writerEpoch = attempt.writerEpoch; inventoryID = attempt.inventoryID
        inventoryGeneration = attempt.inventoryGeneration; inventoryRevision = attempt.inventoryRevision
        packageRevision = attempt.packageRevision; membershipRevision = attempt.membershipRevision
        membershipByteCount = Int64(attempt.membershipBytes.count)
        membershipSHA256 = SharedMediaAcquisitionEncoding.digest(attempt.membershipBytes)
        previousEnvelopeByteCount = Int64(attempt.previousEnvelope.count)
        previousEnvelopeSHA256 = SharedMediaAcquisitionEncoding.digest(attempt.previousEnvelope)
        original = attempt.original; recipe = attempt.recipe
        try validate()
    }

    func validate() throws {
        try original.validate(); try recipe.validate()
        guard sequence > 0,
              [inventoryRevision, packageRevision, membershipRevision].allSatisfy({ $0 >= 0 && $0 < Int64.max - 4 }),
              [membershipByteCount, previousEnvelopeByteCount].allSatisfy({ $0 > 0 && $0 <= PhotoPreparationPolicy.metadata }),
              SharedMediaAcquisitionEncoding.isHash(membershipSHA256),
              SharedMediaAcquisitionEncoding.isHash(previousEnvelopeSHA256) else { throw SharedMediaStorageFailure.invalid }
    }

    /// Plan must call this after exact active-attempt CAS under sealed authority.
    func requireMatch(_ attempt: SharedMediaNativePreparationAttempt) throws {
        guard self == (try Self(attempt: attempt)) else { throw SharedMediaStorageFailure.stale }
    }
}
