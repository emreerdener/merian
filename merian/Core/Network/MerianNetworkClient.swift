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

/// Validates the server certificate chain for *.supabase.co against pinned SHA-256 hashes.
///
/// The check walks the full certificate chain (leaf → intermediate → root).  A connection
/// is accepted if ANY certificate in the chain matches a pinned hash.  Pinning both the
/// leaf and the intermediate CA means the pin survives leaf rotation (every ~90 days for
/// Let's Encrypt certs) as long as the intermediate CA stays constant.
///
/// Pinning is skipped in DEBUG builds to allow MITM proxies (Charles, Proxyman).
///
/// --- Rotation runbook ---
/// 1. Before the leaf cert expires, run:
///      openssl s_client -connect qlarqavoqhkuwzmevrmf.supabase.co:443 </dev/null \
///        | openssl x509 -outform DER | openssl dgst -sha256 -binary | base64
/// 2. Add the new leaf hash alongside the existing one.
/// 3. Ship the app update.  Old builds keep working via the intermediate CA hash.
/// 4. After the old leaf has expired everywhere, remove the stale leaf hash.
///
/// Intermediate CA hash (changes much less often — update only if Supabase migrates CAs):
///   openssl s_client -connect qlarqavoqhkuwzmevrmf.supabase.co:443 -showcerts </dev/null \
///     | awk 'n==1{cert=cert"\n"$0} /BEGIN CERT/{n++} /END CERT/{if(n==2)exit}' \
///     | openssl x509 -outform DER | openssl dgst -sha256 -binary | base64
private final class MerianTLSDelegate: NSObject, URLSessionDelegate {
    // Leaf cert (expires ~90 days — rotate per runbook above).
    // Intermediate CA (Sectigo RSA Domain Validation Secure Server CA) — stable across leaf rotations.
    static let pinnedCertHashes: Set<String> = [
        "OYvM4tmVyyPLCSqTe1tYvZW0CKRfv4mre7EUA0eJrn0=", // leaf — qlarqavoqhkuwzmevrmf.supabase.co
        "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="  // intermediate CA (backup across leaf rotations)
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
              let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Walk the full chain so the intermediate CA hash works as a genuine fallback.
        let matched = certChain.contains { cert in
            let certData = SecCertificateCopyData(cert) as Data
            let hash = Data(SHA256.hash(data: certData)).base64EncodedString()
            return MerianTLSDelegate.pinnedCertHashes.contains(hash)
        }

        if matched {
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

    #if DEBUG
    /// Allows test suites to inject ephemeral configurations (like MockURLProtocol).
    var overridingSession: URLSession?
    #endif

    private var activeSession: URLSession {
        #if DEBUG
        if let overridingSession { return overridingSession }
        #endif
        return session
    }

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

    // MARK: - URL Construction

    /// Builds a URL for the given Edge Function path segment.
    /// Throws `MerianError.invalidURL` rather than crashing if `supabaseUrl` is misconfigured.
    private func endpointURL(_ function: String) throws -> URL {
        guard let url = URL(string: "\(supabaseUrl)/functions/v1/\(function)") else {
            throw MerianError.invalidURL
        }
        return url
    }

    private func makeExploreDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

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

        // In DEBUG, skip the live auth round-trip when a mock session is injected.
        // The Supabase SDK uses its own internal URLSession for token refresh which
        // MockURLProtocol cannot intercept, causing the test to hit the real network.
        #if DEBUG
        if overridingSession == nil {
            let authHeaders = try await SupabaseManager.shared.getValidAuthHeaders()
            for (key, val) in authHeaders {
                request.setValue(val, forHTTPHeaderField: key)
            }
        }
        #else
        let authHeaders = try await SupabaseManager.shared.getValidAuthHeaders()
        for (key, val) in authHeaders {
            request.setValue(val, forHTTPHeaderField: key)
        }
        #endif

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await activeSession.data(for: request)
        } catch let urlError as URLError {
            let transientCodes: Set<URLError.Code> = [
                .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet
            ]
            if transientCodes.contains(urlError.code) && !isRetry {
                MerianLog.network.debug("Transient network error \(urlError.code.rawValue, privacy: .public) — retrying in 2s.")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return try await performAuthenticatedRequest(url: url, method: method, body: body, timeoutInterval: timeoutInterval, isRetry: true)
            }
            throw urlError
        }

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

    /// Builds a fully-authenticated POST URLRequest for the /identify edge function.
    ///
    /// Returns the request without executing it so the caller can dispatch it as a
    /// background URLSession download task — enabling result delivery while backgrounded.
    func buildIdentifyRequest(
        r2ObjectKeys: [String],
        telemetry: CaptureTelemetry,
        clientScanId: String,
        description: String? = nil,
        observationContextJSON: String? = nil
    ) async throws -> URLRequest {
        let functionUrl = try endpointURL("identify")

        let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let userId = (authUserId ?? deviceId).lowercased()
        let deviceLocale = Locale.current.language.languageCode?.identifier ?? "en"
        // IANA timezone identifier (e.g. "America/Los_Angeles") — permission-free geographic
        // signal. Narrows the plausible species universe even when GPS is not authorized.
        let deviceTimeZone = TimeZone.current.identifier
        // ISO 3166-1 region code (e.g. "US", "DE") — complements the language-only locale.
        let deviceRegion = Locale.current.region?.identifier

        // For gallery photos, derive month and time-of-day from the image's own capture date
        // (populated from EXIF via PHAsset.creationDate) so Gemini receives the correct
        // season and light context for the photo rather than the current wall-clock values.
        // Falls back to now() for live captures and gallery photos with no EXIF date.
        let captureDate: Date = telemetry.timestamp.flatMap {
            DateUtilities.iso8601Formatter.date(from: $0)
        } ?? Date()
        let currentMonth = Calendar.current.component(.month, from: captureDate)

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timeOfDay = formatter.string(from: captureDate)

        let depthScaleText = telemetry.subjectDistanceInMeters.map { String(format: "%.1f meters", $0) }
        let capturedScanId = clientScanId
        let capturedTelemetry = telemetry
        let capturedDescription = description
        let capturedObservationContextJSON = observationContextJSON
        let bodyData = try await Task.detached(priority: .userInitiated) {
            let observationContextObject: [String: Any]? = capturedObservationContextJSON.flatMap { json in
                guard let data = json.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return obj
            }
            let isolatedPayload: [String: Any?] = [
                "r2ObjectKeys": r2ObjectKeys,
                "imageBase64s": nil,
                "user_id": userId,
                "mimeType": "image/webp",
                "depthScaleText": depthScaleText,
                "zoomFactor": capturedTelemetry.zoomFactor.map { Double($0) },
                "gpsLatitude": capturedTelemetry.gpsLatitude,
                "gpsLongitude": capturedTelemetry.gpsLongitude,
                "gpsElevation": capturedTelemetry.gpsElevation,
                "semanticLocation": capturedTelemetry.locationName,
                "weatherCondition": capturedTelemetry.weatherCondition,
                "weatherTemperatureF": capturedTelemetry.weatherTemperatureF,
                "deviceLocale": deviceLocale,
                "deviceTimeZone": deviceTimeZone,
                "deviceRegion": deviceRegion,
                "currentMonth": currentMonth,
                "timeOfDay": timeOfDay,
                "timestamp": capturedTelemetry.timestamp,
                "estimated_size_cm": capturedTelemetry.estimatedSizeCm,
                "client_scan_id": capturedScanId,
                "description": capturedDescription?.isEmpty == false ? capturedDescription : nil,
                "observation_context": observationContextObject
            ]
            return try JSONSerialization.data(withJSONObject: isolatedPayload.compactMapValues { $0 })
        }.value

        var request = URLRequest(url: functionUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let authHeaders = try await SupabaseManager.shared.getValidAuthHeaders()
        for (key, val) in authHeaders {
            request.setValue(val, forHTTPHeaderField: key)
        }

        return request
    }

    func analyzeSubject(r2ObjectKeys: [String]?, base64ImageDatas: [String]?, mimeType: String = "image/webp", telemetry: CaptureTelemetry, clientScanId: String? = nil, description: String? = nil, observationContextJSON: String? = nil) async throws -> Data {
        let functionUrl = try endpointURL("identify")

        let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let userId = (authUserId ?? deviceId).lowercased()
        let deviceLocale = Locale.current.language.languageCode?.identifier ?? "en"
        let deviceTimeZone = TimeZone.current.identifier
        let deviceRegion = Locale.current.region?.identifier

        let captureDate: Date = telemetry.timestamp.flatMap {
            DateUtilities.iso8601Formatter.date(from: $0)
        } ?? Date()
        let currentMonth = Calendar.current.component(.month, from: captureDate)

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timeOfDay = formatter.string(from: captureDate)

        let depthScaleText = telemetry.subjectDistanceInMeters.map { String(format: "%.1f meters", $0) }
        let capturedClientScanId = clientScanId
        let capturedDescription = description
        let capturedObservationContextJSON2 = observationContextJSON
        let bodyData = try await Task.detached(priority: .userInitiated) {
            let observationContextObject: [String: Any]? = capturedObservationContextJSON2.flatMap { json in
                guard let data = json.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return obj
            }
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
                "deviceTimeZone": deviceTimeZone,
                "deviceRegion": deviceRegion,
                "currentMonth": currentMonth,
                "timeOfDay": timeOfDay,
                "timestamp": telemetry.timestamp,
                "estimated_size_cm": telemetry.estimatedSizeCm,
                "client_scan_id": capturedClientScanId,
                // Combined path: non-nil when the user staged a describe description alongside images.
                // The edge function injects this as additional Gemini context beside the image parts.
                "description": capturedDescription?.isEmpty == false ? capturedDescription : nil,
                "observation_context": observationContextObject
            ]

            return try JSONSerialization.data(withJSONObject: isolatedPayload.compactMapValues { $0 })
        }.value
        // Inference calls can take up to 25–30s on gemini-2.5-pro with slow connections.
        // Use a 90s timeout matching timeoutIntervalForResource to prevent false timeouts.
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData, timeoutInterval: 90.0)
        return data
    }

    // MARK: - Multi-Modal Identification

    static func buildMultiModalRequestBody(
        r2ObjectKeys: [String] = [],
        base64ImageDatas: [String] = [],
        audioBase64s: [String] = [],
        observationContextsJSON: [String] = [],
        userId: String,
        mimeType: String = "image/webp",
        telemetry: CaptureTelemetry,
        deviceLocale: String,
        deviceTimeZone: String,
        deviceRegion: String?,
        currentMonth: Int,
        timeOfDay: String,
        depthScaleText: String?,
        clientScanId: String
    ) throws -> Data {
        let observationContextsObjects: [[String: Any]] = observationContextsJSON.compactMap { json in
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return obj
        }

        try validateMultiModalPayloadBudget(
            imageBase64s: base64ImageDatas,
            audioBase64s: audioBase64s
        )

        let isolatedPayload: [String: Any?] = [
            "r2ObjectKeys": r2ObjectKeys.isEmpty ? nil : r2ObjectKeys,
            "imageBase64s": base64ImageDatas.isEmpty ? nil : base64ImageDatas,
            "audioBase64s": audioBase64s.isEmpty ? nil : audioBase64s,
            "observation_contexts": observationContextsObjects.isEmpty ? nil : observationContextsObjects,
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
            "deviceTimeZone": deviceTimeZone,
            "deviceRegion": deviceRegion,
            "currentMonth": currentMonth,
            "timeOfDay": timeOfDay,
            "timestamp": telemetry.timestamp,
            "estimated_size_cm": telemetry.estimatedSizeCm,
            "client_scan_id": clientScanId
        ]
        return try JSONSerialization.data(withJSONObject: isolatedPayload.compactMapValues { $0 })
    }

    func buildMultiModalRequest(
        r2ObjectKeys: [String] = [],
        base64ImageDatas: [String] = [],
        mimeType: String = "image/webp",
        audioFilePaths: [String] = [],
        observationContextsJSON: [String] = [],
        telemetry: CaptureTelemetry,
        clientScanId: String
    ) async throws -> URLRequest {
        let functionUrl = try endpointURL("identify-multimodal")

        let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let userId = (authUserId ?? deviceId).lowercased()
        let deviceLocale = Locale.current.language.languageCode?.identifier ?? "en"
        let deviceTimeZone = TimeZone.current.identifier
        let deviceRegion = Locale.current.region?.identifier

        let captureDate: Date = telemetry.timestamp.flatMap {
            DateUtilities.iso8601Formatter.date(from: $0)
        } ?? Date()
        let currentMonth = Calendar.current.component(.month, from: captureDate)

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timeOfDay = formatter.string(from: captureDate)

        let depthScaleText = telemetry.subjectDistanceInMeters.map { String(format: "%.1f meters", $0) }
        let capturedClientScanId = clientScanId

        let capturedAudioPaths = audioFilePaths
        let capturedContextsJSON = observationContextsJSON
        let capturedTelemetry = telemetry
        let capturedMimeType = mimeType

        let bodyData = try await Task.detached(priority: .userInitiated) {
            var audioBase64s: [String] = []
            for path in capturedAudioPaths {
                let url = URL.documentsDirectory.appendingPathComponent(path)
                if let wavData = try? Data(contentsOf: url) {
                    audioBase64s.append(wavData.base64EncodedString())
                }
            }
            return try MerianNetworkClient.buildMultiModalRequestBody(
                r2ObjectKeys: r2ObjectKeys,
                base64ImageDatas: base64ImageDatas,
                audioBase64s: audioBase64s,
                observationContextsJSON: capturedContextsJSON,
                userId: userId,
                mimeType: capturedMimeType,
                telemetry: capturedTelemetry,
                deviceLocale: deviceLocale,
                deviceTimeZone: deviceTimeZone,
                deviceRegion: deviceRegion,
                currentMonth: currentMonth,
                timeOfDay: timeOfDay,
                depthScaleText: depthScaleText,
                clientScanId: capturedClientScanId
            )
        }.value

        var request = URLRequest(url: functionUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let authHeaders = try await SupabaseManager.shared.getValidAuthHeaders()
        for (key, val) in authHeaders {
            request.setValue(val, forHTTPHeaderField: key)
        }

        return request
    }

    /// Validates that the combined base64 image + audio payload fits the V8 isolator memory budget.
    /// Exposed as `internal` so test targets can exercise budget boundaries without auth dependencies.
    static func validateMultiModalPayloadBudget(imageBase64s: [String], audioBase64s: [String]) throws {
        let totalSize = (imageBase64s + audioBase64s).reduce(0) { $0 + $1.utf8.count }
        if totalSize > 3_600_000 {
            throw MerianError.payloadTooLarge
        }
    }

    func identifyMultiModal(
        r2ObjectKeys: [String] = [],
        base64ImageDatas: [String] = [],
        mimeType: String = "image/webp",
        audioFilePaths: [String] = [],
        observationContextsJSON: [String] = [],
        telemetry: CaptureTelemetry,
        clientScanId: String? = nil
    ) async throws -> Data {
        let request = try await buildMultiModalRequest(
            r2ObjectKeys: r2ObjectKeys,
            base64ImageDatas: base64ImageDatas,
            mimeType: mimeType,
            audioFilePaths: audioFilePaths,
            observationContextsJSON: observationContextsJSON,
            telemetry: telemetry,
            clientScanId: clientScanId ?? UUID().uuidString.lowercased()
        )

        guard let url = request.url, let bodyData = request.httpBody else {
            throw MerianError.invalidURL
        }

        let (data, _) = try await performAuthenticatedRequest(url: url, method: "POST", body: bodyData, timeoutInterval: 90.0)
        return data
    }

    func fetchEnrichment(
        scanId: String,
        scientificName: String,
        confidenceScore: Double,
        inferenceTier: String,
        scope: String
    ) async throws -> EnrichScanResponse {
        let functionUrl = try endpointURL("enrich-scan")
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
        let functionUrl = try endpointURL("generate-upload-urls")
        let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let userId = (authUserId ?? deviceId).lowercased()
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
        let (responseData, response) = try await activeSession.data(for: request)
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

    // MARK: - Outbox Confirmation

    /// Asks the server whether `scanId` exists in `public.scans` for the current user.
    /// Returns `"found"` or `"not_found"`. Called from `OfflineQueueManager.handleInferenceRetry`
    /// before resetting a scan to `.staged`, closing the gap where inference succeeded server-side
    /// but the background download task never delivered the response.
    func checkScanStatus(scanId: String) async throws -> String {
        let functionUrl = try endpointURL("check-scan-status")
        let bodyData = try JSONSerialization.data(withJSONObject: ["scan_id": scanId])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        return decoded["status"] ?? "not_found"
    }

    // MARK: - Data Mutation

    func deleteScan(scanId: String) async throws {
        let functionUrl = try endpointURL("delete-scan")
        let bodyData = try JSONSerialization.data(withJSONObject: ["scanId": scanId])
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        MerianLog.network.debug("Scan deleted: \(scanId, privacy: .private)")
    }

    func safeDeleteAccount() async throws {
        let functionUrl = try endpointURL("safe-delete")
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST")
        MerianLog.network.debug("Account deletion complete.")
    }

    // MARK: - Darwin Core Export

    /// Queues a DwC-A export job. This endpoint inserts a job into the Postgres
    /// export_jobs queue, which triggers a background webhook to process the zip
    /// and email the user the final download link via Resend.
    func requestDwcAExport(scope: String = "personal") async throws {
        let functionUrl = try endpointURL("request-export-dwca")
        // includePreciseCoordinates: true — intentional for personal exports. The requesting
        // user is downloading their own data, so full-resolution GPS coordinates are appropriate.
        // For "global" scope exports, the server scrubs coordinates for all rows except the
        // requesting user's own records, regardless of this flag.
        let payload: [String: Any] = ["exportScope": scope, "includePreciseCoordinates": true]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        
        // This is a fast API call that just inserts a row and returns 200 OK.
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData, timeoutInterval: 15.0)
    }

    // MARK: - Explore

    func getExploreFeed(
        limit: Int = 20,
        beforeSharedAt: String? = nil,
        beforePostId: String? = nil
    ) async throws -> [ExplorePost] {
        let functionUrl = try endpointURL("get-explore-feed")
        var payload: [String: Any] = ["limit": limit]

        if let beforeSharedAt, let beforePostId {
            payload["before_shared_at"] = beforeSharedAt
            payload["before_post_id"] = beforePostId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreFeedResponse.self, from: data).data
    }

    func getExploreMapPoints(
        northLatitude: Double,
        southLatitude: Double,
        eastLongitude: Double,
        westLongitude: Double,
        zoomLevel: Double,
        limit: Int = 500
    ) async throws -> ExploreMapPointsResponse {
        let functionUrl = try endpointURL("get-explore-map-points")
        let payload: [String: Any] = [
            "north_latitude": northLatitude,
            "south_latitude": southLatitude,
            "east_longitude": eastLongitude,
            "west_longitude": westLongitude,
            "zoom_level": zoomLevel,
            "limit": limit
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreMapPointsResponse.self, from: data)
    }

    func getExploreComments(
        postId: String,
        limit: Int = 100,
        afterCreatedAt: String? = nil,
        afterCommentId: String? = nil
    ) async throws -> [ExploreComment] {
        let functionUrl = try endpointURL("get-explore-comments")
        var payload: [String: Any] = [
            "post_id": postId,
            "limit": limit
        ]

        if let afterCreatedAt, let afterCommentId {
            payload["after_created_at"] = afterCreatedAt
            payload["after_comment_id"] = afterCommentId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreCommentsResponse.self, from: data).data
    }

    func getExplorePost(postId: String) async throws -> ExplorePost {
        let functionUrl = try endpointURL("get-explore-post")
        let bodyData = try JSONSerialization.data(withJSONObject: ["post_id": postId])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExplorePostResponse.self, from: data).data
    }

    func getExplorePostDetail(postId: String) async throws -> ExplorePostDetail {
        let functionUrl = try endpointURL("get-explore-post-detail")
        let bodyData = try JSONSerialization.data(withJSONObject: ["post_id": postId])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExplorePostDetailResponse.self, from: data).data
    }

    func getExploreShareState(scanId: String) async throws -> ExploreScanShareState {
        let functionUrl = try endpointURL("get-scan-explore-share-state")
        let bodyData = try JSONSerialization.data(withJSONObject: ["scan_id": scanId])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreScanShareStateResponse.self, from: data).data
    }

    func getExploreNotifications(
        limit: Int = 50,
        beforeUpdatedAt: String? = nil,
        beforeNotificationId: String? = nil
    ) async throws -> [ExploreNotification] {
        let functionUrl = try endpointURL("get-explore-notifications")
        var payload: [String: Any] = ["limit": limit]

        if let beforeUpdatedAt, let beforeNotificationId {
            payload["before_updated_at"] = beforeUpdatedAt
            payload["before_notification_id"] = beforeNotificationId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreNotificationsResponse.self, from: data).data
    }

    func getUnreadExploreNotificationCount() async throws -> Int {
        let functionUrl = try endpointURL("get-explore-unread-notification-count")
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: Data("{}".utf8))
        return try makeExploreDecoder().decode(ExploreUnreadNotificationCountResponse.self, from: data).unreadCount
    }

    func markExploreNotificationsRead() async throws -> Int {
        let functionUrl = try endpointURL("mark-explore-notifications-read")
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: Data("{}".utf8))
        return try makeExploreDecoder().decode(ExploreMarkNotificationsReadResponse.self, from: data).markedCount
    }

    func registerPushDevice(deviceToken: String, environment: String, exploreEnabled: Bool) async throws {
        let functionUrl = try endpointURL("register-push-device")
        let payload: [String: Any] = [
            "device_token": deviceToken,
            "platform": "ios",
            "environment": environment,
            "explore_enabled": exploreEnabled
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func shareScanToExplore(scanId: String, restoredObjectKeys: [String]? = nil) async throws -> ExploreShareResponse {
        let functionUrl = try endpointURL("share-scan-to-explore")
        var payload: [String: Any] = ["scan_id": scanId]
        if let restoredObjectKeys, !restoredObjectKeys.isEmpty {
            payload["restored_object_keys"] = restoredObjectKeys
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreShareResponse.self, from: data)
    }

    func shareScanToExplore(scan: LocalScanRecord) async throws -> ExploreShareResponse {
        do {
            return try await shareScanToExplore(scanId: scan.id)
        } catch {
            guard shouldAttemptExploreMediaRestore(after: error) else {
                throw error
            }

            let restoredObjectKeys = try await restoreExploreMediaObjectKeys(for: scan)
            guard !restoredObjectKeys.isEmpty else {
                throw error
            }

            return try await shareScanToExplore(
                scanId: scan.id,
                restoredObjectKeys: restoredObjectKeys
            )
        }
    }

    func unshareExplorePost(postId: String) async throws {
        let functionUrl = try endpointURL("unshare-explore-post")
        let bodyData = try JSONSerialization.data(withJSONObject: ["post_id": postId])
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func setExplorePostLike(postId: String, liked: Bool) async throws -> ExploreLikeResponse {
        let functionUrl = try endpointURL("set-explore-post-like")
        let payload: [String: Any] = [
            "post_id": postId,
            "liked": liked
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreLikeResponse.self, from: data)
    }

    func createExploreComment(postId: String, body: String) async throws -> ExploreCreateCommentResponse {
        let functionUrl = try endpointURL("create-explore-comment")
        let payload: [String: Any] = [
            "post_id": postId,
            "body": body
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreCreateCommentResponse.self, from: data)
    }

    func deleteExploreComment(commentId: String) async throws -> ExploreDeleteCommentResponse {
        let functionUrl = try endpointURL("delete-explore-comment")
        let bodyData = try JSONSerialization.data(withJSONObject: ["comment_id": commentId])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreDeleteCommentResponse.self, from: data)
    }

    func reportExploreComment(
        commentId: String,
        reason: String = "Inappropriate content",
        details: String = "Reported from Explore comments"
    ) async throws {
        let functionUrl = try endpointURL("report-explore-comment")
        let payload: [String: Any] = [
            "comment_id": commentId,
            "reason": reason,
            "details": details
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    // MARK: - Moderation

    func submitFlagIssue(scanId: String, flagReason: String, userSuggestion: String, userId: String) async throws {
        let functionUrl = try endpointURL("flag-issue")
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
        let functionUrl = try endpointURL("block-user")
        let bodyData = try JSONSerialization.data(withJSONObject: ["blocked_id": targetUserId])
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    private func shouldAttemptExploreMediaRestore(after error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, message) = error,
              statusCode == 409 else {
            return false
        }

        return message.contains("This scan no longer has shareable image media.")
    }

    private func restoreExploreMediaObjectKeys(for scan: LocalScanRecord) async throws -> [String] {
        let localImagePaths = resolveRestorableImagePaths(for: scan)
        guard !localImagePaths.isEmpty else { return [] }

        let fileNames = localImagePaths.enumerated().map { index, path in
            let ext = URL(fileURLWithPath: path).pathExtension
            let normalizedExt = ext.isEmpty ? "webp" : ext
            return "\(scan.id)_explore_restore_\(index).\(normalizedExt)"
        }

        let uploadUrls = try await generateUploadURLs(fileNames: fileNames)
        guard uploadUrls.count == localImagePaths.count else {
            throw MerianError.invalidResponse
        }

        for (path, uploadUrl) in zip(localImagePaths, uploadUrls) {
            let fileURL = URL.documentsDirectory.appendingPathComponent(path)
            let data = try Data(contentsOf: fileURL)
            try await uploadToR2(
                url: uploadUrl.signedUrl,
                data: data,
                mimeType: exploreRestoreMimeType(for: data)
            )
        }

        return uploadUrls.map(\.objectKey)
    }

    private func resolveRestorableImagePaths(for scan: LocalScanRecord) -> [String] {
        var candidatePaths = scan.capturedMediaJSON.map(MediaJSONParser.imagePaths(jsonString:)) ?? []

        if candidatePaths.isEmpty, let coverImagePath = scan.coverImagePath {
            candidatePaths.append(coverImagePath)
        }

        var resolved: [String] = []
        for path in candidatePaths where !path.starts(with: "http") {
            let fileURL = URL.documentsDirectory.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: fileURL.path), !resolved.contains(path) {
                resolved.append(path)
            }
        }

        return resolved
    }

    private func exploreRestoreMimeType(for data: Data) -> String {
        guard data.count >= 3 else { return "image/webp" }
        let prefix = [UInt8](data.prefix(3))
        return (prefix[0] == 0xFF && prefix[1] == 0xD8 && prefix[2] == 0xFF)
            ? "image/jpeg"
            : "image/webp"
    }
}
