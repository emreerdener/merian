import Foundation
import Testing

@testable import Merian

@Suite("Inference Live Failure Policy")
struct InferenceLiveFailurePolicyTests {
    private typealias Policy = InferenceLiveFailurePolicy

    @Test func taskCancellationTakesPrecedenceOverReturnedErrors() {
        let errors: [Error] = [
            CancellationError(), URLError(.cancelled), URLError(.timedOut),
            MerianError.decodingFailed, MerianError.aiConsentRequired,
            httpError(429, code: "ai_quota_daily_exceeded")
        ]
        for error in errors {
            #expect(Policy.interruption(for: error, isTaskCancelled: true) == .taskCancellation)
        }
    }

    @Test func logicalAndTransportCancellationRemainDistinct() {
        #expect(Policy.interruption(
            for: CancellationError(), isTaskCancelled: false
        ) == .ownershipCancellation)
        #expect(Policy.interruption(
            for: URLError(.cancelled), isTaskCancelled: false
        ) == .transportCancellation)
        #expect(Policy.interruption(
            for: MerianError.networkTimeout, isTaskCancelled: false
        ) == nil)
        // Preserve the existing direct-URLError rule; do not broaden it to any
        // arbitrary error containing an underlying cancellation.
        let wrapped = NSError(
            domain: "InferencePolicyTest", code: 1,
            userInfo: [NSUnderlyingErrorKey: URLError(.cancelled)]
        )
        #expect(Policy.interruption(for: wrapped, isTaskCancelled: false) == nil)
    }

    @Test func retirementReasonsRetainTheirModalityIdentity() {
        #expect(Policy.Mode.visual.cancellationReason == "live_request_cancelled")
        #expect(Policy.Mode.visual.transportCancellationReason == "live_transport_cancelled")
        #expect(Policy.Mode.visual.failureReason == "live_request_failed")
        for hasAudio in [true, false] {
            let mode = Policy.Mode.nonVisual(hasAudio: hasAudio)
            #expect(mode.cancellationReason == "live_nonvisual_cancelled")
            #expect(mode.transportCancellationReason == "live_nonvisual_transport_cancelled")
            #expect(mode.failureReason == "live_nonvisual_failed")
        }
    }

    @Test func knownProviderPoliciesRequireTheirExactHTTPStatus() {
        let cases: [(Int, String, Policy.Failure)] = [
            (409, "ai_request_already_completed", .recoverableConflict),
            (409, "ai_request_in_progress", .recoverableConflict),
            (409, "scan_already_complete", .recoverableConflict),
            (409, "scan_already_finalized", .recoverableConflict),
            (402, "pro_required", .proRequired),
            (429, "ai_quota_daily_exceeded", .dailyQuotaExceeded),
            (429, "ai_user_rate_limit_exceeded", .rateLimited(.user)),
            (429, "ai_ip_rate_limit_exceeded", .rateLimited(.ip)),
            (400, "observation_rejected", .observationRejected)
        ]
        for mode in modes {
            for (expectedStatus, code, failure) in cases {
                for status in [400, 402, 403, 409, 429, 500] {
                    #expect(Policy.failure(
                        for: httpError(status, code: code), mode: mode
                    ) == (status == expectedStatus ? failure : .service))
                }
            }
        }
    }

    @Test func stableCodeParsingRetainsNetworkCompatibility() {
        #expect(Policy.failure(
            for: httpError(402, code: "  PRO_REQUIRED  "), mode: .visual
        ) == .proRequired)
        for message in [
            "pro_required", #"{"message":"pro_required"}"#,
            #"{"code":"unknown_code"}"#, #"{"code":null}"#,
            #"{"code":15}"#, #"{"code":"pro-required"}"#
        ] {
            #expect(Policy.failure(
                for: MerianError.httpError(statusCode: 402, message: message),
                mode: .visual
            ) == .service)
        }
    }

    @Test func decodingKeepsTheExistingVisualOnlyException() {
        for mode in modes {
            let failure = Policy.failure(for: MerianError.decodingFailed, mode: mode)
            #expect(failure == (mode == .visual ? .visualDecoding : .service))
            #expect(failure.recordsCircuitFailure == (mode != .visual))
            #expect(failure.triggersErrorFeedback)
            let expectedEvent: String
            switch mode {
            case .visual:
                expectedEvent = "APIDecodingFailure"
            case .nonVisual(let hasAudio):
                expectedEvent = hasAudio ? "InferenceServiceFailure" : "DescribeInferenceFailure"
            }
            #expect(failure.telemetryEvent(for: mode) == expectedEvent)
        }
    }

    @Test func consentAndSpecialPoliciesStayOutsideCircuitFailure() {
        let cases: [(Policy.Failure, String, Bool)] = [
            (.recoverableConflict, "InferenceCompletionRecovery", false),
            (.consentRequired, "InferenceConsentRequired", true),
            (.proRequired, "InferenceProRequired", true),
            (.dailyQuotaExceeded, "InferenceDailyQuotaExceeded", false),
            (.rateLimited(.user), "InferenceRateLimited", true),
            (.rateLimited(.ip), "InferenceRateLimited", true),
            (.observationRejected, "InferenceObservationRejected", true),
            (.visualDecoding, "APIDecodingFailure", true)
        ]
        for mode in modes {
            #expect(Policy.failure(for: MerianError.aiConsentRequired, mode: mode) == .consentRequired)
            for (failure, event, feedback) in cases {
                #expect(!failure.recordsCircuitFailure)
                #expect(failure.triggersErrorFeedback == feedback)
                #expect(failure.telemetryEvent(for: mode) == event)
            }
            #expect(Policy.Failure.connectivity.recordsCircuitFailure)
            #expect(Policy.Failure.connectivity.telemetryEvent(for: mode) == "InferenceNetworkFailure")
            #expect(Policy.Failure.service.recordsCircuitFailure)
        }
    }

    @Test func connectivityReusesTheSharedSecurityVeto() {
        let errors: [Error] = [
            MerianError.networkTimeout, URLError(.timedOut), URLError(.secureConnectionFailed)
        ]
        for error in errors {
            #expect(Policy.isConnectivityFailure(error))
            #expect(Policy.failure(for: error, mode: .visual) == .connectivity)
        }
        let wrappedOffline = NSError(
            domain: "InferencePolicyTest", code: 1,
            userInfo: [NSUnderlyingErrorKey: URLError(.notConnectedToInternet)]
        )
        #expect(Policy.isConnectivityFailure(wrappedOffline))
        for code in [URLError.Code.serverCertificateUntrusted, .userAuthenticationRequired,
                     .appTransportSecurityRequiresSecureConnection] {
            let policyError = NSError(
                domain: NSURLErrorDomain, code: URLError.Code.timedOut.rawValue,
                userInfo: [NSUnderlyingErrorKey: URLError(code)]
            )
            #expect(!Policy.isConnectivityFailure(policyError))
            #expect(Policy.failure(for: policyError, mode: .visual) == .service)
        }
        #expect(!Policy.isConnectivityFailure(MerianError.edgeFunctionUnavailable))
        #expect(!Policy.isConnectivityFailure(httpError(503, code: "service_unavailable")))
    }

    private var modes: [Policy.Mode] {
        [.visual, .nonVisual(hasAudio: true), .nonVisual(hasAudio: false)]
    }

    private func httpError(_ status: Int, code: String) -> MerianError {
        .httpError(statusCode: status, message: #"{"code":"\#(code)"}"#)
    }
}
