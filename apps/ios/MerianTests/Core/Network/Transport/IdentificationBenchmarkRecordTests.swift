import Foundation
import Testing

@testable import Merian

@Suite("Identification Benchmark Record")
struct IdentificationBenchmarkRecordTests {
    @Test func projectsFreshMetadataAndSeparatesProviderFromOtherEdgeWork() throws {
        let value = try record(header: fixture())
        #expect(value["delivery"] as? String == "fresh")
        #expect(value["timingStatus"] as? String == "valid")
        #expect(value["otherEdgeMs"] as? Double == 80)
        let diagnostics = try #require(value["diagnostics"] as? [String: Any])
        #expect(diagnostics["requestedModel"] as? String == "gemini-2.5-flash")
        #expect(diagnostics["returnedModel"] as? String == "gemini-2.5-flash-001")
        let usage = try #require(diagnostics["usage"] as? [String: Any])
        #expect(usage["thinkingTokens"] as? Int == 5)
        #expect(usage["cachedTokens"] as? Int == 0)
    }

    @Test func ignoresBodyLikeFieldsAndUnknownAppConfiguration() throws {
        var header = fixture()
        header["rawProviderText"] = "synthetic-private-content"
        var app = appInfo
        app["unrelatedConfiguration"] = "synthetic-private-content"
        let value = try record(header: header, app: app)
        let data = try JSONSerialization.data(withJSONObject: value)
        #expect(!String(decoding: data, as: UTF8.self).contains("synthetic-private-content"))
    }

    @Test func replaysAndFailuresCannotClaimFreshUsage() throws {
        for (status, replay) in [(200, true), (503, false)] {
            let value = try record(header: fixture(), status: status, replay: replay)
            #expect(value["diagnostics"] is NSNull)
            #expect(value["delivery"] as? String == (replay ? "replay" : "unavailable"))
        }
    }

    @Test func oldServerAndMissingBuildKeepUnknowns() throws {
        let value = try record(header: nil, app: ["MERIAN_SOURCE_REVISION": "unavailable"])
        #expect(value["delivery"] as? String == "unavailable")
        let app = try #require(value["app"] as? [String: Any])
        #expect(app.values.allSatisfy { $0 is NSNull })
    }

    @Test func bothReplaySourcesAndUnknownMarkersCannotClaimNewUsage() throws {
        for source in ["stored", "reconstructed", "unknown"] {
            let response = try #require(HTTPURLResponse(
                url: URL(string: "https://example.invalid/identify-multimodal")!,
                statusCode: 200, httpVersion: nil,
                headerFields: [
                    "X-Merian-Idempotent-Replay": source,
                    "X-Merian-Identification": String(decoding: try JSONSerialization.data(withJSONObject: fixture()), as: UTF8.self)
                ]
            ))
            let text = try #require(IdentificationBenchmarkRecord.make(response: response, appInfo: appInfo))
            let value = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            #expect(value["delivery"] as? String == (source == "unknown" ? "unavailable" : "replay"))
            #expect(value["diagnostics"] is NSNull)
        }
    }

    @Test func maximumProjectedRecordFitsCompactLogBudget() throws {
        var header = fixture()
        header["returnedModel"] = "gemini-" + String(repeating: "a", count: 100)
        header["usage"] = Dictionary(uniqueKeysWithValues: [
            "promptTokens", "candidateTokens", "thinkingTokens", "totalTokens", "cachedTokens", "toolTokens"
        ].map { ($0, 10_000_000) })
        var app = appInfo
        app["CFBundleShortVersionString"] = "12345.12345.12345.12345"
        app["CFBundleVersion"] = "1234567890.12345.12345"
        app["MERIAN_SOURCE_REVISION"] = String(repeating: "a", count: 64)
        let value = try record(header: header, timing: "provider;dur=123456.123456, edge_total;dur=234567.234567, gemini;dur=123460", app: app)
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        #expect(encoded.count + IdentificationBenchmarkRecord.marker.utf8.count <= 1_024)
        #expect(Set(try #require(value["serverTimingMs"] as? [String: Double]).keys) == ["provider", "edge_total"])
    }

    @Test func acceptsCompleteThirteenSpanProductionTimingHeader() throws {
        let timing = "auth;dur=1.0, body_read;dur=0.1, tier;dur=0.2, pre_gemini_db;dur=2.0, gemini;dur=25.0, quota_commit;dur=5.0, provider;dur=20.0, video_promotion;dur=0.0, primary_enrichment;dur=3.0, database_finalization;dur=4.0, dictionary;dur=5.0, post_gemini;dur=10.0, edge_total;dur=100.0"
        let value = try record(header: fixture(), timing: timing)
        #expect(value["timingStatus"] as? String == "valid")
        #expect(value["serverTimingMs"] as? [String: Double] == ["provider": 20, "edge_total": 100])
        #expect(value["otherEdgeMs"] as? Double == 80)
        let rejected = try record(header: fixture(), timing: timing + ", proxy;dur=1")
        #expect(rejected["timingStatus"] as? String == "too_many_metrics")
        #expect((rejected["serverTimingMs"] as? [String: Double])?.isEmpty == true)
    }

    @Test func timingFailuresRetainOnlyFixedReasons() throws {
        let cases: [(String?, String)] = [
            (nil, "absent"), (String(repeating: "x", count: 2_049), "oversized"),
            ("provider", "invalid_syntax"), ("synthetic-private;dur=1", "unknown_metric"),
            ("provider;dur=1, provider;dur=2", "duplicate_metric"),
            ("provider;dur=NaN", "invalid_duration")
        ]
        for (timing, reason) in cases {
            let value = try record(header: fixture(), timing: timing)
            #expect(value["timingStatus"] as? String == reason)
            #expect((value["serverTimingMs"] as? [String: Double])?.isEmpty == true)
            #expect(value["otherEdgeMs"] is NSNull)
            #expect(!String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self).contains("synthetic-private"))
        }
    }

    @Test func invalidMetadataCannotLeakAndBadUsageStaysUnknown() throws {
        for key in ["provider", "requestedModel", "backendBundleSha256"] {
            var header = fixture()
            header[key] = "synthetic-private-content"
            #expect(try record(header: header)["diagnostics"] is NSNull)
        }
        var header = fixture()
        header["returnedModel"] = "gemini-invalid\n"
        header["usage"] = ["promptTokens": -1, "thinkingTokens": 10_000_001]
        let diagnostics = try #require(try record(header: header)["diagnostics"] as? [String: Any])
        #expect(diagnostics["returnedModel"] is NSNull)
        let usage = try #require(diagnostics["usage"] as? [String: Any])
        #expect(usage.values.allSatisfy { $0 is NSNull })
    }

    @Test func rejectsMalformedDuplicateOrOversizedTimingAndHeader() throws {
        for timing in [
            "provider;dur=1, provider;dur=2", "provider;dur=NaN",
            "provider;dur=600001", "unknown;dur=1", "provider;dur=1;desc=private"
        ] {
            let value = try record(header: fixture(), timing: timing)
            #expect((value["serverTimingMs"] as? [String: Any])?.isEmpty == true)
            #expect(value["otherEdgeMs"] is NSNull)
        }
        var header = fixture()
        header["extra"] = String(repeating: "x", count: 2_049)
        #expect(try record(header: header)["diagnostics"] is NSNull)
        #expect(try record(header: fixture(), timing: "provider;dur=200, edge_total;dur=100")["otherEdgeMs"] is NSNull)
    }

    @Test func builtTestHostRetainsSourceProvenanceAfterPlistProcessing() throws {
        // The old phase ran before ProcessInfoPlistFile and was silently overwritten.
        let app = try #require(try record(header: nil, app: Bundle.main.infoDictionary ?? [:])["app"] as? [String: Any])
        #expect(app["sourceRevision"] is String)
        #expect(app["sourceFingerprint"] is String)
        #expect(app["sourceState"] is String)
    }

    private var appInfo: [String: Any] {
        ["CFBundleShortVersionString": "1.0.3", "CFBundleVersion": "275",
         "MERIAN_SOURCE_REVISION": String(repeating: "a", count: 40),
         "MERIAN_SOURCE_FINGERPRINT": String(repeating: "b", count: 64),
         "MERIAN_SOURCE_STATE": "dirty"]
    }

    private func fixture() -> [String: Any] {
        ["version": 1, "provider": "gemini", "requestedModel": "gemini-2.5-flash",
         "returnedModel": "gemini-2.5-flash-001",
         "backendBundleSha256": String(repeating: "c", count: 64),
         "usage": ["promptTokens": 10, "candidateTokens": 20, "thinkingTokens": 5,
                   "totalTokens": 35, "cachedTokens": 0, "toolTokens": 0]]
    }

    private func record(
        header: [String: Any]?, status: Int = 200, replay: Bool = false,
        timing: String? = "auth;dur=1, provider;dur=20, gemini;dur=25, edge_total;dur=100",
        app: [String: Any]? = nil
    ) throws -> [String: Any] {
        var headers: [String: String] = [:]
        if let timing { headers["Server-Timing"] = timing }
        if let header {
            headers["X-Merian-Identification"] = String(decoding: try JSONSerialization.data(withJSONObject: header), as: UTF8.self)
        }
        if replay { headers["X-Merian-Idempotent-Replay"] = "stored" }
        let response = try #require(HTTPURLResponse(url: URL(string: "https://example.invalid/identify-multimodal")!, statusCode: status, httpVersion: nil, headerFields: headers))
        let text = try #require(IdentificationBenchmarkRecord.make(response: response, appInfo: app ?? appInfo))
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
