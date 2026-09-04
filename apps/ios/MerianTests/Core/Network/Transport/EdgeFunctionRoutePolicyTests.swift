import Foundation
import Testing

@testable import Merian

@Suite("Edge Function Route Policy")
struct EdgeFunctionRoutePolicyTests {
    @Test func endpointURLRequiresHTTPS() throws {
        let url = try EdgeFunctionRoutePolicy.endpointURL(
            baseURL: "https://example.supabase.co",
            function: "get-explore-feed"
        )
        #expect(
            url.absoluteString
                == "https://example.supabase.co/functions/v1/get-explore-feed"
        )

        #expect(throws: MerianError.invalidURL) {
            try EdgeFunctionRoutePolicy.endpointURL(
                baseURL: "http://example.supabase.co",
                function: "get-explore-feed"
            )
        }
    }

    @Test func unavailableRouteRetryScheduleRemainsBounded() {
        #expect(EdgeFunctionRoutePolicy.unavailableRetryLimit == 3)
        #expect(
            EdgeFunctionRoutePolicy.unavailableRetryDelay(forAttempt: 0)
                == 1_000_000_000
        )
        #expect(
            EdgeFunctionRoutePolicy.unavailableRetryDelay(forAttempt: 1)
                == 2_000_000_000
        )
        #expect(
            EdgeFunctionRoutePolicy.unavailableRetryDelay(forAttempt: 2)
                == 4_000_000_000
        )
        #expect(
            EdgeFunctionRoutePolicy.unavailableRetryDelay(forAttempt: -1)
                == nil
        )
        #expect(
            EdgeFunctionRoutePolicy.unavailableRetryDelay(forAttempt: 3)
                == nil
        )
    }

    @Test func routeEvidenceBoundsRetryAfterSeconds() throws {
        let url = try #require(URL(string: "https://example.supabase.co"))
        let accepted = try response(
            url: url,
            headers: ["Retry-After": " 86400 "]
        )
        let zero = try response(url: url, headers: ["Retry-After": "0"])
        let oversized = try response(
            url: url,
            headers: ["Retry-After": "86401"]
        )

        #expect(
            EdgeFunctionRouteResponseEvidence(response: accepted)
                .retryAfterSeconds == 86_400
        )
        #expect(
            EdgeFunctionRouteResponseEvidence(response: zero)
                .retryAfterSeconds == nil
        )
        #expect(
            EdgeFunctionRouteResponseEvidence(response: oversized)
                .retryAfterSeconds == nil
        )
    }

    @Test func testPlatformFunctionRouteClassifierPreservesGatewayHandlerBoundary() throws {
        let url = try #require(
            URL(
                string: "https://example.supabase.co/functions/v1/share-scan-to-explore"
            )
        )
        let officialPayload = Data(
            #"{"code":"NOT_FOUND","message":"Requested function was not found"}"#.utf8
        )
        let platformResponse = try response(url: url)
        #expect(EdgeFunctionRoutePolicy.isUnavailable(
            evidence: EdgeFunctionRouteResponseEvidence(
                response: platformResponse
            ),
            responseData: officialPayload
        ))

        let headerResponse = try response(
            url: url,
            headers: ["SB-Error-Code": "not_found"]
        )
        #expect(EdgeFunctionRoutePolicy.isUnavailable(
            evidence: EdgeFunctionRouteResponseEvidence(response: headerResponse),
            responseData: Data("{}".utf8)
        ))

        let handlerResponse = try response(
            url: url,
            headers: [
                "X-Merian-Handler": " 1 ",
                "SB-Error-Code": "NOT_FOUND"
            ]
        )
        #expect(!EdgeFunctionRoutePolicy.isUnavailable(
            evidence: EdgeFunctionRouteResponseEvidence(response: handlerResponse),
            responseData: officialPayload
        ))

        let gatewayResponse = try response(
            url: url,
            headers: ["SB-Gateway-Version": "1"]
        )
        #expect(EdgeFunctionRoutePolicy.isUnavailable(
            evidence: EdgeFunctionRouteResponseEvidence(response: gatewayResponse),
            responseData: Data("{}".utf8)
        ))

        let executedResponse = try response(
            url: url,
            headers: [
                "SB-Gateway-Version": "1",
                "X-Deno-Execution-Id": "019fa6ef-3ba3-7acc-9dbc-a9ec785f4152"
            ]
        )
        #expect(!EdgeFunctionRoutePolicy.isUnavailable(
            evidence: EdgeFunctionRouteResponseEvidence(response: executedResponse),
            responseData: Data("{}".utf8)
        ))

        let serverErrorResponse = try response(
            url: url,
            statusCode: 503,
            headers: ["SB-Error-Code": "NOT_FOUND"]
        )
        #expect(!EdgeFunctionRoutePolicy.isUnavailable(
            evidence: EdgeFunctionRouteResponseEvidence(
                response: serverErrorResponse
            ),
            responseData: officialPayload
        ))
    }

    private func response(
        url: URL,
        statusCode: Int = 404,
        headers: [String: String]? = nil
    ) throws -> HTTPURLResponse {
        try #require(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )
        )
    }
}
