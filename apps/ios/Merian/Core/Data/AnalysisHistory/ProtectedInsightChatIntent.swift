import CoreFoundation
import CryptoKit
import Foundation

/// Owner-private restart proof. A saved answer is terminal; context alone is not execution authority.
struct ProtectedInsightChatIntent: Sendable {
    let ownerID: UUID
    let request: ProtectedInsightChatRequest
    let requestSHA256: String
    let receiptData: Data?
    let observedAt: Date?
    var isComplete: Bool { receiptData != nil }

    init(request: ProtectedInsightChatRequest, ownerID: UUID) throws {
        self.ownerID = ownerID; self.request = request
        requestSHA256 = SHA256.hash(data: try request.encoded()).map { String(format: "%02x", $0) }.joined()
        receiptData = nil; observedAt = nil
    }
    private init(original: Self, receipt: Data, observedAt: Date) {
        ownerID = original.ownerID; request = original.request; requestSHA256 = original.requestSHA256
        receiptData = receipt; self.observedAt = observedAt
    }
    func accepting(_ data: Data, at date: Date) throws -> Self {
        _ = try FieldChatResponseDecoder.decodeProtectedCompletion(data, expectedSubjectId: request.observationID,
                                                                  expectedClientMessageId: request.clientMessageID)
        let row = try ProtectedInsightChatWire.object(data, limit: 32_768)
        let canonical = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
        guard date.timeIntervalSince1970.isFinite, (0...32_503_680_000).contains(date.timeIntervalSince1970) else { throw MerianError.invalidResponse }
        if let receiptData {
            guard receiptData == canonical else { throw MerianError.invalidResponse }
            return self
        }
        return Self(original: self, receipt: canonical, observedAt: date)
    }
    func storedData() throws -> Data {
        let row: [String: Any] = ["version": 1, "owner_id": ownerID.uuidString.lowercased(),
            "request": try JSONSerialization.jsonObject(with: request.encoded()), "request_sha256": requestSHA256,
            "receipt": try receiptData.map { try JSONSerialization.jsonObject(with: $0) } ?? NSNull(),
            "observed_at": observedAt?.timeIntervalSince1970 as Any? ?? NSNull()]
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 49_152 else { throw MerianError.invalidResponse }
        return data
    }
    static func decode(_ data: Data) throws -> Self {
        let row = try ProtectedInsightChatWire.object(data, limit: 49_152)
        guard Set(row.keys) == ["version", "owner_id", "request", "request_sha256", "receipt", "observed_at"],
              try ProtectedInsightChatWire.integer(row["version"]) == 1, let request = row["request"] as? [String: Any],
              let digest = row["request_sha256"] as? String else { throw MerianError.invalidResponse }
        let original = try Self(request: ProtectedInsightChatRequest.decode(JSONSerialization.data(withJSONObject: request)),
                                ownerID: ProtectedInsightChatWire.uuid(row["owner_id"]))
        guard digest == original.requestSHA256 else { throw MerianError.invalidResponse }
        if row["receipt"] is NSNull {
            guard row["observed_at"] is NSNull else { throw MerianError.invalidResponse }
            return original
        }
        guard let receipt = row["receipt"] as? [String: Any], let seconds = row["observed_at"] as? NSNumber,
              CFGetTypeID(seconds) != CFBooleanGetTypeID() else { throw MerianError.invalidResponse }
        return try original.accepting(JSONSerialization.data(withJSONObject: receipt), at: Date(timeIntervalSince1970: seconds.doubleValue))
    }
}
