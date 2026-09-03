import Foundation
import Testing

@testable import Merian

@Suite("Scan Image Cloud Endpoints")
@MainActor
struct ScanImageCloudEndpointTests {
    @Test func testScanImageCloudInspectionSendsSourceAndParsesMissingStatus() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let sourceUrl =
            "https://media.merian.app/public_uploads/free/user/old.webp"
        let responseData = Data("""
        {
          "data": {
            "status": "missing"
          }
        }
        """.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        fixture.transport.register(path: "/repair-scan-image") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(payload["source_url"] as? String == sourceUrl)
            #expect(payload["restored_object_key"] == nil)
            return (response, responseData)
        }

        let result = try await fixture.client
            .inspectScanImageCloudStatus(sourceUrl: sourceUrl)

        #expect(result.status == .missing)
        #expect(result.updatedScanCount == 0)
        #expect(result.updatedPostMediaCount == 0)
    }

    @Test func testScanImageCloudRepairSendsStagedKeyAndParsesCounts() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let sourceUrl =
            "https://media.merian.app/public_uploads/free/user/old.webp"
        let restoredObjectKey = "staging/user/repair_new.webp"
        let responseData = Data("""
        {
          "data": {
            "status": "repaired",
            "replacement_url": "https://media.merian.app/public_uploads/pro/user/repair_new.webp",
            "updated_scan_count": 1,
            "updated_post_media_count": 2
          }
        }
        """.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        fixture.transport.register(path: "/repair-scan-image") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(payload["source_url"] as? String == sourceUrl)
            #expect(
                payload["restored_object_key"] as? String == restoredObjectKey
            )
            return (response, responseData)
        }

        let result = try await fixture.client
            .repairScanImageCloudReference(
                sourceUrl: sourceUrl,
                restoredObjectKey: restoredObjectKey
            )

        #expect(result.status == .repaired)
        #expect(result.updatedScanCount == 1)
        #expect(result.updatedPostMediaCount == 2)
    }

    @Test(arguments: [false, true])
    func emptyRawValuesAndInspectOmissionRemainUnchanged(repair: Bool) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("One raw inspection or repair") { sent in
            fixture.transport.register(path: "/repair-scan-image") { request in
                sent()
                let json = repair ? #"{"source_url":"","restored_object_key":""}"# : #"{"source_url":""}"#
                try NetworkEndpointTestSupport.expectPOST(request, function: "repair-scan-image", json: json)
                return try NetworkEndpointTestSupport.response(
                    to: request, json: #"{"data":{"status":"not_referenced","updated_scan_count":null}}"#
                )
            }
            let value = try await repair
                ? fixture.client.repairScanImageCloudReference(sourceUrl: "", restoredObjectKey: "")
                : fixture.client.inspectScanImageCloudStatus(sourceUrl: "")
            #expect(value.status == .notReferenced)
            #expect(value.updatedScanCount == 0 && value.updatedPostMediaCount == 0 && value.replacementUrl == nil)
        }
    }

    @Test(arguments: [false, true], ["healthy", "missing", "not_referenced", "repaired"])
    func validStatusesAreProjectedWithoutCallerWorkflowPolicy(repair: Bool, status: String) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/repair-scan-image") { request in
            try NetworkEndpointTestSupport.response(to: request, json: #"{"data":{"status":"\#(status)"}}"#)
        }
        let value = try await repair
            ? fixture.client.repairScanImageCloudReference(sourceUrl: "raw", restoredObjectKey: "raw")
            : fixture.client.inspectScanImageCloudStatus(sourceUrl: "raw")
        #expect(value.status.rawValue == status)
    }

    @Test(arguments: [false, true], ["", "null", "[]", "{}", #"{"data":null}"#, #"{"data":{}}"#,
                                    #"{"data":{"status":"unknown"}}"#, #"{"data":{"status":"healthy","updated_scan_count":"1"}}"#])
    func missingEnvelopeAndMalformedFieldsPropagateDecodingErrors(repair: Bool, json: String) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/repair-scan-image") { request in
            try NetworkEndpointTestSupport.response(to: request, json: json)
        }
        await #expect(throws: DecodingError.self) {
            if repair {
                _ = try await fixture.client.repairScanImageCloudReference(sourceUrl: "raw", restoredObjectKey: "raw")
            } else {
                _ = try await fixture.client.inspectScanImageCloudStatus(sourceUrl: "raw")
            }
        }
    }
}
