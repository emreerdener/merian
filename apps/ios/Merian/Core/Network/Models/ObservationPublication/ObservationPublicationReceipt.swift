import CoreFoundation
import Foundation

enum ObservationPublicationStatus: String, Sendable, Codable, CaseIterable {
    case accepted, processing
    case photosApproved = "photos_approved"
    case needsAction = "needs_action"
    case admitted
}

/// Historical operation status, never current public visibility or species authority.
struct ObservationPublicationReceipt: Equatable, Sendable {
    let operationID: UUID
    let observationID: UUID
    let analysisID: UUID
    let status: ObservationPublicationStatus
    private init(_ request: ObservationPublicationStatusRequest, status: ObservationPublicationStatus) {
        operationID = request.operationID; observationID = request.observationID
        analysisID = request.analysisID; self.status = status
    }

    static func decodeStatus(_ data: Data, request: ObservationPublicationStatusRequest) throws -> Self {
        let row = try ObservationPublicationWire.object(data,
            keys: ["schema_version", "operation_id", "observation_id", "analysis_id", "status"])
        try validateIdentity(row, request: request)
        guard let raw = row["status"] as? String, let status = ObservationPublicationStatus(rawValue: raw) else {
            throw MerianError.invalidResponse
        }
        return Self(request, status: status)
    }

    static func decodeAdmission(_ data: Data, request: ObservationPublicationRequest) throws -> Self {
        let row = try ObservationPublicationWire.object(data,
            keys: ["schema_version", "operation_id", "observation_id", "analysis_id", "status", "admitted_at"])
        try validateIdentity(row, request: request.statusRequest)
        guard row["status"] as? String == "accepted", let date = row["admitted_at"] as? String,
              date.utf8.count <= 40,
              (DateUtilities.iso8601FractionalFormatter.date(from: date)
                ?? DateUtilities.iso8601Formatter.date(from: date)) != nil else { throw MerianError.invalidResponse }
        return Self(request.statusRequest, status: .accepted)
    }

    private static func validateIdentity(_ row: [String: Any], request: ObservationPublicationStatusRequest) throws {
        guard try ObservationPublicationWire.integer(row["schema_version"]) == 1,
              try ObservationPublicationWire.uuid(row["operation_id"]) == request.operationID,
              try ObservationPublicationWire.uuid(row["observation_id"]) == request.observationID,
              try ObservationPublicationWire.uuid(row["analysis_id"]) == request.analysisID else {
            throw MerianError.invalidResponse
        }
    }
}

/// Bounded, exact-key wire validation; never stores arbitrary private response fields.
enum ObservationPublicationWire {
    static func object(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        guard data.count <= 4096,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == keys else { throw MerianError.invalidResponse }
        return row
    }
    static func uuid(_ value: Any?) throws -> UUID {
        guard let text = value as? String, let id = UUID(uuidString: text),
              text == id.uuidString.lowercased() else { throw MerianError.invalidResponse }
        return id
    }
    static func integer(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 2_147_483_646,
              number.doubleValue.rounded() == number.doubleValue else { throw MerianError.invalidResponse }
        return number.intValue
    }
}
