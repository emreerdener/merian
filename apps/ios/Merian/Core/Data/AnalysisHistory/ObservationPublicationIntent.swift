import CoreFoundation
import CryptoKit
import Foundation

/// Local v1 consent fingerprint, not server authorization or a server digest.
struct ObservationPublicationIntent: Sendable {
    let ownerID: UUID
    let identity: ObservationPublicationStatusRequest
    let requestSHA256: String
    let request: ObservationPublicationRequest?
    let receipt: ObservationPublicationReceipt?
    let observedAt: Date?

    var isTerminal: Bool { receipt?.status == .admitted || receipt?.status == .needsAction }

    init(request: ObservationPublicationRequest, ownerID: UUID) throws {
        self.ownerID = ownerID; identity = request.statusRequest
        requestSHA256 = try Self.fingerprint(request)
        self.request = request; receipt = nil; observedAt = nil
    }

    private init(ownerID: UUID, identity: ObservationPublicationStatusRequest, digest: String,
                 request: ObservationPublicationRequest?, receipt: ObservationPublicationReceipt?, observedAt: Date?) {
        self.ownerID = ownerID; self.identity = identity; requestSHA256 = digest
        self.request = request; self.receipt = receipt; self.observedAt = observedAt
    }

    static func fingerprint(_ request: ObservationPublicationRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return SHA256.hash(data: try encoder.encode(request)).map { String(format: "%02x", $0) }.joined()
    }

    func accepting(_ receipt: ObservationPublicationReceipt, at date: Date) throws -> Self {
        guard receipt.operationID == identity.operationID, receipt.observationID == identity.observationID,
              receipt.analysisID == identity.analysisID, date.timeIntervalSince1970.isFinite,
              (0...32_503_680_000).contains(date.timeIntervalSince1970) else { throw MerianError.invalidResponse }
        // A delayed acknowledgement cannot reopen, replace, or redate a terminal receipt.
        if isTerminal {
            guard self.receipt == receipt else { throw MerianError.invalidResponse }
            return self
        }
        return Self(ownerID: ownerID, identity: identity, digest: requestSHA256,
                    request: nil, receipt: receipt, observedAt: date)
    }

    func storedData() throws -> Data {
        let requestObject: Any = try request.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        let object: [String: Any] = [
            "version": 1, "owner_id": ownerID.uuidString.lowercased(),
            "operation_id": identity.operationID.uuidString.lowercased(),
            "observation_id": identity.observationID.uuidString.lowercased(),
            "analysis_id": identity.analysisID.uuidString.lowercased(),
            "request_sha256": requestSHA256, "request": requestObject,
            "status": receipt?.status.rawValue as Any? ?? NSNull(),
            "observed_at": observedAt?.timeIntervalSince1970 as Any? ?? NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 8192 else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 8192, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["version", "owner_id", "operation_id", "observation_id", "analysis_id",
                                "request_sha256", "request", "status", "observed_at"],
              try ObservationPublicationWire.integer(row["version"]) == 1,
              let digest = row["request_sha256"] as? String, digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw MerianError.invalidResponse
        }
        let owner = try ObservationPublicationWire.uuid(row["owner_id"])
        let identity = try ObservationPublicationStatusRequest(
            operationID: ObservationPublicationWire.uuid(row["operation_id"]),
            observationID: ObservationPublicationWire.uuid(row["observation_id"]),
            analysisID: ObservationPublicationWire.uuid(row["analysis_id"]))
        if row["status"] is NSNull {
            guard row["observed_at"] is NSNull, let request = row["request"] as? [String: Any] else {
                throw MerianError.invalidResponse
            }
            let parsed = try ObservationPublicationRequest.decode(JSONSerialization.data(withJSONObject: request))
            guard parsed.statusRequest == identity, try fingerprint(parsed) == digest else { throw MerianError.invalidResponse }
            return try Self(request: parsed, ownerID: owner)
        }
        guard row["request"] is NSNull, let seconds = row["observed_at"] as? NSNumber,
              CFGetTypeID(seconds) != CFBooleanGetTypeID(), seconds.doubleValue.isFinite,
              (0...32_503_680_000).contains(seconds.doubleValue), let status = row["status"] as? String else {
            throw MerianError.invalidResponse
        }
        let wire: [String: Any] = ["schema_version": 1, "operation_id": identity.operationID.uuidString.lowercased(),
                                  "observation_id": identity.observationID.uuidString.lowercased(),
                                  "analysis_id": identity.analysisID.uuidString.lowercased(), "status": status]
        let receipt = try ObservationPublicationReceipt.decodeStatus(JSONSerialization.data(withJSONObject: wire), request: identity)
        return Self(ownerID: owner, identity: identity, digest: digest, request: nil,
                    receipt: receipt, observedAt: Date(timeIntervalSince1970: seconds.doubleValue))
    }
}
