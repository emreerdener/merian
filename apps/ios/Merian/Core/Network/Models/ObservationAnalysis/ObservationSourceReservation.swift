import Foundation

/// An immutable candidate, not upload, funding or execution authority.
struct ObservationSourceReservationRequest: Equatable, Sendable {
    static let maximumBytes = 1_048_576
    let observationID: UUID
    let sourceAnalysisID: UUID
    let analysisID: UUID
    let requestDigest: String
    let fingerprint: String
    let input: Data
    let body: Data

    init(photo: ObservationReanalysisRequest) throws {
        try self.init(input: photo.body, observationID: photo.observationID, sourceAnalysisID: photo.sourceAnalysisID,
                      analysisID: photo.analysisID, requestDigest: photo.requestDigest)
    }

    init(audio: ObservationAudioReanalysisRequest) throws {
        try self.init(input: audio.body, observationID: audio.observationID, sourceAnalysisID: audio.sourceAnalysisID,
                      analysisID: audio.analysisID, requestDigest: audio.requestDigest)
    }

    /// Restoration retains the original input bytes; it never reconstructs them from current selection.
    init(savedInput: Data, savedBody: Data) throws {
        guard savedInput.count <= 1_044_480, savedBody.count <= Self.maximumBytes,
              let row = try JSONSerialization.jsonObject(with: savedInput) as? [String: Any] else {
            throw MerianError.invalidResponse
        }
        switch try ObservationHistoryPage.integer(row["schema_version"]) {
        case 2: try self.init(photo: ObservationReanalysisRequest(savedBody: savedInput))
        case 3: try self.init(audio: ObservationAudioReanalysisRequest(savedBody: savedInput))
        default: throw MerianError.invalidResponse
        }
        guard body == savedBody else { throw MerianError.invalidResponse }
    }

    private init(input: Data, observationID: UUID, sourceAnalysisID: UUID, analysisID: UUID, requestDigest: String) throws {
        let fingerprint = try ObservationSourceFingerprint(input: input).sha256
        // Embed the exact saved input, including its digest and formatting, rather than reserializing it.
        var body = Data("{\"schema_version\":1,\"input\":".utf8)
        body.append(input)
        body.append(Data(",\"fingerprint_version\":1,\"fingerprint\":\"\(fingerprint)\"}".utf8))
        guard body.count <= Self.maximumBytes else { throw MerianError.invalidResponse }
        self.observationID = observationID; self.sourceAnalysisID = sourceAnalysisID; self.analysisID = analysisID
        self.requestDigest = requestDigest; self.fingerprint = fingerprint; self.input = input; self.body = body
    }
}

/// Exact server observations. None of these states permits upload, admission, replacement or dispatch.
struct ObservationSourceReservationReply: Equatable, Sendable {
    static let maximumBytes = 2_048
    enum Hold: String, Sendable {
        case sourceOccupied = "source_occupied"
        case ambiguousOccupancy = "ambiguous_occupancy"
        case coverageIncomplete = "coverage_incomplete"
        case malformedLinkage = "malformed_linkage"
        case terminalUnproven = "terminal_unproven"
    }
    enum State: Equatable, Sendable { case reserved, held(Hold), unavailable }
    let state: State
    let request: ObservationSourceReservationRequest
    let ownerID: UUID
    let data: Data

    init(data: Data, request: ObservationSourceReservationRequest, ownerID: UUID) throws {
        guard data.count <= Self.maximumBytes,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              try ObservationHistoryPage.integer(row["schema_version"]) == 1,
              try ObservationHistoryPage.uuid(row["owner_id"]) == ownerID,
              try ObservationHistoryPage.uuid(row["observation_id"]) == request.observationID,
              try ObservationHistoryPage.uuid(row["source_analysis_id"]) == request.sourceAnalysisID else {
            throw MerianError.invalidResponse
        }
        let scope: Set<String> = ["schema_version", "owner_id", "observation_id", "source_analysis_id", "state"]
        switch row["state"] as? String {
        case "reserved":
            guard Set(row.keys) == scope.union(["analysis_id", "request_digest", "fingerprint_version", "fingerprint"]),
                  try ObservationHistoryPage.uuid(row["analysis_id"]) == request.analysisID,
                  row["request_digest"] as? String == request.requestDigest,
                  try ObservationHistoryPage.integer(row["fingerprint_version"]) == 1,
                  row["fingerprint"] as? String == request.fingerprint else { throw MerianError.invalidResponse }
            state = .reserved
        case "held":
            guard Set(row.keys) == scope.union(["reason"]), let raw = row["reason"] as? String,
                  let reason = Hold(rawValue: raw) else { throw MerianError.invalidResponse }
            state = .held(reason)
        case "unavailable":
            guard Set(row.keys) == scope else { throw MerianError.invalidResponse }
            state = .unavailable
        default: throw MerianError.invalidResponse
        }
        self.request = request; self.ownerID = ownerID; self.data = data
    }
}
