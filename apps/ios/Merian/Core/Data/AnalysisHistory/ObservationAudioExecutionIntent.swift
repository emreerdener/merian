import Foundation

/// Exact local audio binding. Neither decoding nor a consumed marker permits an HTTP replay.
struct ObservationAudioExecutionIntent: Equatable, Sendable {
    let ownerID: UUID
    let sourceSnapshotSHA256: String
    let request: ObservationAudioReanalysisRequest

    var identity: OfflineQueueWork.Reanalysis {
        .init(observationID: request.observationID, sourceAnalysisID: request.sourceAnalysisID,
              analysisID: request.analysisID, ownerID: ownerID)
    }

    /// Construct off-main from submitted evidence, never from the current selection.
    init(preparation: ObservationAudioPreparation) throws {
        guard preparation.action == .submit else { throw MerianError.invalidResponse }
        ownerID = preparation.identity.ownerID; sourceSnapshotSHA256 = preparation.sourceSnapshotSHA256
        request = try .init(observationID: preparation.identity.observationID, analysisID: preparation.identity.analysisID,
            sourceAnalysisID: preparation.identity.sourceAnalysisID, evidence: preparation.evidence)
    }

    private init(ownerID: UUID, sourceSnapshotSHA256: String, request: ObservationAudioReanalysisRequest) {
        self.ownerID = ownerID; self.sourceSnapshotSHA256 = sourceSnapshotSHA256; self.request = request
    }

    func matches(_ preparation: ObservationAudioPreparation) -> Bool {
        preparation.action == .submit && identity == preparation.identity && sourceSnapshotSHA256 == preparation.sourceSnapshotSHA256
            && request.evidence == preparation.evidence
    }

    enum State: String, Sendable { case idle, running, held }
    struct Work: Equatable, Sendable {
        let intent: ObservationAudioExecutionIntent
        let state: State
        let attempt: Int
        /// The original dispatch attempt remains immutable through later recovery claims.
        let consumedAttempt: Int?

        init(intent: ObservationAudioExecutionIntent, state: State = .idle, attempt: Int = 0, consumedAttempt: Int? = nil) throws {
            let validState = state == .idle ? attempt == 0 && consumedAttempt == nil : attempt > 0
            guard (0...2_147_483_647).contains(attempt), validState,
                  consumedAttempt.map({ $0 > 0 && $0 <= attempt }) ?? true else { throw MerianError.invalidResponse }
            self.intent = intent; self.state = state; self.attempt = attempt; self.consumedAttempt = consumedAttempt
        }

        func data() throws -> Data {
            let data = try JSONSerialization.data(withJSONObject: [
                "version": 1, "kind": "audio_execution", "owner_id": intent.ownerID.uuidString.lowercased(),
                "source_snapshot_sha256": intent.sourceSnapshotSHA256, "request_base64": intent.request.body.base64EncodedString(),
                "state": state.rawValue, "attempt": attempt, "consumed_attempt": consumedAttempt.map { $0 as Any } ?? NSNull()
            ], options: [.sortedKeys, .withoutEscapingSlashes])
            guard data.count <= 1_400_000 else { throw MerianError.invalidResponse }
            return data
        }

        static func decode(_ data: Data) throws -> Self {
            guard data.count <= 1_400_000, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(row.keys) == ["version", "kind", "owner_id", "source_snapshot_sha256", "request_base64", "state", "attempt", "consumed_attempt"],
                  try ObservationHistoryPage.integer(row["version"]) == 1, row["kind"] as? String == "audio_execution",
                  let digest = row["source_snapshot_sha256"] as? String, digest.utf8.count == 64,
                  digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  let encoded = row["request_base64"] as? String, let body = Data(base64Encoded: encoded), body.base64EncodedString() == encoded,
                  let raw = row["state"] as? String, let state = State(rawValue: raw) else { throw MerianError.invalidResponse }
            let attempt = try ObservationHistoryPage.integer(row["attempt"])
            let consumed: Int? = row["consumed_attempt"] is NSNull ? nil : try ObservationHistoryPage.integer(row["consumed_attempt"])
            let intent = try ObservationAudioExecutionIntent(ownerID: ObservationHistoryPage.uuid(row["owner_id"]),
                sourceSnapshotSHA256: digest, request: .init(savedBody: body))
            return try Self(intent: intent, state: state, attempt: attempt, consumedAttempt: consumed)
        }
    }
}
