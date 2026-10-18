import Foundation

/// Native preparation assertions. None of these decoded values grants file,
/// processor, account, funding or provider authority.
struct SharedMediaNativeOriginalIdentity: Codable, Equatable, Sendable {
    let reference: PhotoOriginalReference
    let ordinal: Int64
    let token: String
    let byteCount: Int64
    let sha256: String
    let contentType: String
    let descriptor: SharedMediaPhotoRetirementIdentity

    var file: PhotoPreparationFile {
        .init(assetID: reference.assetID, generation: reference.assetGeneration, token: token,
              byteCount: byteCount, sha256: sha256, contentType: contentType)
    }
    func validate() throws {
        try reference.validate()
        let components = token.split(separator: "/", omittingEmptySubsequences: false)
        guard (0..<2).contains(ordinal), byteCount > 0, byteCount <= PhotoPreparationPolicy.original,
              SharedMediaAcquisitionEncoding.isHash(sha256), !contentType.isEmpty, contentType.utf8.count <= 128,
              components.count == 3, components[0] == reference.ownerID.uuidString.lowercased(),
              components[2] == reference.assetID.uuidString.lowercased(),
              let origin = UUID(uuidString: String(components[1])), components[1] == origin.uuidString.lowercased() else {
            throw SharedMediaStorageFailure.invalid
        }
        // A shared original keeps its physical origin package; it need not be
        // the logical destination package carried by the reference.
        _ = try SharedMediaPhotoRetirementIdentity.decode(descriptor.encoded())
    }
}

struct SharedMediaNativePreparationRecipe: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case stillImage = "nativeStillImageV1" }
    let format: Format
    let isPro: Bool
    let cropDisplaySize: Double?
    let quarterTurns: Int
    let scale: Double
    let offsetX: Double
    let offsetY: Double

    func validate() throws {
        guard (0...3).contains(quarterTurns), scale.isFinite, scale >= 1,
              offsetX.isFinite, offsetY.isFinite else { throw SharedMediaStorageFailure.invalid }
        if let cropDisplaySize {
            guard cropDisplaySize.isFinite, cropDisplaySize > 0 else { throw SharedMediaStorageFailure.invalid }
        } else {
            guard quarterTurns == 0, scale == 1, offsetX == 0, offsetY == 0 else { throw SharedMediaStorageFailure.invalid }
        }

    }
}

struct SharedMediaNativePreparationAttempt: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case attempt = "nativePreparationAttemptV2" }
    let format: Format
    let sequence: Int64
    let operationID: UUID
    let writerEpoch: UUID
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let inventoryRevision: Int64
    let packageRevision: Int64
    let membershipRevision: Int64
    let membershipBytes: Data
    let previousEnvelope: Data
    let original: SharedMediaNativeOriginalIdentity
    let recipe: SharedMediaNativePreparationRecipe

    var outputReservation: Int64 { PhotoPreparationPolicy.aiCohort + PhotoPreparationPolicy.display }
    func validate() throws {
        try original.validate(); try recipe.validate()
        guard sequence > 0, [inventoryRevision, packageRevision, membershipRevision].allSatisfy({ $0 >= 0 && $0 < Int64.max - 4 }),
              !previousEnvelope.isEmpty, previousEnvelope.count <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.invalid }
        _ = try SharedMediaMembership.decode(membershipBytes)
        // Deliberately do not recursively decode a previous V2 envelope here.
        // The mutation compares the exact prior bytes and validates its graph.
    }
    func encoded() throws -> Data {
        try validate()
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Int(PhotoPreparationPolicy.metadata))
    }
    static func decode(_ bytes: Data) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}

/// A compact projection binds the exact active attempt without embedding its
/// ancestral envelope. Output facts are immutable and cannot be reconstructed
/// from current UI controls. The draft attemptBytes format is never admitted.
struct SharedMediaNativeDerivativeIntent: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case intent = "nativeDerivativeIntentV3" }
    let format: Format
    let preparation: SharedMediaNativePreparedIdentity
    let pairID: UUID
    let nonce: UUID
    let previousPairID: UUID?
    let ai: SharedMediaDerivativeInput
    let display: SharedMediaDerivativeInput
    /// The detector outcome for these exact AI bytes, including nil.
    let focus: NormalizedImageFocusRegion?

    func attempt() throws -> SharedMediaNativePreparedIdentity { try preparation.validate(); return preparation }
    func encoded() throws -> Data {
        _ = try attempt()
        try ai.validate(); try display.validate()
        if let focus {
            guard focus.x.isFinite, focus.y.isFinite, focus.width.isFinite, focus.height.isFinite,
                  focus.x >= 0, focus.y >= 0, focus.width > 0, focus.height > 0,
                  focus.x + focus.width <= 1, focus.y + focus.height <= 1 else { throw SharedMediaStorageFailure.invalid }
        }
        guard ai.role == "aiInput", display.role == "display", previousPairID != pairID,
              Set([pairID, nonce, ai.id, ai.assetID, ai.referenceID, ai.leaseID,
                   display.id, display.assetID, display.referenceID, display.leaseID]).count == 10 else { throw SharedMediaStorageFailure.invalid }
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Int(PhotoPreparationPolicy.metadata))
    }
    static func decode(_ bytes: Data) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}

/// Canonical bytes and digest are retained together. The digest domain is only
/// these bytes, never the enclosing envelope or its own digest field.
struct SharedMediaNativePreparationBlob: Codable, Equatable, Sendable {
    let bytes: Data
    let sha256: String
    init(bytes: Data) { self.bytes = bytes; sha256 = SharedMediaAcquisitionEncoding.digest(bytes) }
    func validate() throws {
        guard !bytes.isEmpty, bytes.count <= PhotoPreparationPolicy.metadata,
              SharedMediaAcquisitionEncoding.isHash(sha256), sha256 == SharedMediaAcquisitionEncoding.digest(bytes) else {
            throw SharedMediaStorageFailure.conflict
        }
    }
}
