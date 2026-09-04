import Foundation
import Testing

@testable import Merian

@Suite("Edge Function Error Policy")
struct EdgeFunctionErrorPolicyTests {
    @Test func stableCodeNormalizesOnlyBoundedMachineCodes() {
        #expect(
            EdgeFunctionErrorPolicy.stableCode(
                responseData: Data(#"{"code":" NOT_FOUND "}"#.utf8)
            ) == "not_found"
        )
        #expect(
            EdgeFunctionErrorPolicy.stableCode(
                responseData: Data(#"{"code":"9_invalid"}"#.utf8)
            ) == nil
        )
        #expect(
            EdgeFunctionErrorPolicy.stableCode(
                responseData: Data(#"{"code":"invalid-code"}"#.utf8)
            ) == nil
        )
        #expect(
            EdgeFunctionErrorPolicy.stableCode(
                responseData: Data("not-json".utf8)
            ) == nil
        )
    }

    @Test func stableCodeReadsOnlyHTTPErrorPayloads() {
        let error = MerianError.httpError(
            statusCode: 404,
            message: #"{"code":"species_not_available"}"#
        )
        #expect(
            EdgeFunctionErrorPolicy.stableCode(from: error)
                == "species_not_available"
        )
        #expect(
            EdgeFunctionErrorPolicy.stableCode(from: MerianError.invalidResponse)
                == nil
        )
    }

    @Test func refreshableAuthErrorsRequireReviewedEvidence() {
        #expect(EdgeFunctionErrorPolicy.isRefreshableAuthSessionError(
            responseData: Data(#"{"code":"auth_session_missing"}"#.utf8),
            fallbackMessage: ""
        ))
        #expect(EdgeFunctionErrorPolicy.isRefreshableAuthSessionError(
            responseData: Data(
                #"{"error":"Invalid or expired session token"}"#.utf8
            ),
            fallbackMessage: ""
        ))
        #expect(EdgeFunctionErrorPolicy.isRefreshableAuthSessionError(
            responseData: Data(),
            fallbackMessage: "Auth session missing"
        ))
        #expect(!EdgeFunctionErrorPolicy.isRefreshableAuthSessionError(
            responseData: Data(#"{"code":"unauthorized"}"#.utf8),
            fallbackMessage: "Access denied"
        ))
    }
}
