import Foundation
import Testing

@testable import Merian

enum AccountDeletionRecoveryRequestCase: CaseIterable, Sendable {
    case legacyRecover, legacyAcknowledge, recoverV2, acknowledgeV2

    var isV2: Bool { self == .recoverV2 || self == .acknowledgeV2 }
    var acknowledges: Bool { self == .legacyAcknowledge || self == .acknowledgeV2 }

    @MainActor
    func invoke(_ client: MerianNetworkClient, capability: String = AccountDeletionTestSupport.recovery) async throws -> AccountDeletionReceipt {
        switch self {
        case .legacyRecover, .legacyAcknowledge:
            try await client.recoverAcceptedAccountDeletion(recoveryCapability: capability, acknowledge: acknowledges)
        case .recoverV2:
            try await client.recoverPreparedAccountDeletionV2(recoveryCapability: capability)
        case .acknowledgeV2:
            try await client.acknowledgeAccountDeletionRecoveryV2(acknowledgementCapability: capability)
        }
    }

    func response(to request: URLRequest, status: Int = 200) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (response, try AccountDeletionTestSupport.receiptData(
            status: .completed, acknowledged: acknowledges, protocolVersion: isV2 ? 2 : nil
        ))
    }

    @discardableResult
    func expectRequest(_ request: URLRequest) throws -> NetworkEndpointRequestSnapshot {
        #expect(request.url?.scheme == "https" && request.url?.path == "/functions/v1/recover-account-deletion")
        #expect(request.url?.query == nil && request.httpMethod == "POST")
        #expect(request.timeoutInterval == 20 && request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "apikey") != nil)
        for key in ["Authorization", "X-Merian-Entitlement-Protocol", "Idempotency-Key"] {
            #expect(request.value(forHTTPHeaderField: key) == nil)
        }
        var expected: [String: Any] = ["operation": acknowledges ? "acknowledge" : "recover"]
        if isV2 { expected["protocol_version"] = 2 }
        expected[isV2 && acknowledges ? "acknowledgement_capability" : "recovery_capability"] = AccountDeletionTestSupport.recovery
        let body = try #require(MockURLProtocol.bodyData(for: request))
        let json = try JSONSerialization.data(withJSONObject: expected)
        #expect(try NetworkEndpointTestSupport.canonicalRequestJSON(body) == NetworkEndpointTestSupport.canonicalRequestJSON(json))
        return NetworkEndpointRequestSnapshot(body: body, idempotencyKey: nil, timeout: request.timeoutInterval)
    }
}
