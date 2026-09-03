import Foundation

/// Export queue requests only; Settings owns availability and presentation.
extension MerianNetworkClient {
    /// Queues a DwC-A export job. The insertion transaction snapshots bounded
    /// source membership and revision fingerprints, then a background webhook
    /// generates the ZIP and emails the final download link via Resend.
    func requestDwcAExport(scope: String = "personal") async throws {
        // Personal exports intentionally request the owner's precise coordinates.
        // The backend independently enforces release availability and scope
        // authorization; this client continues to forward the caller's raw scope.
        let payload: [String: Any] = ["exportScope": scope, "includePreciseCoordinates": true]

        // Archive generation remains asynchronous; this timeout covers only the
        // bounded queue-and-snapshot transaction.
        try await performAuthenticatedJSONPost(
            function: "request-export-dwca",
            payload: payload,
            timeoutInterval: 15.0
        )
    }
}
