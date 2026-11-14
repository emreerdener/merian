import Foundation
import Testing
@testable import Merian

private final class ScanObservationBundleAnchor: NSObject {}

enum ScanObservationTestFixture {
    static func response(ownerID: UUID, scanID: UUID, rowExists: Bool, status: String? = "complete") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "phase": "observe",
            "owner_id": ownerID.uuidString.lowercased(), "scan_id": scanID.uuidString.lowercased(),
            "row_exists": rowExists, "job_status": status as Any? ?? NSNull(), "original_result": "unavailable"], options: [.sortedKeys])
    }
    static func response(to request: URLRequest, rowExists: Bool = true) throws -> Data {
        let bytes = try #require(MockURLProtocol.bodyData(for: request))
        let outer = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(outer.keys) == ["initial_recovery"])
        let envelope = try #require(outer["initial_recovery"] as? [String: Any])
        let original = try #require(envelope["original"] as? [String: String])
        let owner = try #require(original["owner_id"].flatMap(UUID.init(uuidString:)))
        let scan = try #require(original["scan_id"].flatMap(UUID.init(uuidString:)))
        #expect(request.value(forHTTPHeaderField: "X-Merian-Initial-Recovery") == "observe-v1")
        return try response(ownerID: owner, scanID: scan, rowExists: rowExists)
    }
}

@Suite("Observation-only status wire contract")
struct ScanObservationResponseTests {
    @Test func sharedBackendFixtureMatchesRequestAndTypedResponse() throws {
        let url = try #require(Bundle(for: ScanObservationBundleAnchor.self).url(forResource: "observation-v1", withExtension: "json"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let request = try #require(object["request"] as? [String: Any])
        let response = try #require(object["response"] as? [String: Any])
        let owner = try #require((response["owner_id"] as? String).flatMap(UUID.init(uuidString:)))
        let scan = try #require((response["scan_id"] as? String).flatMap(UUID.init(uuidString:)))
        #expect(try ScanObservationResponse.request(ownerID: owner, scanID: scan) == JSONSerialization.data(withJSONObject: request, options: [.sortedKeys]))
        let decoded = try ScanObservationResponse.decode(JSONSerialization.data(withJSONObject: response), ownerID: owner, scanID: scan)
        #expect(decoded.rowExists && decoded.jobStatus == .complete && decoded.originalResult == "unavailable")
    }

    @Test(arguments: ["owner", "scan", "upper", "version", "phase", "original", "job", "bool", "extra", "absent", "legacy", "oversized"])
    func rejectsForeignMixedAndMalformedResponses(_ fault: String) throws {
        let owner = UUID(), scan = UUID()
        var object = try #require(JSONSerialization.jsonObject(with: ScanObservationTestFixture.response(ownerID: owner, scanID: scan, rowExists: true)) as? [String: Any])
        switch fault {
        case "owner": object["owner_id"] = UUID().uuidString.lowercased()
        case "scan": object["scan_id"] = UUID().uuidString.lowercased()
        case "upper": object["owner_id"] = owner.uuidString.uppercased()
        case "version": object["version"] = 2
        case "phase": object["phase"] = "completion"
        case "original": object["original_result"] = "found"
        case "job": object["job_status"] = "unknown"
        case "bool": object["row_exists"] = 1
        case "extra": object["result"] = [:]
        case "absent": object.removeValue(forKey: "job_status")
        case "legacy": object = ["status": "found"]
        default: object["original_result"] = String(repeating: "x", count: 4097)
        }
        let bytes = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try ScanObservationResponse.decode(bytes, ownerID: owner, scanID: scan) }
    }

    @Test func absentRowAndIndependentJobStatusNeverBecomeOriginalResultProof() throws {
        let owner = UUID(), scan = UUID()
        for status in [nil, "processing", "finalizing", "retrying", "failed_retryable", "failed_terminal", "complete"] {
            for exists in [false, true] {
                let value = try ScanObservationResponse.decode(ScanObservationTestFixture.response(ownerID: owner, scanID: scan, rowExists: exists, status: status), ownerID: owner, scanID: scan)
                #expect(value.rowExists == exists && value.jobStatus?.rawValue == status && value.originalResult == "unavailable")
            }
        }
    }
}
