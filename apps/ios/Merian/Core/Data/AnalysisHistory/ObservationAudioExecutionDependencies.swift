import Foundation

extension ObservationAudioExecutionService.Dependencies {
    /// Closed I/O only. The queue supplies receipt cleanup inside its retained execution scope.
    @MainActor
    static func live(files: ObservationReanalysisFileStore, client: MerianNetworkClient) -> Self {
        let analysis = client.audioAnalysisTransport(), outcome = client.audioOutcomeTransport()
        return Self(read: { preparation, before, after in
            try await files.readAudio(preparation: preparation, validateBeforeRead: before, validateBeforeReturn: after)
        }, upload: { upload, owner, validate in
            try await client.uploadObservationAudioEvidence(upload, ownerID: owner, validateAttempt: validate)
        }, authorize: { owner, validate in
            try await client.prepareBoundObservationReanalysisAuthorization(processor: .gemini,
                expectedAuthUserID: owner, validateAttempt: validate)
        }, analyze: { permit, authorization, before, after in
            try await analysis.submit(permit, authorization: authorization, validateAttempt: before, validateResponse: after)
        }, outcome: { claim, before, after in
            try await outcome.read(claim, validateAttempt: before, validateResponse: after)
        })
    }
}
