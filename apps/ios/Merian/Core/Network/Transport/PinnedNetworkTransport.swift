import CryptoKit
import Foundation
import os
import Security

/// Value-only certificate policy used by the pinned Supabase session delegate.
enum MerianTLSCertificatePinPolicy {
    // Leaf cert (expires approximately every 90 days).
    // Intermediate CA remains the rotation fallback.
    static let pinnedCertificateHashes: Set<String> = [
        "OYvM4tmVyyPLCSqTe1tYvZW0CKRfv4mre7EUA0eJrn0=",
        "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="
    ]

    static func accepts(
        systemTrustIsValid: Bool,
        certificateChainHashes: [String]?
    ) -> Bool {
        guard systemTrustIsValid, let certificateChainHashes else {
            return false
        }
        return !pinnedCertificateHashes.isEmpty && certificateChainHashes.contains {
            pinnedCertificateHashes.contains($0)
        }
    }

    static func requiresPinning(host: String) -> Bool {
        let lowercaseHost = host.lowercased()
        let normalizedHost = lowercaseHost.last == "."
            ? String(lowercaseHost.dropLast())
            : lowercaseHost
        return normalizedHost == "supabase.co"
            || (
                normalizedHost.count > "supabase.co".count + 1
                    && normalizedHost.hasSuffix(".supabase.co")
            )
    }
}

/// Owns the client's only production URLSession and its DEBUG replacement seam.
/// Every mutable session reference is accessed under `sessionLock`.
final class PinnedNetworkTransport: @unchecked Sendable {
    private let sessionLock = NSLock()
    private var productionSession: URLSession?

    #if DEBUG
    private var storedOverridingSession: URLSession?

    var overridingSession: URLSession? {
        get { withSessionLock { storedOverridingSession } }
        set { withSessionLock { storedOverridingSession = newValue } }
    }
    #endif

    var isUsingOverridingSession: Bool {
        #if DEBUG
        withSessionLock { storedOverridingSession != nil }
        #else
        false
        #endif
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return configuration
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await activeSession.data(for: request)
    }

    func data(
        for request: URLRequest,
        delegate: URLSessionTaskDelegate
    ) async throws -> (Data, URLResponse) {
        try await activeSession.data(for: request, delegate: delegate)
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL
    ) async throws -> (Data, URLResponse) {
        try await activeSession.upload(for: request, fromFile: fileURL)
    }

    private var activeSession: URLSession {
        withSessionLock {
            #if DEBUG
            if let storedOverridingSession { return storedOverridingSession }
            #endif
            return resolveProductionSessionLocked()
        }
    }

    #if DEBUG
    var productionSessionIdentityForTesting: ObjectIdentifier {
        withSessionLock {
            ObjectIdentifier(resolveProductionSessionLocked())
        }
    }
    #endif

    private func resolveProductionSessionLocked() -> URLSession {
        if let productionSession { return productionSession }
        let session = URLSession(
            configuration: Self.makeConfiguration(),
            delegate: MerianTLSDelegate(),
            delegateQueue: nil
        )
        productionSession = session
        return session
    }

    private func withSessionLock<Value>(
        _ operation: () -> Value
    ) -> Value {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return operation()
    }
}

/// Validates the server certificate chain for `supabase.co` and its subdomains
/// against pinned SHA-256 hashes. Pinning is skipped in DEBUG builds to support
/// local proxies.
///
/// Rotation runbook:
/// 1. Before the leaf expires, obtain its DER SHA-256 base64 value with
///    `openssl s_client` and `openssl x509`.
/// 2. Add the new leaf alongside the existing leaf and intermediate values.
/// 3. Ship the app update before removing the expired leaf value.
/// 4. Replace the intermediate value only if Supabase changes certificate
///    authorities.
private final class MerianTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        #if DEBUG
        completionHandler(.performDefaultHandling, nil)
        #else
        guard MerianTLSCertificatePinPolicy.requiresPinning(
            host: challenge.protectionSpace.host
        ), challenge.protectionSpace.authenticationMethod
            == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            MerianLog.network.error(
                "TLS cert pinning could not evaluate trust for \(challenge.protectionSpace.host, privacy: .public)"
            )
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let systemTrustIsValid = SecTrustEvaluateWithError(serverTrust, nil)
        let chainHashes = (
            SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate]
        )?.map { certificate in
            let data = SecCertificateCopyData(certificate) as Data
            return Data(SHA256.hash(data: data)).base64EncodedString()
        }
        guard MerianTLSCertificatePinPolicy.accepts(
            systemTrustIsValid: systemTrustIsValid,
            certificateChainHashes: chainHashes
        ) else {
            MerianLog.network.error(
                "TLS trust or cert pinning failed for \(challenge.protectionSpace.host, privacy: .public)"
            )
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
        #endif
    }
}
