import Foundation
import Testing

@testable import Merian

@Suite("Scan connectivity failure policy")
struct ScanConnectivityFailurePolicyTests {
    @Test func connectivityFailuresSelectQueueOnlyAdmission() {
        let reviewedConnectivityCodes: [URLError.Code] = [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .internationalRoamingOff,
            .callIsActive,
            .dataNotAllowed,
            .backgroundSessionWasDisconnected,
            .cannotLoadFromNetwork
        ]

        for code in reviewedConnectivityCodes {
            #expect(ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
                URLError(code)
            ))
        }

        #expect(ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
            wrapped(URLError(.notConnectedToInternet), layers: 3)
        ))
        #expect(!ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
            wrapped(URLError(.notConnectedToInternet), layers: 4)
        ))
    }

    @Test func authenticationAndTrustFailuresRemainFailClosed() {
        let policyFailureCodes: [URLError.Code] = [
            .userCancelledAuthentication,
            .userAuthenticationRequired,
            .appTransportSecurityRequiresSecureConnection,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired
        ]
        let admissionVetoCodes: [URLError.Code] = [
            .cancelled,
            .secureConnectionFailed
        ] + policyFailureCodes

        for code in admissionVetoCodes {
            #expect(!ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
                URLError(code)
            ))
        }

        for code in policyFailureCodes {
            let wrappedPolicyFailure = NSError(
                domain: NSURLErrorDomain,
                code: URLError.Code.timedOut.rawValue,
                userInfo: [NSUnderlyingErrorKey: URLError(code)]
            )
            #expect(!ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
                wrappedPolicyFailure
            ))
            #expect(!ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
                wrappedPolicyFailure
            ))
        }

        let deepestInspectedPolicyFailure = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.timedOut.rawValue,
            userInfo: [
                NSUnderlyingErrorKey: wrapped(
                    URLError(.serverCertificateUntrusted),
                    layers: 2
                )
            ]
        )
        #expect(!ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
            deepestInspectedPolicyFailure
        ))
        #expect(!ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
            deepestInspectedPolicyFailure
        ))
    }

    @Test func secureTransportFailuresUseOnlyDurableRecovery() {
        #expect(ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
            URLError(.secureConnectionFailed)
        ))
        #expect(!ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
            URLError(.serverCertificateUntrusted)
        ))

        let wrappedTransportFailure = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.secureConnectionFailed.rawValue,
            userInfo: [
                NSUnderlyingErrorKey: URLError(.notConnectedToInternet)
            ]
        )
        #expect(!ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
            wrappedTransportFailure
        ))
        #expect(ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
            wrappedTransportFailure
        ))

        let wrappedCertificateFailure = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.secureConnectionFailed.rawValue,
            userInfo: [
                NSUnderlyingErrorKey: URLError(.serverCertificateUntrusted)
            ]
        )
        #expect(!ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
            wrappedCertificateFailure
        ))
    }

    private func wrapped(_ error: Error, layers: Int) -> Error {
        (0..<layers).reduce(error) { underlyingError, layer in
            NSError(
                domain: "ScanAdmissionTransportWrapper.\(layer)",
                code: layer,
                userInfo: [NSUnderlyingErrorKey: underlyingError]
            )
        }
    }
}
