import CoreFoundation
import CryptoKit
import Foundation

/// Owner-private immutable mutation plus historical receipt. Receipt recovery never resubmits a decision.
struct ObservationAnalysisReviewIntent: Sendable {
    let ownerID: UUID
    let request: ObservationAnalysisReviewRequest
    let requestSHA256: String
    let receipt: ObservationAnalysisReviewReceipt?
    let observedAt: Date?
    let reconciledAt: Date?

    var hasReceipt: Bool { receipt != nil }
    var isComplete: Bool { reconciledAt != nil }

    init(request: ObservationAnalysisReviewRequest, ownerID: UUID) throws {
        self.ownerID = ownerID; self.request = request
        requestSHA256 = try Self.fingerprint(request)
        receipt = nil; observedAt = nil; reconciledAt = nil
    }

    private init(ownerID: UUID, request: ObservationAnalysisReviewRequest, digest: String,
                 receipt: ObservationAnalysisReviewReceipt?, observedAt: Date?, reconciledAt: Date?) {
        self.ownerID = ownerID; self.request = request; requestSHA256 = digest
        self.receipt = receipt; self.observedAt = observedAt; self.reconciledAt = reconciledAt
    }

    static func fingerprint(_ request: ObservationAnalysisReviewRequest) throws -> String {
        SHA256.hash(data: try request.encoded()).map { String(format: "%02x", $0) }.joined()
    }

    func accepting(_ receipt: ObservationAnalysisReviewReceipt, at date: Date) throws -> Self {
        guard receipt.request == request, Self.validDate(date) else { throw MerianError.invalidResponse }
        if let existing = self.receipt {
            guard existing == receipt else { throw MerianError.invalidResponse }
            return self
        }
        return Self(ownerID: ownerID, request: request, digest: requestSHA256,
                    receipt: receipt, observedAt: date, reconciledAt: nil)
    }

    func storedData() throws -> Data {
        let row: [String: Any] = [
            "version": 1, "owner_id": ownerID.uuidString.lowercased(),
            "request": try JSONSerialization.jsonObject(with: request.encoded()),
            "request_sha256": requestSHA256,
            "receipt": try receipt.map { try JSONSerialization.jsonObject(with: $0.encoded()) } ?? NSNull(),
            "observed_at": observedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
            "reconciled_at": reconciledAt?.timeIntervalSince1970 as Any? ?? NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        guard data.count <= 8192 else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        let row = try ObservationAnalysisReviewWire.object(data, limit: 8192)
        guard Set(row.keys) == ["version", "owner_id", "request", "request_sha256", "receipt", "observed_at", "reconciled_at"],
              try ObservationAnalysisReviewWire.integer(row["version"]) == 1,
              let requestRow = row["request"] as? [String: Any], let digest = row["request_sha256"] as? String else {
            throw MerianError.invalidResponse
        }
        let request = try ObservationAnalysisReviewRequest.decode(JSONSerialization.data(withJSONObject: requestRow))
        guard try fingerprint(request) == digest else { throw MerianError.invalidResponse }
        let owner = try ObservationAnalysisReviewWire.uuid(row["owner_id"])
        if row["receipt"] is NSNull {
            guard row["observed_at"] is NSNull, row["reconciled_at"] is NSNull else { throw MerianError.invalidResponse }
            return try Self(request: request, ownerID: owner)
        }
        guard let receiptRow = row["receipt"] as? [String: Any] else { throw MerianError.invalidResponse }
        let receipt = try ObservationAnalysisReviewReceipt.decode(JSONSerialization.data(withJSONObject: receiptRow), request: request)
        let observed = try date(row["observed_at"])
        let reconciled = row["reconciled_at"] is NSNull ? nil : try date(row["reconciled_at"])
        guard reconciled.map({ $0 >= observed }) ?? true else { throw MerianError.invalidResponse }
        return Self(ownerID: owner, request: request, digest: digest, receipt: receipt, observedAt: observed, reconciledAt: reconciled)
    }

    static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && (0...32_503_680_000).contains(date.timeIntervalSince1970)
    }
    private static func date(_ value: Any?) throws -> Date {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { throw MerianError.invalidResponse }
        let date = Date(timeIntervalSince1970: number.doubleValue)
        guard validDate(date) else { throw MerianError.invalidResponse }
        return date
    }
}
