import Foundation

/// A frozen denial-only expectation, never consent, funding or dispatch authority.
struct SharedMediaNativePhotoAdmission: Codable, Equatable, Sendable {
    let clientProtocol: Int
    let identificationProtocol: Int
    let expectedProcessorPermission: IdentificationRecipientExpectation

    @MainActor
    init(authorization: IdentificationDispatchAuthorization) throws {
        try authorization.validate()
        clientProtocol = 3; identificationProtocol = authorization.identificationProtocol
        expectedProcessorPermission = authorization.recipient
        try validate()
    }
    func validate() throws {
        guard clientProtocol == 3, identificationProtocol == 6,
              expectedProcessorPermission == .gemini || expectedProcessorPermission == .openAI else {
            throw SharedMediaStorageFailure.invalid
        }
    }
    func requireSaved(_ saved: Self?) throws {
        try validate()
        guard saved == self else { throw SharedMediaStorageFailure.stale }
    }
}

/// Inactive CPM candidate. Current receiving/account fences remain the consuming owner's responsibility.
struct SharedMediaNativePhotoCandidate: Sendable {
    let canonicalBytes: Data
    let unverifiedDigest: String

    init(prepared: SharedMediaNativeReceivingIntent.Prepared) throws {
        guard let admission = prepared.photoAdmission else { throw SharedMediaStorageFailure.closed }
        try self.init(content: SharedMediaNativePhotoContent(prepared: prepared), admission: admission)
    }
    init(content: SharedMediaNativePhotoContent, admission: SharedMediaNativePhotoAdmission) throws {
        try admission.validate()
        guard let contentText = String(data: content.canonicalBytes, encoding: .utf8) else {
            throw SharedMediaStorageFailure.invalid
        }
        let text = "{\"admission\":{\"client_protocol\":3,\"expected_processor_permission\":"
            + SharedMediaNativePhotoContent.quote(admission.expectedProcessorPermission.rawValue)
            + ",\"identification_protocol\":6},\"content_canonical\":"
            + SharedMediaNativePhotoContent.quote(contentText) + ",\"variant\":\"client_prepared_photo\",\"version\":1}"
        let bytes = Data(text.utf8)
        guard bytes.count <= PhotoPreparationPolicy.metadata else { throw PhotoPreparationFailure.sizeLimit }
        canonicalBytes = bytes
        unverifiedDigest = SharedMediaAcquisitionEncoding.digest(
            Data("merian.initial-analysis.cpm-photo-candidate.v1\n".utf8) + bytes)
    }
}
