import Foundation

/// Prepared reader-12 retirement only. No transport, queue or cleanup consumer is installed.
struct ObservationVideoSourceRetirementRequest: Equatable, Sendable {
    static let readerVersion = 12
    static let maximumBytes = 2_048
    let identity: ObservationVideoSourceIdentity
    let operationID: UUID
    let body: Data

    /// The caller freezes this operation at the final decision, before durable staging.
    init(identity: ObservationVideoSourceIdentity, operationID: UUID) throws {
        let fields = identity.fields.merging(["operation_id": operationID.uuidString.lowercased()]) { _, new in new }
        try self.init(savedBody: JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]), identity: identity)
    }

    /// Validate the original complete candidate association without rewriting persisted bytes.
    init(savedBody: Data, identity: ObservationVideoSourceIdentity) throws {
        let row = try Self.object(savedBody)
        guard Set(row.keys) == Set(identity.fields.keys).union(["operation_id"]) else { throw MerianError.invalidResponse }
        try identity.validate(row)
        let operation = try ObservationHistoryPage.uuid(row["operation_id"])
        guard row["operation_id"] as? String == operation.uuidString.lowercased(),
              ![identity.observationID, identity.sourceAnalysisID, identity.analysisID].contains(operation) else {
            throw MerianError.invalidResponse
        }
        self.identity = identity; operationID = operation; body = savedBody
    }

    fileprivate static func object(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= maximumBytes, !data.contains(0),
              String(data: data, encoding: .utf8) != nil,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MerianError.invalidResponse }
        return row
    }
}

/// Exact permanent receipt, separate from reservation/recovery replies and legacy retirement.
/// Matching JSON is not server authentication and never by itself authorizes local cleanup.
struct ObservationVideoSourceRetirementReceipt: Equatable, Sendable {
    let request: ObservationVideoSourceRetirementRequest
    let ownerID: UUID
    let data: Data

    init(data: Data, request: ObservationVideoSourceRetirementRequest, ownerID: UUID) throws {
        let row = try ObservationVideoSourceRetirementRequest.object(data)
        guard Set(row.keys) == Set(request.identity.fields.keys).union(["operation_id", "owner_id", "state"]),
              row["operation_id"] as? String == request.operationID.uuidString.lowercased(),
              row["owner_id"] as? String == ownerID.uuidString.lowercased(),
              row["state"] as? String == "retired_pre_execution" else { throw MerianError.invalidResponse }
        try request.identity.validate(row)
        self.request = request; self.ownerID = ownerID; self.data = data
    }
}
