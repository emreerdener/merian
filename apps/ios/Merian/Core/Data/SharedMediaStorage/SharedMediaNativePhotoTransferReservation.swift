import Foundation

/// One local, not-started role. No file, ticket, write-attempt or release authority.
/// Its fixed copy allowance stays charged until a separately qualified transition
/// proves it can be retired. Cancellation and account shutdown do not erase it.
struct SharedMediaNativePhotoTransferReservation: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case reservedNotStarted }
    static let copyAllowance: Int64 = 32 * PhotoPreparationPolicy.mib
    let state: State
    let selection: SharedMediaNativePhotoRoleMapping.Entry
    let pairID: UUID, assetID: UUID, assetGeneration: UUID
    let descriptor: SharedMediaPhotoRetirementIdentity
    let byteCount: Int64, sha256: String, contentType: String

    init(prepared: SharedMediaNativeReceivingIntent.Prepared,
         selection: SharedMediaNativePhotoRoleMapping.Entry) throws {
        _ = try prepared.encoded()
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        guard frozen.entries.indices.contains(selection.photoOrdinal) else { throw SharedMediaStorageFailure.invalid }
        let entry = frozen.entries[selection.photoOrdinal]
        let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
        state = .reservedNotStarted; self.selection = selection; pairID = intent.pairID
        let reference: UUID
        if selection.role == .source {
            let original = intent.preparation.original
            reference = original.reference.referenceID; assetID = original.reference.assetID
            assetGeneration = original.reference.assetGeneration; descriptor = original.descriptor
            byteCount = original.byteCount; sha256 = original.sha256; contentType = original.contentType
        } else {
            let input = selection.role == .ai ? intent.ai : intent.display
            reference = input.referenceID; assetID = input.assetID; assetGeneration = input.assetGeneration
            descriptor = selection.role == .ai ? entry.aiDescriptor : entry.displayDescriptor
            byteCount = input.byteCount; sha256 = input.sha256; contentType = input.contentType
        }
        guard reference == selection.referenceID else { throw SharedMediaStorageFailure.conflict }
    }

    func validate(claim: SharedMediaNativePhotoAllocation.Claim, mapping: SharedMediaNativePhotoRoleMapping) throws {
        try mapping.validate(claim)
        guard mapping.entries.contains(selection), byteCount > 0, byteCount <= Self.copyAllowance,
              SharedMediaAcquisitionEncoding.isHash(sha256), !contentType.isEmpty, contentType.utf8.count <= 128 else {
            throw SharedMediaStorageFailure.conflict
        }
        _ = try SharedMediaPhotoRetirementIdentity.decode(descriptor.encoded())
        // Compare the declaration to the same canonical content already checked
        // by mapping.validate; local physical identity is checked against Prepared
        // by the clean snapshot before this value can enter aggregate accounting.
        guard let candidate = try JSONSerialization.jsonObject(with: Data(claim.candidateCanonical.utf8)) as? [String: Any],
              let text = candidate["content_canonical"] as? String,
              let content = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let photos = content["photos"] as? [[String: Any]], photos.indices.contains(selection.photoOrdinal),
              let role = photos[selection.photoOrdinal][selection.role.rawValue] as? [String: Any],
              try ObservationHistoryPage.integer(role["byte_count"], maximum: Int(Self.copyAllowance)) == byteCount,
              role["sha256"] as? String == sha256, role["declared_content_type"] as? String == contentType else {
            throw SharedMediaStorageFailure.conflict
        }
    }
}
