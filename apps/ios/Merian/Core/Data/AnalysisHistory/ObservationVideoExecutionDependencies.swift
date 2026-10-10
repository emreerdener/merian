import Foundation

extension ObservationVideoExecutionService.Dependencies {
    @MainActor
    static func live(client: MerianNetworkClient, account: ObservationHistoryCloudClient) -> Self {
        let analysis = client.videoAnalysisTransport()
        return Self(authorize: { owner, validate in
            try await client.prepareBoundObservationReanalysisAuthorization(processor: .gemini,
                expectedAuthUserID: owner, validateAttempt: validate)
        }, analyze: { permit, authorization, before, after in
            try await analysis.submit(permit, authorization: authorization, validateAttempt: before, validateResponse: after)
        }, outcome: reader(account: account))
    }

    /// Reader11 is an exact completed-result read, never a provider outcome mutation or retry.
    @MainActor
    static func reader(account: ObservationHistoryCloudClient) -> (ObservationVideoExecutionStore.Snapshot,
        @escaping ObservationVideoExecutionService.Validate, @escaping ObservationVideoExecutionService.Validate) async throws -> Data? {
        { saved, before, after in
            try before()
            guard saved.work.consumed, saved.work.phase == .running || saved.work.phase == .held else { throw MerianError.invalidResponse }
            let identity = saved.work.preparation.identity
            let lease = try account.begin(identity.ownerID)
            defer { account.finish(lease) }
            @MainActor func validateLease() throws {
                guard lease.session.userID == identity.ownerID, account.isCurrent(lease) else { throw MerianError.invalidResponse }
            }
            try before(); try validateLease()
            let request = ObservationHistoryStateRequest(observation_id: identity.observationID.uuidString.lowercased(),
                analysis_id: identity.analysisID.uuidString.lowercased())
            let data = try await account.fetchState(request)
            try after(); try validateLease()
            let state = try ObservationHistoryState.decode(data, request: request, ownerID: identity.ownerID)
            let result = try ObservationReanalysisResult.decode(state.result.bytes, matching: saved.work.request)
            try after(); try validateLease()
            return result.bytes
        }
    }
}
