import Foundation
import Testing

@testable import Merian

struct ScanLifecycleNetworkRequestCase: Sendable, CustomTestStringConvertible {
    enum Kind: Sendable { case status, compatibility, bulk, deletion }

    private typealias Fixtures = ScanLifecycleNetworkFixtures
    let name: String
    let kind: Kind
    let expectedJSON: String
    let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void

    var testDescription: String { name }
    var function: String { kind == .deletion ? "delete-scan" : "check-scan-status" }
    var path: String { "/\(function)" }
    var responseJSON: String {
        switch kind {
        case .status, .compatibility: Fixtures.statusJSON
        case .bulk: Fixtures.bulkJSON
        case .deletion: Fixtures.deletionJSON
        }
    }

    static let status = Self(
        name: "single status defaults", kind: .status,
        expectedJSON: #"{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#
    ) { client in
        _ = try await client.checkScanStatusDetails(scanId: Fixtures.scanID)
    }
    static let compatibility = Self(
        name: "compatibility status defaults", kind: .compatibility,
        expectedJSON: #"{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#
    ) { client in
        _ = try await client.checkScanStatus(scanId: Fixtures.scanID)
    }
    static let bulk = Self(
        name: "bulk status", kind: .bulk,
        expectedJSON: #"{"scans":[{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}]}"#
    ) { client in
        _ = try await client.checkScanStatuses([Fixtures.scanID: 0])
    }
    static let deletion = Self(
        name: "confirmed deletion", kind: .deletion,
        expectedJSON: #"{"scanId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#
    ) { client in
        try await client.deleteScan(scanId: Fixtures.scanID)
    }
    static let recovery = Self(
        name: "single status with owner recovery", kind: .status,
        expectedJSON: #"{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","recovery_scan":\#(Fixtures.recoveryJSON)}"#
    ) { client in
        _ = try await client.checkScanStatusDetails(scanId: Fixtures.scanID, recoveryScan: Fixtures.recoveryScan())
    }

    static var operations: [Self] { [status, compatibility, bulk, deletion, recovery] }
    static var statusOperations: [Self] { operations.filter { $0.kind != .deletion } }
    static var all: [Self] { operations + variants }

    @discardableResult
    func expectRequest(_ request: URLRequest) throws -> NetworkEndpointRequestSnapshot {
        try NetworkEndpointTestSupport.expectPOST(request, function: function, json: expectedJSON)
    }

    @MainActor
    func withResponse(_ json: String? = nil, body: (MerianNetworkClient) async throws -> Void) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingAuthUserID = UUID(uuidString: Fixtures.userID)
        try await confirmation("Exactly one scan lifecycle request") { sent in
            fixture.transport.register(path: path) { request in
                sent()
                try expectRequest(request)
                return try NetworkEndpointTestSupport.response(to: request, json: json ?? responseJSON)
            }
            try await body(fixture.client)
        }
    }

    private static var variants: [Self] {
        let videoCounts: [(Int, String)] = [(0, ""), (-3, ""), (2, #","required_video_count":2"#)]
        let videoCases = videoCounts.flatMap { count, field in
            [
                Self(name: "single video count \(count)", kind: .status,
                     expectedJSON: #"{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"\#(field)}"#) { client in
                    _ = try await client.checkScanStatusDetails(scanId: Fixtures.scanID, requiredVideoCount: count)
                },
                Self(name: "compatibility video count \(count)", kind: .compatibility,
                     expectedJSON: #"{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"\#(field)}"#) { client in
                    _ = try await client.checkScanStatus(scanId: Fixtures.scanID, requiredVideoCount: count)
                },
                Self(name: "bulk video count \(count)", kind: .bulk,
                     expectedJSON: #"{"scans":[{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"\#(field)}]}"#) { client in
                    _ = try await client.checkScanStatuses([Fixtures.scanID: count])
                }
            ]
        }
        return videoCases + [
            Self(name: "single forwards raw ID", kind: .status, expectedJSON: #"{"scan_id":" Raw-ID "}"#) { client in
                _ = try await client.checkScanStatusDetails(scanId: " Raw-ID ")
            },
            Self(name: "single forwards empty ID", kind: .status, expectedJSON: #"{"scan_id":""}"#) { client in
                _ = try await client.checkScanStatusDetails(scanId: "")
            },
            Self(name: "deletion forwards raw ID", kind: .deletion, expectedJSON: #"{"scanId":" Raw-ID "}"#) { client in
                try await client.deleteScan(scanId: " Raw-ID ")
            },
            Self(name: "deletion forwards empty ID", kind: .deletion, expectedJSON: #"{"scanId":""}"#) { client in
                try await client.deleteScan(scanId: "")
            }
        ]
    }
}
