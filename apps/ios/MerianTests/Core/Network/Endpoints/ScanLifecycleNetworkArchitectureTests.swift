import Foundation
import Testing

@testable import Merian

@Suite("Scan Lifecycle Network Architecture")
struct ScanLifecycleNetworkArchitectureTests {
    @Test func endpointOwnerKeepsFourPublicMethodsWithoutTransportOrState() throws {
        let endpoint = try source("Endpoints/MerianNetworkClient+ScanLifecycle.swift")
        let client = try source("MerianNetworkClient.swift")
        let expected: Set<String> = ["checkScanStatusDetails", "checkScanStatuses", "checkScanStatus", "deleteScan"]
        let declarations = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
        let matches = declarations.matches(in: endpoint, range: NSRange(endpoint.startIndex..., in: endpoint))
        let names = try matches.map { String(endpoint[try #require(Range($0.range(at: 1), in: endpoint))]) }
        #expect(names.count == 4 && Set(names) == expected)
        #expect(endpoint.components(separatedBy: "performAuthenticatedJSONDataPost(").count == 4)
        #expect(endpoint.components(separatedBy: "validateEndpointConfiguration(").count == 3)
        for name in expected { #expect(!client.contains("func \(name)(")) }
        for token in ["URLSession", "SupabaseManager", "Task", "static let shared", "endpointURL(",
                      "performAuthenticatedRequest(", "JSONDecoder", "catch"] {
            #expect(!endpoint.contains(token), "Scan lifecycle endpoint must not own \(token)")
        }
        #expect(endpoint.range(of: #"(?m)^    (?:private )?(?:static )?(?:let|var)\s"#, options: .regularExpression) == nil)
        #expect(endpoint.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        for owner in ["MissingScanRecoveryAction", "OwnedScanRecoveryPayload", "recoverMissingOwnedCloudScan",
                      "makeOwnedScanRecoveryPayload", "waitForScanPersistence", "shareScanToExplore", "requestCommunityIdentification"] {
            #expect(client.contains(owner), "Recovery and publication ownership must remain unchanged: \(owner)")
        }
    }

    @Test func requestOrderingAndRecoveryAccountBindingStayExplicit() throws {
        let endpoint = try source("Endpoints/MerianNetworkClient+ScanLifecycle.swift")
        let single = try method("checkScanStatusDetails", in: endpoint)
        try expectOrder([
            #"try validateEndpointConfiguration("check-scan-status")"#,
            "try JSONEncoder().encode(recoveryScan)",
            "JSONSerialization.jsonObject(with: recoveryData)",
            "let expectedAuthUserID = recoveryScan.flatMap",
            "UUID(uuidString: $0.userId)",
            "try await performAuthenticatedJSONDataPost(",
            "expectedAuthUserID: expectedAuthUserID",
            "try ScanLifecycleResponseDecoder.status("
        ], in: single)
        #expect(single.contains("requiredVideoCount > 0"))
        #expect(!single.contains("lowercased") && !single.contains("trimmingCharacters"))

        let bulk = try method("checkScanStatuses", in: endpoint)
        try expectOrder([
            "guard !requirements.isEmpty else { return [:] }",
            "for scanID in requirements.keys", "expectedScanIDs.updateValue(scanID, forKey: normalized)",
            #"try validateEndpointConfiguration("check-scan-status")"#,
            "let scans = requirements.map", "try await performAuthenticatedJSONDataPost(",
            "try ScanLifecycleResponseDecoder.statuses("
        ], in: bulk)
        #expect(bulk.contains("requiredVideoCount > 0") && !bulk.contains("recovery_scan"))
        let deletion = try method("deleteScan", in: endpoint)
        try expectOrder([
            "try await performAuthenticatedJSONDataPost(", #"payload: ["scanId": scanId]"#,
            "try ScanLifecycleResponseDecoder.confirmDeletion(from: data)", "MerianLog.network.debug"
        ], in: deletion)
        let compatibility = try method("checkScanStatus", in: endpoint)
        #expect(compatibility.contains("try await checkScanStatusDetails(") && compatibility.contains("return response.status.rawValue"))
    }

    @Test func rawJSONBridgeForwardsAccountBindingWithoutNewTransportPolicy() throws {
        let client = try source("MerianNetworkClient.swift")
        let bridge = try method("performAuthenticatedJSONDataPost", in: client)
        #expect(bridge.contains("expectedAuthUserID: UUID? = nil") && bridge.contains("async throws -> Data"))
        try expectOrder([
            "try endpointURL(function)", "try JSONSerialization.data(withJSONObject: payload)",
            "try await performAuthenticatedRequest(", "expectedAuthUserID: expectedAuthUserID", "return data"
        ], in: bridge)
        #expect(bridge.contains(#"method: "POST""#))
        #expect(bridge.components(separatedBy: "performAuthenticatedRequest(").count == 2)
        for token in ["catch", "JSONDecoder", "Task", "URLSession", "SupabaseManager", "@escaping",
                      "timeoutInterval:", "idempotencyKey:", "isRetry:"] {
            #expect(!bridge.contains(token), "Raw bridge must not add \(token)")
        }
        for token in ["private func endpointURL(", "private func performAuthenticatedRequest(",
                      "private func performAuthenticatedTransport(", "private func acquireAccountWorkLeaseIfRequired("] {
            #expect(client.contains(token))
        }
    }

    @Test func DTOsAndStrictDecodingHaveContainedOwners() throws {
        let models = try source("ScanLifecycleAPIModels.swift")
        let decoder = try source("Decoding/ScanLifecycleResponseDecoder.swift")
        let client = try source("MerianNetworkClient.swift")
        for declaration in ["enum ScanCloudStatus:", "enum ScanIngestionJobStatus:",
                            "enum ComplimentaryScanState:", "struct ScanStatusResponse:"] {
            #expect(models.contains(declaration) && !client.contains(declaration))
        }
        #expect(models.contains("case scanId = \"scan_id\"") && models.contains("case jobAttemptCount = \"job_attempt_count\""))
        #expect(models.contains("if rawValue == \"failed_terminal\"") && models.contains("self = .failed"))
        for declaration in ["private struct BulkScanStatusResponse:", "private struct DeleteScanResponse:"] {
            #expect(decoder.contains(declaration) && !client.contains(declaration) && !models.contains(declaration))
        }
        #expect(decoder.contains("JSONDecoder().decode(type, from: data)"))
        #expect(!decoder.contains("keyDecodingStrategy"))
        #expect(decoder.contains("throw MerianError.invalidResponse"))
        for contents in [models, decoder] {
            #expect(contents.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
            for token in ["URLSession", "Supabase", "MerianNetworkClient", "Task", "@MainActor", "static var", "@escaping"] {
                #expect(!contents.contains(token), "Wire/decoding owners must not acquire \(token)")
            }
        }
    }

    @Test func rehomedTestsKeepNamesAndUsePrivateTransportFixtures() throws {
        let root = try repositoryRoot().appendingPathComponent("apps/ios/MerianTests/Core/Network")
        let aggregate = try String(contentsOf: root.appendingPathComponent("MerianNetworkClientTests.swift"), encoding: .utf8)
        let suites = [
            "ScanStatusEndpointTests": ["testCheckScanStatusDetailsDecodesJobStateAndRequiredVideoCount",
                                        "testCheckScanStatusDetailsSendsOwnedRecoveryPayload",
                                        "testCheckScanStatusRejectsMalformedOrMismatchedSuccess",
                                        "testBulkScanStatusRejectsDuplicateMissingOrForeignRows"],
            "ScanDeletionEndpointTests": ["testDeleteScanEndpoint", "testDeleteScanRejectsUnconfirmedSuccessResponse"]
        ]
        for (suite, names) in suites {
            let contents = try String(contentsOf: root.appendingPathComponent("Endpoints/\(suite).swift"), encoding: .utf8)
            for name in names {
                #expect(contents.contains("func \(name)(") && !aggregate.contains("func \(name)("))
            }
        }
        for suite in Array(suites.keys) + ["ScanLifecycleNetworkEndpointTests", "ScanLifecycleNetworkTransportTests"] {
            let contents = try String(contentsOf: root.appendingPathComponent("Endpoints/\(suite).swift"), encoding: .utf8)
            #expect(contents.contains("NetworkEndpointFixture()"))
            #expect(!contents.contains("MerianNetworkClient.shared") && !contents.contains("MockURLProtocol.mockEndpoints"))
        }
        #expect(aggregate.contains("func testMissingScanRecoveryNeverRacesActiveOrRetryableIngestion("))
        #expect(aggregate.contains("func testEdgeFunctionSelfHealingRefreshesInvalidSessionBeforeRetry("))
    }

    private func method(_ name: String, in source: String) throws -> String {
        let start = try #require(source.range(of: "    func \(name)("))
        let end = try #require(source.range(of: "\n    }", range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.upperBound])
    }

    private func expectOrder(_ tokens: [String], in source: String) throws {
        var cursor = source.startIndex
        for token in tokens {
            let found = try #require(source.range(of: token, range: cursor..<source.endIndex), "Missing or out-of-order: \(token)")
            cursor = found.upperBound
        }
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent("apps/ios/Merian/Core/Network/\(path)"), encoding: .utf8)
    }

    private func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("project.yml").path) { return directory }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
