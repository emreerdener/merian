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
    let receiptKind: ProtectedInsightChatReply.Kind?
    private let storageVersion: Int
    var isComplete: Bool { receiptData != nil }

    init(request: ProtectedInsightChatRequest, ownerID: UUID) throws {
        self.ownerID = ownerID; self.request = request
        requestSHA256 = SHA256.hash(data: try request.encoded()).map { String(format: "%02x", $0) }.joined()
        receiptData = nil; observedAt = nil; receiptKind = nil; storageVersion = 1
    }
    private init(original: Self, version: Int, receipt: Data?, kind: ProtectedInsightChatReply.Kind?, observedAt: Date?) {
        ownerID = original.ownerID; request = original.request; requestSHA256 = original.requestSHA256
        receiptData = receipt; receiptKind = kind; storageVersion = version; self.observedAt = observedAt
    }
    func accepting(_ data: Data, at date: Date) throws -> Self {
        let reply = try ProtectedInsightChatReply(data: data, request: request)
        let row = try ProtectedInsightChatWire.object(data, limit: 32_768)
        let canonical = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
        guard date.timeIntervalSince1970.isFinite, (0...32_503_680_000).contains(date.timeIntervalSince1970) else { throw MerianError.invalidResponse }
        if let receiptData {
            guard receiptData == canonical else { throw MerianError.invalidResponse }
            return self
        }
        return Self(original: self, version: 2,
                    receipt: canonical, kind: reply.outcome.kind, observedAt: date)
    }
    func storedData() throws -> Data {
        var row: [String: Any] = ["version": storageVersion, "owner_id": ownerID.uuidString.lowercased(),
            "request": try JSONSerialization.jsonObject(with: request.encoded()), "request_sha256": requestSHA256,
            "receipt": try receiptData.map { try JSONSerialization.jsonObject(with: $0) } ?? NSNull(),
            "observed_at": observedAt?.timeIntervalSince1970 as Any? ?? NSNull()]
        if storageVersion == 2 { row["receipt_kind"] = receiptKind?.rawValue as Any? ?? NSNull() }
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 49_152 else { throw MerianError.invalidResponse }
        return data
    }
    static func decode(_ data: Data) throws -> Self {
        let row = try ProtectedInsightChatWire.object(data, limit: 49_152)
        let version = try ProtectedInsightChatWire.integer(row["version"])
        let keys: Set<String> = ["version", "owner_id", "request", "request_sha256", "receipt", "observed_at"]
        guard version == 1 || version == 2, Set(row.keys) == (version == 2 ? keys.union(["receipt_kind"]) : keys),
              let request = row["request"] as? [String: Any],
              let digest = row["request_sha256"] as? String else { throw MerianError.invalidResponse }
        let original = try Self(request: ProtectedInsightChatRequest.decode(JSONSerialization.data(withJSONObject: request)),
                                ownerID: ProtectedInsightChatWire.uuid(row["owner_id"]))
        guard digest == original.requestSHA256 else { throw MerianError.invalidResponse }
        if row["receipt"] is NSNull {
            guard version == 1, row["observed_at"] is NSNull else { throw MerianError.invalidResponse }
            return Self(original: original, version: version, receipt: nil, kind: nil, observedAt: nil)
        }
        guard let receipt = row["receipt"] as? [String: Any], let seconds = row["observed_at"] as? NSNumber,
              CFGetTypeID(seconds) != CFBooleanGetTypeID() else { throw MerianError.invalidResponse }
        let data = try JSONSerialization.data(withJSONObject: receipt)
        if version == 1 {
            _ = try FieldChatResponseDecoder.decodeProtectedCompletion(data, expectedSubjectId: original.request.observationID,
                expectedClientMessageId: original.request.clientMessageID)
        }
        let accepted = try original.accepting(data, at: Date(timeIntervalSince1970: seconds.doubleValue))
        guard version == 1 || row["receipt_kind"] as? String == accepted.receiptKind?.rawValue else { throw MerianError.invalidResponse }
        return Self(original: original, version: version, receipt: accepted.receiptData, kind: accepted.receiptKind, observedAt: accepted.observedAt)
    }
}
