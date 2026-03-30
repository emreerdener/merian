import CryptoKit
import Foundation
import os

// Using MerianError from Core/Utilities.

// MARK: - Pre-Signed URL DTOs

struct PreSignedURLResponse: Codable {
    let urls: [PreSignedURL]
}

struct PreSignedURL: Codable {
    let fileName: String
    let signedUrl: String
    let objectKey: String
}

// MARK: - TLS Certificate Pinning

/// Validates the server certificate for *.supabase.co against pinned SHA-256 hashes.
///
/// Pinning is skipped in DEBUG builds to allow MITM proxies (Charles, Proxyman).
/// When `pinnedCertHashes` is empty (initial state), default ATS validation applies.
///
/// To populate the hashes, run:
///   openssl s_client -connect qlarqavoqhkuwzmevrmf.supabase.co:443 </dev/null \
///     | openssl x509 -outform DER \
///     | openssl dgst -sha256 -binary \
///     | base64
///
/// Include a primary hash and a backup hash to allow zero-downtime cert rotation.
private final class MerianTLSDelegate: NSObject, URLSessionDelegate {
    static let pinnedCertHashes: Set<String> = [
        // "insert_primary_cert_sha256_base64_here",
        // "insert_backup_cert_sha256_base64_here",
    ]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        #if DEBUG
        // Skip pinning in debug builds to allow MITM proxies (Charles, Proxyman).
        completionHandler(.performDefaultHandling, nil)
        #else
        // Only pin the Supabase domain; let R2 and other hosts use default ATS validation.
        guard challenge.protectionSpace.host.hasSuffix("supabase.co"),
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              !MerianTLSDelegate.pinnedCertHashes.isEmpty,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leafCert = certChain.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let certData = SecCertificateCopyData(leafCert) as Data
        let hash = Data(SHA256.hash(data: certData)).base64EncodedString()

        if MerianTLSDelegate.pinnedCertHashes.contains(hash) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            MerianLog.network.error("TLS cert pinning failed for \(challenge.protectionSpace.host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
        #endif
    }
}

// MARK: - Merian Network Client

/// Authenticated HTTP client for all Supabase Edge Function and R2 storage calls.
final class MerianNetworkClient {

    // MARK: - Singleton Architecture
    static let shared = MerianNetworkClient()

    private let supabaseUrl = MerianEnvironment.supabaseUrl
    private let supabaseAnonKey = MerianEnvironment.supabaseAnonKey

    // MARK: - URLSession

    /// Dedicated session with sensible timeouts, connection limits, and TLS pinning.
    /// Replaces `URLSession.shared` to avoid inheriting the system-wide shared configuration.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30       // TCP + TLS + first-byte wait
        config.timeoutIntervalForResource = 90      // Hard cap; Gemini can be slow on bad connections
        config.httpMaximumConnectionsPerHost = 6
        config.httpShouldSetCookies = false         // Auth uses headers, not cookies
        config.urlCache = nil                       // Edge responses are never cacheable
        return URLSession(configuration: config, delegate: MerianTLSDelegate(), delegateQueue: nil)
    }()

    // MARK: - Authenticated Request Core

    private func performAuthenticatedRequest(
        url: URL,
        method: String,
        body: Data? = nil,
        timeoutInterval: TimeInterval = 30.0,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutInterval)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = body
        }

        let authHeaders = try await SupabaseManager.shared.getValidAuthHeaders()
        for (key, val) in authHeaders {
            request.setValue(val, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MerianError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errString = String(data: data, encoding: .utf8) ?? "Unknown"
            MerianLog.network.debug("Edge function failed [\(httpResponse.statusCode, privacy: .public)]: \(errString, privacy: .public)")

            // A 401 on a guest session indicates a zombie token — purge and retry once.
            if httpResponse.statusCode == 401 && !isRetry {
                let hasAuthenticatedOAuth = KeychainManager.shared.bool(forKey: "Merian_HasAuthenticatedOAuth")
                if hasAuthenticatedOAuth {
                    // OAuth user whose token expired — surface the 401 so the UI can prompt re-auth.
                    throw MerianError.invalidResponse
                }

                let isGuest = await SupabaseManager.shared.isGuestUser
                if isGuest {
                    MerianLog.network.debug("Zombie session detected — regenerating ghost session.")
                    await SupabaseManager.shared.signOut()
                    await SupabaseManager.shared.initializeGhostSession()

                    // Allow ~1.5s for the API gateway to recognize the new token signature.
                    try? await Task.sleep(nanoseconds: 1_500_000_000)

                    return try await performAuthenticatedRequest(url: url, method: method, body: body, timeoutInterval: timeoutInterval, isRetry: true)
                } else {
                    throw MerianError.invalidResponse
                }
            }

            // 5xx — transient server/Edge Function error. Retry once after a brief pause
            // so a cold-start or momentary Deno isolate failure doesn't surface as a permanent
            // user-facing "Network Timeout". Only safe on idempotent callers (inference, reads).
            if httpResponse.statusCode >= 500 && !isRetry {
                MerianLog.network.debug("Server error \(httpResponse.statusCode, privacy: .public) — retrying in 2s.")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return try await performAuthenticatedRequest(url: url, method: method, body: body, timeoutInterval: timeoutInterval, isRetry: true)
            }

            throw MerianError.httpError(statusCode: httpResponse.statusCode, message: errString)
        }

        return (data, httpResponse)
    }

    // MARK: - Inference

    func analyzeSubject(r2ObjectKeys: [String]?, base64ImageDatas: [String]?, mimeType: String = "image/webp", telemetry: CaptureTelemetry) async throws -> Data {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/identify")!

        let userId = await MainActor.run { (SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId).lowercased() }
        let deviceLocale = Locale.current.language.languageCode?.identifier ?? "en"
        let currentMonth = Calendar.current.component(.month, from: Date())

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timeOfDay = formatter.string(from: Date())

        let depthScaleText = telemetry.subjectDistanceInMeters.map { String(format: "%.1f meters", $0) }
        let bodyData = try await Task.detached(priority: .userInitiated) {
            let isolatedPayload: [String: Any?] = [
                "r2ObjectKeys": r2ObjectKeys,
                "imageBase64s": base64ImageDatas,
                "user_id": userId,
                "mimeType": mimeType,
                "depthScaleText": depthScaleText,
                "zoomFactor": telemetry.zoomFactor.map { Double($0) },
                "gpsLatitude": telemetry.gpsLatitude,
                "gpsLongitude": telemetry.gpsLongitude,
                "gpsElevation": telemetry.gpsElevation,
                "semanticLocation": telemetry.locationName,
                "weatherCondition": telemetry.weatherCondition,
                "weatherTemperatureF": telemetry.weatherTemperatureF,
                "deviceLocale": deviceLocale,
                "currentMonth": currentMonth,
                "timeOfDay": timeOfDay,
                "timestamp": telemetry.timestamp,
                "estimated_size_cm": telemetry.estimatedSizeCm
            ]
            
            return try JSONSerialization.data(withJSONObject: isolatedPayload.compactMapValues { $0 })
        }.value
        // Inference calls can take up to 25–30s on gemini-2.5-pro with slow connections.
        // Use a 90s timeout matching timeoutIntervalForResource to prevent false timeouts.
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData, timeoutInterval: 90.0)
        return data
    }

    func fetchEnrichment(
        scanId: String,
        scientificName: String,
        confidenceScore: Double,
        inferenceTier: String,
        scope: String
    ) async throws -> EnrichScanResponse {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/enrich-scan")!
        let payload: [String: Any] = [
            "scan_id": scanId,
            "scientific_name": scientificName,
            "confidence_score": confidenceScore,
            "inference_tier": inferenceTier,
            "scope": scope
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try JSONDecoder().decode(EnrichScanResponse.self, from: data)
    }

    // MARK: - R2 Storage

    func generateUploadURLs(fileNames: [String]) async throws -> [PreSignedURL] {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/generate-upload-urls")!
        let userId = await MainActor.run { (SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId).lowercased() }
        let payload: [String: Any] = ["fileNames": fileNames, "user_id": userId]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try JSONDecoder().decode(PreSignedURLResponse.self, from: data).urls
    }

    func uploadToR2(url: String, data: Data, mimeType: String = "image/webp") async throws {
        guard let signedUrl = URL(string: url) else { throw MerianError.invalidURL }

        var request = URLRequest(url: signedUrl)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let uploadStart = CFAbsoluteTimeGetCurrent()
        let (responseData, response) = try await session.data(for: request)
        MerianLog.network.debug("R2 upload completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - uploadStart), privacy: .public)s.")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MerianError.uploadFailed
        }

        if httpResponse.statusCode != 200 {
            let errString = String(data: responseData, encoding: .utf8) ?? "Unknown"
            MerianLog.network.debug("R2 upload failed [\(httpResponse.statusCode, privacy: .public)]: \(errString, privacy: .public)")
            throw MerianError.uploadFailed
        }
    }

    // MARK: - Data Mutation

    func deleteScan(scanId: String) async throws {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/delete-scan")!
        let bodyData = try JSONSerialization.data(withJSONObject: ["scanId": scanId])
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        MerianLog.network.debug("Scan deleted: \(scanId, privacy: .private)")
    }

    func safeDeleteAccount() async throws {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/safe-delete")!
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST")
        MerianLog.network.debug("Account deletion complete.")
    }

    // MARK: - Darwin Core Export

    /// Queues a DwC-A export job. This endpoint inserts a job into the Postgres
    /// export_jobs queue, which triggers a background webhook to process the zip
    /// and email the user the final download link via Resend.
    func requestDwcAExport(scope: String = "user") async throws {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/request-export-dwca")!
        let payload: [String: Any] = ["exportScope": scope, "includePreciseCoordinates": true]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        
        // This is a fast API call that just inserts a row and returns 200 OK.
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData, timeoutInterval: 15.0)
    }

    // MARK: - Moderation

    func submitFlagIssue(scanId: String, flagReason: String, userSuggestion: String, userId: String) async throws {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/flag-issue")!
        let payload: [String: Any] = [
            "scanId": scanId,
            "userId": userId,
            "flagReason": flagReason,
            "userSuggestion": userSuggestion
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func blockUser(targetUserId: String) async throws {
        let functionUrl = URL(string: "\(supabaseUrl)/functions/v1/block-user")!
        let bodyData = try JSONSerialization.data(withJSONObject: ["blocked_id": targetUserId])
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }
}
