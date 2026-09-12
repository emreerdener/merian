import Foundation

/// Classifies transport failures at the two distinct scan-ownership boundaries.
/// Before durability, only reviewed offline/data-path failures may select the
/// queue-only admission route. After durability, a generic secure-connection
/// failure may also relinquish the foreground request to the existing queue;
/// certificate, authentication, and ATS policy failures remain outside both
/// sets even when wrapped by a broader transport error. An incompletely
/// inspected over-depth chain also remains outside both sets.
enum ScanConnectivityFailurePolicy {
    private struct URLFailureChain {
        let codes: Set<URLError.Code>
        let wasFullyInspected: Bool
    }

    private static let queueOnlyAdmissionCodes: Set<URLError.Code> = [
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

    private static let durableRecoveryCodes =
        queueOnlyAdmissionCodes.union([.secureConnectionFailed])

    /// These failures represent explicit security or credential policy rather
    /// than loss of network reachability. They veto connectivity recovery even
    /// when a broader URL error earlier in the wrapper chain would otherwise be
    /// eligible. This prevents, for example, `.secureConnectionFailed` wrapping
    /// `.serverCertificateUntrusted` from being treated as ordinary offline
    /// recovery.
    private static let policyFailureCodes: Set<URLError.Code> = [
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

    private static let queueOnlyAdmissionVetoCodes =
        policyFailureCodes.union([.cancelled, .secureConnectionFailed])

    static func isQueueOnlyAdmissionFailure(_ error: Error) -> Bool {
        containsURLFailure(
            error,
            in: queueOnlyAdmissionCodes,
            vetoedBy: queueOnlyAdmissionVetoCodes
        )
    }

    static func isDurableRecoveryFailure(_ error: Error) -> Bool {
        containsURLFailure(
            error,
            in: durableRecoveryCodes,
            vetoedBy: policyFailureCodes
        )
    }

    private static func containsURLFailure(
        _ error: Error,
        in codes: Set<URLError.Code>,
        vetoedBy vetoCodes: Set<URLError.Code>
    ) -> Bool {
        let chain = urlFailureChain(in: error)
        guard chain.wasFullyInspected,
              chain.codes.isDisjoint(with: vetoCodes) else {
            return false
        }
        return !chain.codes.isDisjoint(with: codes)
    }

    private static func urlFailureChain(
        in error: Error,
        depth: Int = 0
    ) -> URLFailureChain {
        guard depth < 4 else {
            return URLFailureChain(codes: [], wasFullyInspected: false)
        }

        let nsError = error as NSError
        var codes: Set<URLError.Code> = []
        if nsError.domain == NSURLErrorDomain {
            codes.insert(URLError.Code(rawValue: nsError.code))
        }

        guard let underlyingError = nsError.userInfo[NSUnderlyingErrorKey]
            as? Error else {
            return URLFailureChain(codes: codes, wasFullyInspected: true)
        }
        let underlyingChain = urlFailureChain(
            in: underlyingError,
            depth: depth + 1
        )
        codes.formUnion(underlyingChain.codes)
        return URLFailureChain(
            codes: codes,
            wasFullyInspected: underlyingChain.wasFullyInspected
        )
    }
}
