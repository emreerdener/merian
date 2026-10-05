import Foundation

extension MerianNetworkClient {
    /// Owner-only completed-result recovery. Does not require inference consent or mutate selection.
    /// Only a verified missing target returns nil; all other denials remain failures.
    func recoverObservationAnalysis(
        _ input: ObservationReanalysisRequest,
        expectedAuthUserID: UUID,
        validateAttempt: @escaping @MainActor @Sendable () throws -> Void
    ) async throws -> Data? {
        func validate() async throws {
            try Task.checkCancellation()
            guard try await authenticatedUserIDForInferenceRequest() == expectedAuthUserID else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            try await validateAttempt()
        }
        struct Parameters: Encodable {
            let p_request: ObservationHistoryStateRequest
            let p_reader = 9
        }
        let request = ObservationHistoryStateRequest(observation_id: input.observationID.uuidString.lowercased(),
            analysis_id: input.analysisID.uuidString.lowercased())
        try await validate()
        let bytes: Data
        do {
            bytes = try await performOwnedIdentificationRead(body: JSONEncoder().encode(Parameters(p_request: request)),
                expectedAuthUserID: expectedAuthUserID, route: .analysisState)
        } catch {
            try await validate()
            if Self.isMissingObservationAnalysis(error) { return nil }
            throw error
        }
        try await validate()
        let result: ObservationHistoryPage.Result
        do {
            let state = try ObservationHistoryState.decode(bytes, request: request, ownerID: expectedAuthUserID)
            result = try ObservationReanalysisResult.decode(state.result.bytes, matching: input)
        } catch let error as ObservationHistoryError {
            throw error
        } catch {
            // Parser/decoder failures are invalid stored state, never transport uncertainty.
            throw ObservationHistoryError.invalidSnapshot
        }
        try await validate()
        return result.bytes
    }

    private static func isMissingObservationAnalysis(_ error: Error) -> Bool {
        guard let error = error as? MerianError, case let .httpError(_, message) = error,
              message.utf8.count <= 8_192,
              let row = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
              Set(row.keys).isSubset(of: ["code", "message", "details", "hint"]),
              row["code"] as? String == "P0002", row["message"] as? String == "analysis_history_not_found" else { return false }
        return ["details", "hint"].allSatisfy { row[$0] == nil || row[$0] is NSNull || row[$0] is String }
    }
}
