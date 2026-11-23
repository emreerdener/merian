import Foundation

/// Prepared reader-14 identity. Semantic validation is not native saved-body restoration or server authority.
struct ObservationCompositionSourceIdentity: Equatable, Sendable {
    static let readerVersion = 14
    let observationID: UUID
    let sourceAnalysisID: UUID
    let analysisID: UUID
    let requestDigest: String
    let fingerprint: String
    let fingerprintVersion: Int
    var requiredReaderVersion: Int { fingerprintVersion == 2 ? 15 : 14 }

    init(input: Data) throws {
        guard !input.isEmpty, input.count <= 1_044_480, !input.contains(0),
              String(data: input, encoding: .utf8) != nil else { throw MerianError.invalidResponse }
        fingerprint = try ObservationCompositionReanalysisRequest(savedBody: input).sourceFingerprint()
        guard let row = try JSONSerialization.jsonObject(with: input) as? [String: Any],
              let digest = row["request_digest"] as? String else { throw MerianError.invalidResponse }
        observationID = try ObservationHistoryPage.uuid(row["observation_id"])
        sourceAnalysisID = try ObservationHistoryPage.uuid(row["source_analysis_id"])
        analysisID = try ObservationHistoryPage.uuid(row["analysis_id"])
        requestDigest = digest
        fingerprintVersion = try ObservationHistoryPage.integer(row["schema_version"]) == 6 ? 2 : 1
    }

    /// Exact lookup only; no absence, release, upload or execution permission.
    func recoveryBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    var fields: [String: Any] {
        ["schema_version": 3, "observation_id": observationID.uuidString.lowercased(),
         "source_analysis_id": sourceAnalysisID.uuidString.lowercased(), "analysis_id": analysisID.uuidString.lowercased(),
         "request_digest": requestDigest, "fingerprint_version": fingerprintVersion, "fingerprint": fingerprint]
    }

    func validate(_ row: [String: Any]) throws {
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 3,
              try ObservationHistoryPage.integer(row["fingerprint_version"]) == fingerprintVersion,
              row["observation_id"] as? String == observationID.uuidString.lowercased(),
              row["source_analysis_id"] as? String == sourceAnalysisID.uuidString.lowercased(),
              row["analysis_id"] as? String == analysisID.uuidString.lowercased(),
              row["request_digest"] as? String == requestDigest,
              row["fingerprint"] as? String == fingerprint else { throw MerianError.invalidResponse }
    }
}

/// Immutable schema-3 envelope for typed reservation transport. No queue caller is installed.
struct CompositionSourceReservationRequest: Equatable, Sendable {
    static let maximumBytes = 1_048_576
    let identity: ObservationCompositionSourceIdentity
    let input: Data
    let body: Data

    init(composition: ObservationCompositionReanalysisRequest) throws {
        let identity = try ObservationCompositionSourceIdentity(input: composition.body)
        var body = Data("{\"schema_version\":3,\"input\":".utf8)
        body.append(composition.body)
        body.append(Data(",\"fingerprint_version\":\(identity.fingerprintVersion),\"fingerprint\":\"\(identity.fingerprint)\"}".utf8))
        guard body.count <= Self.maximumBytes else { throw MerianError.invalidResponse }
        self.identity = identity; input = composition.body; self.body = body
    }

    /// Replay must retain both byte strings; formatting changes are not replacement requests.
    init(savedInput: Data, savedBody: Data) throws {
        guard savedInput.count <= 1_044_480, savedBody.count <= Self.maximumBytes,
              String(data: savedInput, encoding: .utf8) != nil else { throw MerianError.invalidResponse }
        try self.init(composition: ObservationCompositionReanalysisRequest(savedBody: savedInput))
        guard body == savedBody else { throw MerianError.invalidResponse }
    }
}

/// Reservation and recovery share one closed reply contract. Every state binds the complete identity.
struct CompositionSourceReservationReply: Equatable, Sendable {
    static let maximumBytes = 2_048
    enum Hold: String, CaseIterable, Sendable {
        case sourceOccupied = "source_occupied"
        case ambiguousOccupancy = "ambiguous_occupancy"
        case coverageIncomplete = "coverage_incomplete"
        case malformedLinkage = "malformed_linkage"
        case terminalUnproven = "terminal_unproven"
    }
    enum State: Equatable, Sendable { case reserved, held(Hold), unavailable }
    let identity: ObservationCompositionSourceIdentity
    let ownerID: UUID
    let state: State
    let data: Data

    init(data: Data, identity: ObservationCompositionSourceIdentity, ownerID: UUID) throws {
        guard !data.isEmpty, data.count <= Self.maximumBytes, !data.contains(0),
              String(data: data, encoding: .utf8) != nil,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              row["owner_id"] as? String == ownerID.uuidString.lowercased() else { throw MerianError.invalidResponse }
        try identity.validate(row)
        let keys = Set(identity.fields.keys).union(["owner_id", "state"])
        switch row["state"] as? String {
        case "reserved":
            guard Set(row.keys) == keys else { throw MerianError.invalidResponse }
            state = .reserved
        case "unavailable":
            guard Set(row.keys) == keys else { throw MerianError.invalidResponse }
            state = .unavailable
        case "held":
            guard Set(row.keys) == keys.union(["reason"]), let raw = row["reason"] as? String,
                  let reason = Hold(rawValue: raw) else { throw MerianError.invalidResponse }
            state = .held(reason)
        default: throw MerianError.invalidResponse
        }
        self.identity = identity; self.ownerID = ownerID; self.data = data
    }
}
