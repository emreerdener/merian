import Foundation

/// Advisory photo recipient lookup. Identity is supplied by durable queue ownership, never minted here.
struct ObservationReanalysisPreflightRequest: Encodable, Equatable, Sendable {
    let observationID: UUID
    let analysisID: UUID
    let sourceAnalysisID: UUID

    init(observationID: UUID, analysisID: UUID, sourceAnalysisID: UUID) throws {
        guard Set([observationID, analysisID, sourceAnalysisID]).count == 3 else { throw MerianError.invalidResponse }
        self.observationID = observationID; self.analysisID = analysisID; self.sourceAnalysisID = sourceAnalysisID
    }
    enum CodingKeys: String, CodingKey {
        case schema_version, observation_id, analysis_id, source_analysis_id
        case entitlement_protocol, identification_protocol, history_protocol
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schema_version)
        try values.encode(observationID.uuidString.lowercased(), forKey: .observation_id)
        try values.encode(analysisID.uuidString.lowercased(), forKey: .analysis_id)
        try values.encode(sourceAnalysisID.uuidString.lowercased(), forKey: .source_analysis_id)
        try values.encode(3, forKey: .entitlement_protocol)
        try values.encode(6, forKey: .identification_protocol)
        try values.encode(8, forKey: .history_protocol)
    }

    static func recipient(from data: Data, for request: Self) throws -> IdentificationRecipientExpectation {
        guard data.count <= 4096,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["schema_version", "observation_id", "analysis_id", "source_analysis_id",
                "decision", "processor_permission", "minimum_entitlement_protocol", "minimum_identification_protocol"],
              integer(row["schema_version"]) == 1,
              row["observation_id"] as? String == request.observationID.uuidString.lowercased(),
              row["analysis_id"] as? String == request.analysisID.uuidString.lowercased(),
              row["source_analysis_id"] as? String == request.sourceAnalysisID.uuidString.lowercased(),
              let decision = row["decision"] as? String else { throw MerianError.invalidResponse }
        if decision == "recovery_only" {
            guard row["processor_permission"] is NSNull,
                  row["minimum_entitlement_protocol"] is NSNull,
                  row["minimum_identification_protocol"] is NSNull else { throw MerianError.invalidResponse }
            return .recoveryOnly
        }
        let recipient = (row["processor_permission"] as? String).flatMap(IdentificationRecipientExpectation.init(rawValue:))
        let identificationMinimum = integer(row["minimum_identification_protocol"])
        guard let minimum = integer(row["minimum_entitlement_protocol"]),
              row["processor_permission"] is NSNull || recipient == .gemini || recipient == .openAI,
              row["minimum_identification_protocol"] is NSNull || identificationMinimum != nil else {
            throw MerianError.invalidResponse
        }
        if decision == "client_update_required" {
            guard minimum > 0 || (identificationMinimum ?? 0) > 0 else { throw MerianError.invalidResponse }
            throw MerianError.httpError(statusCode: 426, message: #"{"code":"client_update_required"}"#)
        }
        guard ["ready", "permission_required"].contains(decision), minimum <= 3,
              let identificationMinimum, [0, 4, 5, 6].contains(identificationMinimum),
              let recipient, recipient != .openAI || [4, 5, 6].contains(identificationMinimum) else {
            throw MerianError.invalidResponse
        }
        if decision == "permission_required" {
            throw recipient == .openAI ? MerianError.openAIConsentRequired : MerianError.aiConsentRequired
        }
        return recipient
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= 1000,
              Double(number.intValue) == number.doubleValue else { return nil }
        return number.intValue
    }
}
