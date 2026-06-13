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

private struct UploadURLRequestBody: Encodable {
    let files: [StagingUploadFile]
    let userId: String

    private enum CodingKeys: String, CodingKey {
        case files
        case userId = "user_id"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct ExploreShareMediaSnapshot {
    let scanId: String
    let imagePaths: [String]
    let coverImagePath: String?

    init(scan: LocalScanRecord) {
        self.scanId = scan.id
        self.imagePaths = scan.capturedMediaSnapshot.imagePaths
        self.coverImagePath = scan.coverImagePath
    }
}

private struct EdgeErrorPayload: Decodable {
    let code: String?
    let error: String?
}

private struct InferenceRequestContext: Sendable {
    let userId: String
    let deviceLocale: String
    let deviceTimeZone: String
    let deviceRegion: String?
    let currentMonth: Int
    let timeOfDay: String
    let depthScaleText: String?
    let defaultGeoprivacy: String
}

private enum InferencePayloadBuilder {
    static func makeContext(
        userId: String,
        telemetry: CaptureTelemetry,
        defaultGeoprivacy: String
    ) -> InferenceRequestContext {
        let captureDate: Date = telemetry.timestamp.flatMap {
            DateUtilities.iso8601Formatter.date(from: $0)
        } ?? Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return InferenceRequestContext(
            userId: userId.lowercased(),
            deviceLocale: Locale.current.language.languageCode?.identifier ?? "en",
            deviceTimeZone: TimeZone.current.identifier,
            deviceRegion: Locale.current.region?.identifier,
            currentMonth: Calendar.current.component(.month, from: captureDate),
            timeOfDay: formatter.string(from: captureDate),
            depthScaleText: telemetry.subjectDistanceInMeters.map { String(format: "%.1f meters", $0) },
            defaultGeoprivacy: normalizedGeoprivacy(defaultGeoprivacy)
        )
    }

    static func identifyBody(
        r2ObjectKeys: [String]?,
        imageBase64s: [String]?,
        mimeType: String,
        telemetry: CaptureTelemetry,
        context: InferenceRequestContext,
        clientScanId: String?,
        description: String?,
        observationContextJSON: String?
    ) throws -> Data {
        try MerianNetworkClient.validateMultiModalPayloadBudget(
            imageBase64s: imageBase64s ?? [],
            audioBase64s: []
        )

        var payload = telemetryPayloadFields(
            telemetry: telemetry,
            context: context,
            clientScanId: clientScanId
        )
        setIfPresent(r2ObjectKeys, forKey: "r2ObjectKeys", in: &payload)
        setIfPresent(imageBase64s, forKey: "imageBase64s", in: &payload)
        payload["mimeType"] = mimeType

        if let description, !description.isEmpty {
            payload["description"] = description
        }

        setIfPresent(
            observationContextObject(from: observationContextJSON),
            forKey: "observation_context",
            in: &payload
        )

        return try jsonData(from: payload)
    }

    static func multimodalBody(
        r2ObjectKeys: [String],
        audioR2ObjectKeys: [String],
        imageBase64s: [String],
        audioBase64s: [String],
        observationContextsJSON: [String],
        mimeType: String,
        telemetry: CaptureTelemetry,
        context: InferenceRequestContext,
        clientScanId: String
    ) throws -> Data {
        try MerianNetworkClient.validateMultiModalPayloadBudget(
            imageBase64s: imageBase64s,
            audioBase64s: audioBase64s
        )

        var payload = telemetryPayloadFields(
            telemetry: telemetry,
            context: context,
            clientScanId: clientScanId
        )
        if !r2ObjectKeys.isEmpty {
            payload["r2ObjectKeys"] = r2ObjectKeys
        }
        if !audioR2ObjectKeys.isEmpty {
            payload["audioR2ObjectKeys"] = audioR2ObjectKeys
        }
        if !imageBase64s.isEmpty {
            payload["imageBase64s"] = imageBase64s
        }
        if !audioBase64s.isEmpty {
            payload["audioBase64s"] = audioBase64s
        }

        let observationContexts = observationContextObjects(from: observationContextsJSON)
        if !observationContexts.isEmpty {
            payload["observation_contexts"] = observationContexts
        }
        payload["mimeType"] = mimeType

        return try jsonData(from: payload)
    }

    private static func telemetryPayloadFields(
        telemetry: CaptureTelemetry,
        context: InferenceRequestContext,
        clientScanId: String?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "user_id": context.userId,
            "deviceLocale": context.deviceLocale,
            "deviceTimeZone": context.deviceTimeZone,
            "currentMonth": context.currentMonth,
            "timeOfDay": context.timeOfDay
        ]

        setIfPresent(context.depthScaleText, forKey: "depthScaleText", in: &payload)
        setIfPresent(telemetry.zoomFactor.map { Double($0) }, forKey: "zoomFactor", in: &payload)
        setIfPresent(telemetry.gpsLatitude, forKey: "gpsLatitude", in: &payload)
        setIfPresent(telemetry.gpsLongitude, forKey: "gpsLongitude", in: &payload)
        setIfPresent(telemetry.gpsElevation, forKey: "gpsElevation", in: &payload)
        let publicLocationLabel = context.defaultGeoprivacy == "private"
            ? nil
            : ExploreLocationPrivacy.displayLabel(from: telemetry.locationName)
        setIfPresent(telemetry.locationName, forKey: "semanticLocation", in: &payload)
        setIfPresent(publicLocationLabel, forKey: "publicLocationLabel", in: &payload)
        setIfPresent(context.defaultGeoprivacy, forKey: "geoprivacy", in: &payload)
        setIfPresent(telemetry.weatherCondition, forKey: "weatherCondition", in: &payload)
        setIfPresent(telemetry.weatherTemperatureF, forKey: "weatherTemperatureF", in: &payload)
        setIfPresent(context.deviceRegion, forKey: "deviceRegion", in: &payload)
        setIfPresent(telemetry.timestamp, forKey: "timestamp", in: &payload)
        setIfPresent(telemetry.estimatedSizeCm, forKey: "estimated_size_cm", in: &payload)
        setIfPresent(clientScanId, forKey: "client_scan_id", in: &payload)

        return payload
    }

    private static func observationContextObject(from json: String?) -> [String: Any]? {
        json.flatMap { rawJSON in
            guard let data = rawJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    static func normalizedGeoprivacy(_ value: String) -> String {
        switch value {
        case "private", "obscured":
            return value
        default:
            return "open"
        }
    }

    private static func observationContextObjects(from jsons: [String]) -> [[String: Any]] {
        jsons.compactMap { json in
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    private static func setIfPresent<T>(_ value: T?, forKey key: String, in payload: inout [String: Any]) {
        if let value {
            payload[key] = value
        }
    }

    private static func jsonData(from payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: payload)
    }
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
    private let speciesDictionaryCacheTTL: TimeInterval = 10 * 60
    private let speciesDictionaryCacheLimit = 64
    private let speciesDictionaryCacheLock = NSLock()
    private var speciesDictionaryCache: [String: SpeciesDictionaryCacheEntry] = [:]
    private let speciesObservationStatsCacheTTL: TimeInterval = 5 * 60
    private let speciesObservationStatsCacheLimit = 64
    private let speciesObservationStatsCacheLock = NSLock()
    private var speciesObservationStatsCache: [String: SpeciesObservationStatsCacheEntry] = [:]

    private struct SpeciesDictionaryCacheEntry {
        let value: SpeciesDictionaryEntry
        let storedAt: Date
    }

    private struct SpeciesObservationStatsCacheEntry {
        let value: SpeciesObservationStatsEntry
        let storedAt: Date
    }

    // MARK: - URLSession

    #if DEBUG
    /// Allows test suites to inject ephemeral configurations (like MockURLProtocol).
    var overridingSession: URLSession? {
        didSet { resetSpeciesDictionaryCacheForTesting() }
    }
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
        config.urlCache = nil                       // Keep URLCache off; public dictionary pages use scoped memoization.
        return URLSession(configuration: config, delegate: MerianTLSDelegate(), delegateQueue: nil)
    }()

    // MARK: - URL Construction

    /// Builds a URL for the given Edge Function path segment.
    /// Throws `MerianError.invalidURL` rather than crashing if `supabaseUrl` is misconfigured.
    private func endpointURL(_ function: String) throws -> URL {
        guard MerianEnvironment.isSupabaseConfigured else {
            MerianLog.network.error("Network request blocked because Supabase environment configuration is incomplete.")
            throw MerianError.invalidURL
        }
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

    private static func isMissingAuthSessionError(responseData: Data, fallbackMessage: String) -> Bool {
        if let payload = try? JSONDecoder().decode(EdgeErrorPayload.self, from: responseData) {
            if payload.code == "auth_session_missing" {
                return true
            }

            if payload.error?.localizedCaseInsensitiveContains("Auth session missing") == true {
                return true
            }
        }

        return fallbackMessage.localizedCaseInsensitiveContains("Auth session missing")
    }

    #if DEBUG
    func resetSpeciesDictionaryCacheForTesting() {
        speciesDictionaryCacheLock.lock()
        speciesDictionaryCache.removeAll()
        speciesDictionaryCacheLock.unlock()

        speciesObservationStatsCacheLock.lock()
        speciesObservationStatsCache.removeAll()
        speciesObservationStatsCacheLock.unlock()
    }
    #endif

    private func makeInferenceRequestContext(telemetry: CaptureTelemetry) async -> InferenceRequestContext {
        let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let (deviceId, defaultGeoprivacy) = await MainActor.run {
            (
                DeviceIdentityManager.shared.deviceId,
                AppDIContainer.shared.profileViewModel.defaultGeoprivacy
            )
        }
        return InferencePayloadBuilder.makeContext(
            userId: authUserId ?? deviceId,
            telemetry: telemetry,
            defaultGeoprivacy: defaultGeoprivacy
        )
    }

    private func makeAuthenticatedJSONRequest(
        url: URL,
        bodyData: Data,
        timeoutInterval: TimeInterval = 90.0
    ) async throws -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let authHeaders = try await SupabaseManager.shared.getValidAuthHeaders()
        for (key, val) in authHeaders {
            request.setValue(val, forHTTPHeaderField: key)
        }

        return request
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

            if httpResponse.statusCode == 401 && !isRetry {
                if Self.isMissingAuthSessionError(responseData: data, fallbackMessage: errString) {
                    if await SupabaseManager.shared.refreshActiveSessionForRetry() {
                        return try await performAuthenticatedRequest(url: url, method: method, body: body, timeoutInterval: timeoutInterval, isRetry: true)
                    }

                    let isGuest = await SupabaseManager.shared.isGuestUser
                    if isGuest {
                        MerianLog.network.debug("Missing anonymous auth session detected — regenerating ghost session.")
                        if await SupabaseManager.shared.resetGhostSessionForRetry() {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            return try await performAuthenticatedRequest(url: url, method: method, body: body, timeoutInterval: timeoutInterval, isRetry: true)
                        }
                    }

                    await SupabaseManager.shared.clearLocalSessionAfterAuthFailure()
                    throw MerianError.invalidResponse
                }

                let hasAuthenticatedOAuth = KeychainManager.shared.bool(forKey: KeychainKeys.hasAuthenticatedOAuth)
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

    private func performPublicGETRequest(
        url: URL,
        timeoutInterval: TimeInterval = 20.0,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await activeSession.data(for: request)
        } catch let urlError as URLError {
            let transientCodes: Set<URLError.Code> = [
                .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet
            ]
            if transientCodes.contains(urlError.code) && !isRetry {
                MerianLog.network.debug("Transient public network error \(urlError.code.rawValue, privacy: .public) — retrying in 2s.")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return try await performPublicGETRequest(url: url, timeoutInterval: timeoutInterval, isRetry: true)
            }
            throw urlError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MerianError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errString = String(data: data, encoding: .utf8) ?? "Unknown"
            MerianLog.network.debug("Public edge function failed [\(httpResponse.statusCode, privacy: .public)]: \(errString, privacy: .public)")

            if httpResponse.statusCode >= 500 && !isRetry {
                MerianLog.network.debug("Public server error \(httpResponse.statusCode, privacy: .public) — retrying in 2s.")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return try await performPublicGETRequest(url: url, timeoutInterval: timeoutInterval, isRetry: true)
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
        let context = await makeInferenceRequestContext(telemetry: telemetry)
        let capturedR2ObjectKeys = r2ObjectKeys
        let capturedScanId = clientScanId
        let capturedTelemetry = telemetry
        let capturedDescription = description
        let capturedObservationContextJSON = observationContextJSON
        let bodyData = try await Task.detached(priority: .userInitiated) {
            try InferencePayloadBuilder.identifyBody(
                r2ObjectKeys: capturedR2ObjectKeys,
                imageBase64s: nil,
                mimeType: "image/webp",
                telemetry: capturedTelemetry,
                context: context,
                clientScanId: capturedScanId,
                description: capturedDescription,
                observationContextJSON: capturedObservationContextJSON
            )
        }.value

        return try await makeAuthenticatedJSONRequest(url: functionUrl, bodyData: bodyData)
    }

    func analyzeSubject(r2ObjectKeys: [String]?, base64ImageDatas: [String]?, mimeType: String = "image/webp", telemetry: CaptureTelemetry, clientScanId: String? = nil, description: String? = nil, observationContextJSON: String? = nil) async throws -> Data {
        let functionUrl = try endpointURL("identify")
        let context = await makeInferenceRequestContext(telemetry: telemetry)
        let capturedR2ObjectKeys = r2ObjectKeys
        let capturedImageBase64s = base64ImageDatas
        let capturedMimeType = mimeType
        let capturedTelemetry = telemetry
        let capturedClientScanId = clientScanId
        let capturedDescription = description
        let capturedObservationContextJSON = observationContextJSON
        let bodyData = try await Task.detached(priority: .userInitiated) {
            try InferencePayloadBuilder.identifyBody(
                r2ObjectKeys: capturedR2ObjectKeys,
                imageBase64s: capturedImageBase64s,
                mimeType: capturedMimeType,
                telemetry: capturedTelemetry,
                context: context,
                clientScanId: capturedClientScanId,
                description: capturedDescription,
                observationContextJSON: capturedObservationContextJSON
            )
        }.value
        // Inference calls can take up to 25–30s on gemini-2.5-pro with slow connections.
        // Use a 90s timeout matching timeoutIntervalForResource to prevent false timeouts.
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData, timeoutInterval: 90.0)
        return data
    }

    // MARK: - Multi-Modal Identification

    static func buildMultiModalRequestBody(
        r2ObjectKeys: [String] = [],
        audioR2ObjectKeys: [String] = [],
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
        clientScanId: String,
        defaultGeoprivacy: String = "open"
    ) throws -> Data {
        let context = InferenceRequestContext(
            userId: userId.lowercased(),
            deviceLocale: deviceLocale,
            deviceTimeZone: deviceTimeZone,
            deviceRegion: deviceRegion,
            currentMonth: currentMonth,
            timeOfDay: timeOfDay,
            depthScaleText: depthScaleText,
            defaultGeoprivacy: InferencePayloadBuilder.normalizedGeoprivacy(defaultGeoprivacy)
        )

        return try InferencePayloadBuilder.multimodalBody(
            r2ObjectKeys: r2ObjectKeys,
            audioR2ObjectKeys: audioR2ObjectKeys,
            imageBase64s: base64ImageDatas,
            audioBase64s: audioBase64s,
            observationContextsJSON: observationContextsJSON,
            mimeType: mimeType,
            telemetry: telemetry,
            context: context,
            clientScanId: clientScanId
        )
    }

    func buildMultiModalRequest(
        r2ObjectKeys: [String] = [],
        audioR2ObjectKeys: [String] = [],
        base64ImageDatas: [String] = [],
        mimeType: String = "image/webp",
        audioFilePaths: [String] = [],
        observationContextsJSON: [String] = [],
        telemetry: CaptureTelemetry,
        clientScanId: String
    ) async throws -> URLRequest {
        let functionUrl = try endpointURL("identify-multimodal")
        let context = await makeInferenceRequestContext(telemetry: telemetry)
        let capturedR2ObjectKeys = r2ObjectKeys
        let capturedBase64ImageDatas = base64ImageDatas
        let capturedClientScanId = clientScanId

        let capturedAudioPaths = audioFilePaths
        let capturedAudioR2ObjectKeys = audioR2ObjectKeys
        let capturedContextsJSON = observationContextsJSON
        let capturedTelemetry = telemetry
        let capturedMimeType = mimeType

        let bodyData = try await Task.detached(priority: .userInitiated) {
            let audioBase64s = try MerianNetworkClient.loadInlineAudioBase64s(from: capturedAudioPaths)
            return try MerianNetworkClient.buildMultiModalRequestBody(
                r2ObjectKeys: capturedR2ObjectKeys,
                audioR2ObjectKeys: capturedAudioR2ObjectKeys,
                base64ImageDatas: capturedBase64ImageDatas,
                audioBase64s: audioBase64s,
                observationContextsJSON: capturedContextsJSON,
                userId: context.userId,
                mimeType: capturedMimeType,
                telemetry: capturedTelemetry,
                deviceLocale: context.deviceLocale,
                deviceTimeZone: context.deviceTimeZone,
                deviceRegion: context.deviceRegion,
                currentMonth: context.currentMonth,
                timeOfDay: context.timeOfDay,
                depthScaleText: context.depthScaleText,
                clientScanId: capturedClientScanId,
                defaultGeoprivacy: context.defaultGeoprivacy
            )
        }.value

        return try await makeAuthenticatedJSONRequest(url: functionUrl, bodyData: bodyData)
    }

    /// Validates that the combined base64 image + audio payload fits the V8 isolator memory budget.
    /// Exposed as `internal` so test targets can exercise budget boundaries without auth dependencies.
    static let maxInlineInferenceBodyBytes = 3_600_000

    static func validateMultiModalPayloadBudget(imageBase64s: [String], audioBase64s: [String]) throws {
        let totalSize = (imageBase64s + audioBase64s).reduce(0) { $0 + $1.utf8.count }
        if totalSize > maxInlineInferenceBodyBytes {
            throw MerianError.payloadTooLarge
        }
    }

    static let maxInlineAudioBytes = MerianConfig.audioPayloadMaxBytes

    private static func loadInlineAudioBase64s(from audioFilePaths: [String]) throws -> [String] {
        guard !audioFilePaths.isEmpty else { return [] }

        let fileURLs = audioFilePaths.map { URL.documentsDirectory.appendingPathComponent($0) }
        try validateInlineAudioFileBudget(fileURLs: fileURLs)

        var audioBase64s: [String] = []
        audioBase64s.reserveCapacity(audioFilePaths.count)

        for url in fileURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let wavData = try Data(contentsOf: url, options: [.mappedIfSafe])
            audioBase64s.append(wavData.base64EncodedString())
        }

        return audioBase64s
    }

    static func validateInlineAudioFileBudget(fileURLs: [URL]) throws {
        var totalAudioBytes = 0
        for url in fileURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            totalAudioBytes += try audioFileSize(at: url)
            guard totalAudioBytes <= maxInlineAudioBytes else {
                throw MerianError.payloadTooLarge
            }
        }
    }

    private static func audioFileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber {
            return size.intValue
        }
        throw MerianError.invalidResponse
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

    func generateUploadURLs(uploadFiles: [StagingUploadFile]) async throws -> [PreSignedURL] {
        let functionUrl = try endpointURL("generate-upload-urls")
        let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let userId = (authUserId ?? deviceId).lowercased()
        let bodyData = try JSONEncoder().encode(UploadURLRequestBody(files: uploadFiles, userId: userId))

        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try JSONDecoder().decode(PreSignedURLResponse.self, from: data).urls
    }

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
        try validateR2UploadResponse(responseData: responseData, response: response)
    }

    func uploadToR2(url: String, fileURL: URL, mimeType: String = "image/webp") async throws {
        guard let signedUrl = URL(string: url) else { throw MerianError.invalidURL }

        var request = URLRequest(url: signedUrl)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let uploadStart = CFAbsoluteTimeGetCurrent()
        let (responseData, response) = try await activeSession.upload(for: request, fromFile: fileURL)
        MerianLog.network.debug("R2 file upload completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - uploadStart), privacy: .public)s.")
        try validateR2UploadResponse(responseData: responseData, response: response)
    }

    private func validateR2UploadResponse(responseData: Data, response: URLResponse) throws {
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
        filter: ExploreFeedFilter = .recent,
        latitude: Double? = nil,
        longitude: Double? = nil,
        cursor: ExploreFeedCursor? = nil
    ) async throws -> [ExplorePost] {
        let functionUrl = try endpointURL("get-explore-feed")
        var payload: [String: Any] = [
            "limit": limit,
            "filter": filter.rawValue
        ]

        if let latitude {
            payload["latitude"] = latitude
        }

        if let longitude {
            payload["longitude"] = longitude
        }

        if let cursor {
            if let beforeSharedAt = cursor.beforeSharedAt,
               let beforePostId = cursor.beforePostId {
                payload["before_shared_at"] = beforeSharedAt
                payload["before_post_id"] = beforePostId
            }

            if let beforeRankingValue = cursor.beforeRankingValue {
                payload["before_ranking_value"] = beforeRankingValue
            }
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

    func getExploreCommentReplies(
        parentCommentId: String,
        limit: Int = 25,
        afterCreatedAt: String? = nil,
        afterCommentId: String? = nil
    ) async throws -> [ExploreComment] {
        let functionUrl = try endpointURL("get-explore-comment-replies")
        var payload: [String: Any] = [
            "parent_comment_id": parentCommentId,
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

    func getSpeciesDictionary(scientificName: String) async throws -> SpeciesDictionaryEntry {
        try await performSpeciesDictionaryRequest(speciesId: nil, scientificName: scientificName)
    }

    func getSpeciesDictionary(speciesId: String, scientificName: String? = nil) async throws -> SpeciesDictionaryEntry {
        try await performSpeciesDictionaryRequest(speciesId: speciesId, scientificName: scientificName)
    }

    func getSpeciesObservationStats(
        speciesId: String? = nil,
        scientificName: String
    ) async throws -> SpeciesObservationStatsEntry {
        let functionUrl = try endpointURL("species-observation-stats")
        let requestedSpeciesId = normalizedSpeciesDictionaryId(speciesId)
        let requestedScientificName = scientificName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty

        if let cached = cachedSpeciesObservationStatsEntry(
            speciesId: requestedSpeciesId,
            scientificName: requestedScientificName
        ) {
            return cached
        }

        var components = URLComponents(url: functionUrl, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if let requestedSpeciesId {
            queryItems.append(URLQueryItem(name: "species_id", value: requestedSpeciesId))
        }
        if let requestedScientificName {
            queryItems.append(URLQueryItem(name: "scientific_name", value: requestedScientificName))
        }
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let requestURL = components?.url else {
            throw MerianError.invalidURL
        }

        let (data, _) = try await performPublicGETRequest(url: requestURL, timeoutInterval: 20.0)
        let entry = try makeExploreDecoder().decode(SpeciesObservationStatsResponse.self, from: data).data
        cacheSpeciesObservationStatsEntry(
            entry,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
        return entry
    }

    private func performSpeciesDictionaryRequest(speciesId: String?, scientificName: String?) async throws -> SpeciesDictionaryEntry {
        let functionUrl = try endpointURL("species-dictionary")
        var payload: [String: Any] = [:]
        let requestedSpeciesId = speciesId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let requestedScientificName = scientificName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        if let cached = cachedSpeciesDictionaryEntry(
            speciesId: requestedSpeciesId,
            scientificName: requestedScientificName
        ) {
            return cached
        }

        if let speciesId = requestedSpeciesId {
            payload["species_id"] = speciesId
        }
        if let scientificName = requestedScientificName {
            payload["scientific_name"] = scientificName
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        let entry = try makeExploreDecoder().decode(SpeciesDictionaryResponse.self, from: data).data
        cacheSpeciesDictionaryEntry(
            entry,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
        return entry
    }

    private func cachedSpeciesDictionaryEntry(
        speciesId: String?,
        scientificName: String?
    ) -> SpeciesDictionaryEntry? {
        guard let key = speciesDictionaryCacheKey(
            speciesId: speciesId,
            scientificName: scientificName
        ) else {
            return nil
        }

        speciesDictionaryCacheLock.lock()
        defer { speciesDictionaryCacheLock.unlock() }

        guard let cached = speciesDictionaryCache[key] else { return nil }
        guard Date().timeIntervalSince(cached.storedAt) < speciesDictionaryCacheTTL else {
            speciesDictionaryCache.removeValue(forKey: key)
            return nil
        }

        return cached.value
    }

    private func cacheSpeciesDictionaryEntry(
        _ entry: SpeciesDictionaryEntry,
        requestedSpeciesId: String?,
        requestedScientificName: String?
    ) {
        let keys = speciesDictionaryCacheKeys(
            for: entry,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
        guard !keys.isEmpty else { return }

        let now = Date()
        speciesDictionaryCacheLock.lock()
        defer { speciesDictionaryCacheLock.unlock() }

        for key in keys {
            speciesDictionaryCache[key] = SpeciesDictionaryCacheEntry(
                value: entry,
                storedAt: now
            )
        }

        if speciesDictionaryCache.count > speciesDictionaryCacheLimit {
            let expiredKeys = speciesDictionaryCache
                .filter { now.timeIntervalSince($0.value.storedAt) >= speciesDictionaryCacheTTL }
                .map(\.key)
            for key in expiredKeys {
                speciesDictionaryCache.removeValue(forKey: key)
            }

            if speciesDictionaryCache.count > speciesDictionaryCacheLimit {
                let currentOverflowCount = speciesDictionaryCache.count - speciesDictionaryCacheLimit
                let keysToRemove = speciesDictionaryCache
                    .sorted { $0.value.storedAt < $1.value.storedAt }
                    .prefix(currentOverflowCount)
                    .map(\.key)
                for key in keysToRemove {
                    speciesDictionaryCache.removeValue(forKey: key)
                }
            }
        }
    }

    private func speciesDictionaryCacheKey(
        speciesId: String?,
        scientificName: String?
    ) -> String? {
        if let speciesId = normalizedSpeciesDictionaryId(speciesId) {
            return "id:\(speciesId)"
        }
        if let scientificName = normalizedSpeciesDictionaryName(scientificName) {
            return "name:\(scientificName)"
        }
        return nil
    }

    private func cachedSpeciesObservationStatsEntry(
        speciesId: String?,
        scientificName: String?
    ) -> SpeciesObservationStatsEntry? {
        guard let key = speciesDictionaryCacheKey(
            speciesId: speciesId,
            scientificName: scientificName
        ) else {
            return nil
        }

        speciesObservationStatsCacheLock.lock()
        defer { speciesObservationStatsCacheLock.unlock() }

        guard let cached = speciesObservationStatsCache[key] else { return nil }
        guard Date().timeIntervalSince(cached.storedAt) < speciesObservationStatsCacheTTL else {
            speciesObservationStatsCache.removeValue(forKey: key)
            return nil
        }

        return cached.value
    }

    private func cacheSpeciesObservationStatsEntry(
        _ entry: SpeciesObservationStatsEntry,
        requestedSpeciesId: String?,
        requestedScientificName: String?
    ) {
        var keys = Set<String>()
        if let requestedSpeciesId = normalizedSpeciesDictionaryId(requestedSpeciesId) {
            keys.insert("id:\(requestedSpeciesId)")
        }
        if let entrySpeciesId = normalizedSpeciesDictionaryId(entry.speciesId) {
            keys.insert("id:\(entrySpeciesId)")
        }
        if let requestedScientificName = normalizedSpeciesDictionaryName(requestedScientificName) {
            keys.insert("name:\(requestedScientificName)")
        }
        if let entryScientificName = normalizedSpeciesDictionaryName(entry.scientificName) {
            keys.insert("name:\(entryScientificName)")
        }
        guard !keys.isEmpty else { return }

        let now = Date()
        speciesObservationStatsCacheLock.lock()
        defer { speciesObservationStatsCacheLock.unlock() }

        for key in keys {
            speciesObservationStatsCache[key] = SpeciesObservationStatsCacheEntry(
                value: entry,
                storedAt: now
            )
        }

        if speciesObservationStatsCache.count > speciesObservationStatsCacheLimit {
            let expiredKeys = speciesObservationStatsCache
                .filter { now.timeIntervalSince($0.value.storedAt) >= speciesObservationStatsCacheTTL }
                .map(\.key)
            for key in expiredKeys {
                speciesObservationStatsCache.removeValue(forKey: key)
            }

            if speciesObservationStatsCache.count > speciesObservationStatsCacheLimit {
                let currentOverflowCount = speciesObservationStatsCache.count - speciesObservationStatsCacheLimit
                let keysToRemove = speciesObservationStatsCache
                    .sorted { $0.value.storedAt < $1.value.storedAt }
                    .prefix(currentOverflowCount)
                    .map(\.key)
                for key in keysToRemove {
                    speciesObservationStatsCache.removeValue(forKey: key)
                }
            }
        }
    }

    private func speciesDictionaryCacheKeys(
        for entry: SpeciesDictionaryEntry,
        requestedSpeciesId: String?,
        requestedScientificName: String?
    ) -> Set<String> {
        var keys = Set<String>()
        if let requestedSpeciesId = normalizedSpeciesDictionaryId(requestedSpeciesId) {
            keys.insert("id:\(requestedSpeciesId)")
        }
        if let entrySpeciesId = normalizedSpeciesDictionaryId(entry.id) {
            keys.insert("id:\(entrySpeciesId)")
        }
        if let requestedScientificName = normalizedSpeciesDictionaryName(requestedScientificName) {
            keys.insert("name:\(requestedScientificName)")
        }
        if let entryScientificName = normalizedSpeciesDictionaryName(entry.scientificName) {
            keys.insert("name:\(entryScientificName)")
        }
        return keys
    }

    private func normalizedSpeciesDictionaryId(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty
    }

    private func normalizedSpeciesDictionaryName(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
            .nilIfEmpty
    }

    func getExploreAuthorProfile(authorUserId: String, previewLimit: Int = 9) async throws -> ExploreAuthorProfile {
        let functionUrl = try endpointURL("get-explore-author-profile")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "author_user_id": authorUserId,
            "preview_limit": previewLimit
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreAuthorProfileResponse.self, from: data).data
    }

    func getExploreAuthorPosts(
        authorUserId: String,
        limit: Int = 30,
        cursor: ExploreAuthorPostCursor? = nil
    ) async throws -> [ExplorePost] {
        let functionUrl = try endpointURL("get-explore-author-posts")
        var payload: [String: Any] = [
            "author_user_id": authorUserId,
            "limit": limit
        ]

        if let cursor,
           let beforeSharedAt = cursor.beforeSharedAt,
           let beforePostId = cursor.beforePostId {
            payload["before_shared_at"] = beforeSharedAt
            payload["before_post_id"] = beforePostId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreAuthorPostsResponse.self, from: data).data
    }

    func getExploreHashtagPosts(
        hashtag: String,
        limit: Int = 30,
        cursor: ExploreHashtagPostCursor? = nil
    ) async throws -> [ExplorePost] {
        let functionUrl = try endpointURL("get-explore-hashtag-posts")
        var payload: [String: Any] = [
            "hashtag": hashtag,
            "limit": limit
        ]

        if let cursor,
           let beforeSharedAt = cursor.beforeSharedAt,
           let beforePostId = cursor.beforePostId {
            payload["before_shared_at"] = beforeSharedAt
            payload["before_post_id"] = beforePostId
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreHashtagPostsResponse.self, from: data).data
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

    func updatePublicUsername(_ username: String) async throws -> PublicUsernameUpdateResponse {
        let functionUrl = try endpointURL("update-public-username")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "username": username
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(PublicUsernameUpdateResponse.self, from: data)
    }

    func updatePublicAvatar(r2ObjectKey: String, mimeType: String) async throws -> PublicAvatarUpdateResponse {
        let functionUrl = try endpointURL("update-public-avatar")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "r2_object_key": r2ObjectKey,
            "mime_type": mimeType
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(PublicAvatarUpdateResponse.self, from: data)
    }

    func checkPublicUsernameAvailability(_ username: String) async throws -> PublicUsernameAvailabilityResponse {
        let functionUrl = try endpointURL("check-public-username")
        let bodyData = try JSONSerialization.data(withJSONObject: [
            "username": username
        ])
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(PublicUsernameAvailabilityResponse.self, from: data)
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

    func shareScanToExplore(
        scanId: String,
        restoredObjectKeys: [String]? = nil,
        fieldNotes: String? = nil,
        hashtags: [String] = [],
        locationSharing: ExplorePostLocationSharing = .obscured
    ) async throws -> ExploreShareResponse {
        let functionUrl = try endpointURL("share-scan-to-explore")
        var payload: [String: Any] = [
            "scan_id": scanId,
            "field_notes": fieldNotes ?? NSNull(),
            "hashtags": hashtags,
            "location_sharing": locationSharing.rawValue
        ]
        if let restoredObjectKeys, !restoredObjectKeys.isEmpty {
            payload["restored_object_keys"] = restoredObjectKeys
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreShareResponse.self, from: data)
    }

    func shareScanToExplore(
        scan: LocalScanRecord,
        fieldNotes: String? = nil,
        hashtags: [String] = [],
        locationSharing: ExplorePostLocationSharing = .obscured
    ) async throws -> ExploreShareResponse {
        let mediaSnapshot = ExploreShareMediaSnapshot(scan: scan)
        do {
            return try await shareScanToExplore(
                scanId: mediaSnapshot.scanId,
                fieldNotes: fieldNotes,
                hashtags: hashtags,
                locationSharing: locationSharing
            )
        } catch {
            guard shouldAttemptExploreMediaRestore(after: error) else {
                throw error
            }

            let restoredObjectKeys = try await restoreExploreMediaObjectKeys(for: mediaSnapshot)
            guard !restoredObjectKeys.isEmpty else {
                throw error
            }

            return try await shareScanToExplore(
                scanId: mediaSnapshot.scanId,
                restoredObjectKeys: restoredObjectKeys,
                fieldNotes: fieldNotes,
                hashtags: hashtags,
                locationSharing: locationSharing
            )
        }
    }

    func unshareExplorePost(postId: String) async throws {
        let functionUrl = try endpointURL("unshare-explore-post")
        let bodyData = try JSONSerialization.data(withJSONObject: ["post_id": postId])
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
    }

    func updateExplorePostFieldNotes(postId: String, fieldNotes: String?) async throws -> ExploreUpdateFieldNotesResponse {
        let functionUrl = try endpointURL("update-explore-field-notes")
        let payload: [String: Any] = [
            "post_id": postId,
            "field_notes": fieldNotes ?? NSNull()
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreUpdateFieldNotesResponse.self, from: data)
    }

    func updateExplorePostContent(
        postId: String,
        fieldNotes: String?,
        hashtags: [String],
        locationSharing: ExplorePostLocationSharing
    ) async throws -> ExploreUpdateFieldNotesResponse {
        let functionUrl = try endpointURL("update-explore-field-notes")
        let payload: [String: Any] = [
            "post_id": postId,
            "field_notes": fieldNotes ?? NSNull(),
            "hashtags": hashtags,
            "location_sharing": locationSharing.rawValue
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreUpdateFieldNotesResponse.self, from: data)
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

    func setUserFollow(authorUserId: String, isFollowing: Bool) async throws -> ExploreFollowState {
        let functionUrl = try endpointURL("set-user-follow")
        let payload: [String: Any] = [
            "author_user_id": authorUserId,
            "is_following": isFollowing
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
        return try makeExploreDecoder().decode(ExploreFollowState.self, from: data)
    }

    func createExploreComment(postId: String, body: String, parentCommentId: String? = nil) async throws -> ExploreCreateCommentResponse {
        let functionUrl = try endpointURL("create-explore-comment")
        var payload: [String: Any] = [
            "post_id": postId,
            "body": body
        ]
        if let parentCommentId {
            payload["parent_comment_id"] = parentCommentId
        }
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

    func toggleExploreCommentReaction(commentId: String, emoji: String) async throws {
        let functionUrl = try endpointURL("toggle-explore-comment-reaction")
        let payload: [String: Any] = [
            "comment_id": commentId,
            "emoji": emoji
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(url: functionUrl, method: "POST", body: bodyData)
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

    private func restoreExploreMediaObjectKeys(for scan: ExploreShareMediaSnapshot) async throws -> [String] {
        let localImagePaths = resolveRestorableImagePaths(for: scan)
        guard !localImagePaths.isEmpty else { return [] }

        let fileNames = localImagePaths.enumerated().map { index, path in
            let ext = URL(fileURLWithPath: path).pathExtension
            let normalizedExt = ext.isEmpty ? "webp" : ext
            return MediaStagingContract.sanitizedFileName("\(scan.scanId)_explore_restore_\(index).\(normalizedExt)")
        }

        let uploadFiles = try zip(localImagePaths, fileNames).map { path, fileName in
            let fileURL = URL.documentsDirectory.appendingPathComponent(path)
            return StagingUploadFile(
                fileName: fileName,
                mediaKind: .image,
                contentType: exploreRestoreMimeType(for: fileURL),
                sizeBytes: try MediaStagingContract.fileSizeBytes(at: fileURL)
            )
        }

        let uploadUrls = try await generateUploadURLs(uploadFiles: uploadFiles)
        guard uploadUrls.count == localImagePaths.count else {
            throw MerianError.invalidResponse
        }

        let uploadPairs = Array(zip(localImagePaths, uploadUrls))
        let maxConcurrentUploads = 2

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = uploadPairs.makeIterator()
            var inFlight = 0

            func enqueueNext() {
                while inFlight < maxConcurrentUploads, let (path, uploadUrl) = iterator.next() {
                    inFlight += 1
                    group.addTask { [self] in
                        let fileURL = URL.documentsDirectory.appendingPathComponent(path)
                        try await uploadToR2(
                            url: uploadUrl.signedUrl,
                            fileURL: fileURL,
                            mimeType: exploreRestoreMimeType(for: fileURL)
                        )
                    }
                }
            }

            enqueueNext()
            while try await group.next() != nil {
                inFlight -= 1
                enqueueNext()
            }
        }

        return uploadUrls.map { $0.objectKey }
    }

    private func resolveRestorableImagePaths(for scan: ExploreShareMediaSnapshot) -> [String] {
        var candidatePaths = scan.imagePaths

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

    private func exploreRestoreMimeType(for fileURL: URL) -> String {
        let fileExtension = fileURL.pathExtension.lowercased()
        if fileExtension == "jpg" || fileExtension == "jpeg" {
            return "image/jpeg"
        }
        if fileExtension == "png" {
            return "image/png"
        }
        if fileExtension == "heic" || fileExtension == "heif" {
            return "image/heic"
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return "image/webp"
        }
        defer { try? handle.close() }

        let prefixData: Data
        do {
            guard let readData = try handle.read(upToCount: 12) else {
                return "image/webp"
            }
            prefixData = readData
        } catch {
            return "image/webp"
        }
        let prefix = [UInt8](prefixData)
        if prefix.count >= 3,
           prefix[0] == 0xFF, prefix[1] == 0xD8, prefix[2] == 0xFF {
            return "image/jpeg"
        }
        if prefix.count >= 8,
           prefix[0] == 0x89, prefix[1] == 0x50, prefix[2] == 0x4E, prefix[3] == 0x47,
           prefix[4] == 0x0D, prefix[5] == 0x0A, prefix[6] == 0x1A, prefix[7] == 0x0A {
            return "image/png"
        }
        if prefix.count >= 12,
           prefix[0] == 0x52, prefix[1] == 0x49, prefix[2] == 0x46, prefix[3] == 0x46,
           prefix[8] == 0x57, prefix[9] == 0x45, prefix[10] == 0x42, prefix[11] == 0x50 {
            return "image/webp"
        }
        return "image/webp"
    }
}
