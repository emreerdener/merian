import Foundation

@testable import Merian

/// Synthetic, identity-free receipts shared by the wire and endpoint suites.
enum AccountDeletionTestSupport {
    static let recovery = String(repeating: "R", count: 43)
    static let acknowledgement = String(repeating: "K", count: 43)
    static let futureExpiry = "2099-01-01T00:00:00Z"
    static let expiredTimestamp = "2025-01-01T00:00:00Z"
    static let now = Date(timeIntervalSince1970: 1_893_456_000)

    static func preparationHandlerResponseData() throws -> Data {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("project.yml").path
            ) {
                return try Data(
                    contentsOf: directory.appendingPathComponent(
                        "services/supabase/functions/_tests/fixtures/" +
                            "account-deletion-preparation-v2-success.json"
                    )
                )
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    static func receiptData(
        status: AccountDeletionStatus = .pending,
        success: Bool = true,
        expiry: String? = futureExpiry,
        acknowledged: Bool? = nil,
        protocolVersion: Int? = 2
    ) throws -> Data {
        var payload: [String: Any] = [
            "success": success,
            "status": status.rawValue,
            "manual_provider_revocation_required": false
        ]
        payload["recovery_capability_expires_at"] = expiry
        payload["recovery_acknowledged"] = acknowledged
        payload["protocol_version"] = protocolVersion
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}
