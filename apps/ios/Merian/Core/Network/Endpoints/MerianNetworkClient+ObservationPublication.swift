import Foundation

extension MerianNetworkClient {
    /// Descriptive candidates only; final consent and durable admission belong to a separate owner.
    func prepareObservationPublicationConsent(_ request: ObservationPublicationConsentRequest, ownerID: UUID) async throws -> ObservationPublicationConsentSnapshot {
        let data = try await performAuthenticatedJSONDataPost(function: "prepare-observation-publication-consent",
            payload: try publicationPayload(request), expectedAuthUserID: ownerID, allowsUnauthorizedSessionRecovery: false)
        return try ObservationPublicationConsentSnapshot.decode(data, request: request)
    }

    /// Exact replay belongs to the durable caller; this method never creates an operation ID.
    func requestObservationPublication(_ request: ObservationPublicationRequest, ownerID: UUID) async throws -> ObservationPublicationReceipt {
        let data = try await performAuthenticatedJSONDataPost(function: "request-observation-publication",
            payload: try publicationPayload(request), expectedAuthUserID: ownerID, allowsUnauthorizedSessionRecovery: false)
        return try ObservationPublicationReceipt.decodeAdmission(data, request: request)
    }

    func observationPublicationStatus(_ request: ObservationPublicationStatusRequest, ownerID: UUID) async throws -> ObservationPublicationReceipt {
        let data = try await performAuthenticatedJSONDataPost(function: "get-observation-publication-status",
            payload: try publicationPayload(request), expectedAuthUserID: ownerID, allowsUnauthorizedSessionRecovery: false)
        return try ObservationPublicationReceipt.decodeStatus(data, request: request)
    }
    private func publicationPayload<T: Encodable>(_ request: T) throws -> [String: Any] {
        guard let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any] else {
            throw MerianError.invalidResponse
        }
        return payload
    }
}
