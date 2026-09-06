import Foundation
import os

// MARK: - Merian Network Client

/// Authenticated HTTP client for all Supabase Edge Function and R2 storage calls.
final class MerianNetworkClient {
    // MARK: - Singleton Architecture
    static let shared = MerianNetworkClient()

    private let supabaseUrl = MerianEnvironment.supabaseUrl
    private let supabaseAnonKey = MerianEnvironment.supabaseAnonKey
    /// No caller can access this memo or insert a response outside the validated request boundary.
    private let speciesDictionaryResponses = SpeciesDictionaryResponseCache()
    private let sessionTransport: PinnedNetworkTransport
    private let authenticatedTransport: AuthenticatedTransportDispatcher

    init() {
        let sessionTransport = PinnedNetworkTransport()
        self.sessionTransport = sessionTransport
        authenticatedTransport = AuthenticatedTransportDispatcher(
            sessionTransport: sessionTransport
        )
    }

    // MARK: - Test Transport Overrides

    #if DEBUG
    /// Allows test suites to inject ephemeral configurations (like MockURLProtocol).
    var overridingSession: URLSession? {
        get { sessionTransport.overridingSession }
        set {
            sessionTransport.overridingSession = newValue
            resetSpeciesDictionaryCacheForTesting()
        }
    }

    /// Keeps request-construction tests independent from Supabase while still
    /// allowing dedicated tests to prove that consent failures stop dispatch.
    var overridingInferenceConsentCheck: (@Sendable () async throws -> Void)?

    /// Explicit account identity for mocked requests whose injected transport
    /// intentionally has no live Supabase SDK session. Production never reads
    /// this seam.
    var overridingAuthUserID: UUID? {
        get { authenticatedTransport.overridingAuthUserID }
        set { authenticatedTransport.overridingAuthUserID = newValue }
    }

    /// Lets the 401 recovery regression exercise the real request replay branch
    /// without refreshing or replacing a developer's persisted simulator session.
    var overridingAuthSessionRefresh: (@Sendable () async -> Bool)? {
        get { authenticatedTransport.overridingAuthSessionRefresh }
        set {
            authenticatedTransport.overridingAuthSessionRefresh = newValue
        }
    }
    #endif

    // MARK: - URL Construction

    /// Builds a URL for the given Edge Function path segment.
    /// Throws `MerianError.invalidURL` rather than crashing if `supabaseUrl` is misconfigured.
    private func endpointURL(_ function: String) throws -> URL {
        guard MerianEnvironment.isSupabaseConfigured else {
            MerianLog.network.error("Network request blocked because Supabase environment configuration is incomplete.")
            throw MerianError.invalidURL
        }
        return try EdgeFunctionRoutePolicy.endpointURL(
            baseURL: supabaseUrl,
            function: function
        )
    }

    private func makeExploreDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    #if DEBUG
    func resetSpeciesDictionaryCacheForTesting() {
        speciesDictionaryResponses.resetForTesting()
    }
    #endif

    // MARK: - Authenticated Request Core

    /// Narrow entry point for endpoint extensions using snake-case JSON envelopes.
    /// Session state, Auth leases, retry policy, and cancellation remain private
    /// to the existing authenticated transport; this helper adds no retry layer.
    /// A supplied failure replaces decoding errors only, never transport errors.
    func performAuthenticatedJSONPost<Response: Decodable>(
        function: String,
        payload: [String: Any],
        responseType: Response.Type,
        timeoutInterval: TimeInterval = 30.0,
        idempotencyKey: String? = nil,
        decodingFailure: MerianError? = nil
    ) async throws -> Response {
        let url = try endpointURL(function)
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(
            url: url,
            method: "POST",
            body: body,
            timeoutInterval: timeoutInterval,
            idempotencyKey: idempotencyKey
        )
        do {
            return try makeExploreDecoder().decode(responseType, from: data)
        } catch {
            if let decodingFailure { throw decodingFailure }
            throw error
        }
    }

    /// Sends a JSON POST whose caller intentionally ignores the successful body.
    /// Empty, non-JSON, and application-level fields in a 2xx body remain ignored;
    /// HTTP failures still use the existing authenticated transport policy.
    func performAuthenticatedJSONPost(
        function: String,
        payload: [String: Any],
        timeoutInterval: TimeInterval = 30.0
    ) async throws {
        let url = try endpointURL(function)
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await performAuthenticatedRequest(
            url: url,
            method: "POST",
            body: body,
            timeoutInterval: timeoutInterval
        )
    }

    /// Encodes a typed request body and returns bytes for domain-specific validation.
    /// URL construction, Auth, replay, and cancellation stay behind this boundary.
    func performAuthenticatedEncodedJSONPost<Body: Encodable>(
        function: String,
        body: Body,
        timeoutInterval: TimeInterval,
        idempotencyKey: String? = nil
    ) async throws -> Data {
        let url = try endpointURL(function)
        let bodyData = try JSONEncoder().encode(body)
        let (data, _) = try await performAuthenticatedRequest(
            url: url,
            method: "POST",
            body: bodyData,
            timeoutInterval: timeoutInterval,
            idempotencyKey: idempotencyKey
        )
        return data
    }

    /// Builds an encoded body with the exact account later reacquired by transport.
    /// Configuration precedes account resolution and encoding; the body builder
    /// cannot escape or acquire mutable session state.
    func performAccountBoundEncodedJSONPost<Body: Encodable>(
        function: String,
        expectedAuthUserID: UUID? = nil,
        body: (UUID) -> Body
    ) async throws -> Data {
        let url = try endpointURL(function)
        let authUserID: UUID
        if let expectedAuthUserID {
            authUserID = expectedAuthUserID
        } else {
            authUserID = try await authenticatedTransport
                .requestPayloadAuthUserID()
        }
        let bodyData = try JSONEncoder().encode(body(authUserID))
        let (data, _) = try await performAuthenticatedRequest(
            url: url,
            method: "POST",
            body: bodyData,
            expectedAuthUserID: authUserID
        )
        return data
    }

    /// Value-only account boundary for owner-row reconstruction. Recovery may
    /// encode the UUID but cannot observe or retain Auth session/lease state;
    /// the status endpoint binds the encoded owner back to private transport.
    func authenticatedUserIDForOwnedScanRecovery() async throws -> UUID {
        try await authenticatedTransport.requestPayloadAuthUserID()
    }

    /// Value-only account boundary for inference payload construction. The
    /// endpoint can encode this UUID but cannot retain Auth session or lease state.
    func authenticatedUserIDForInferenceRequest() async throws -> UUID {
        try await authenticatedTransport.requestPayloadAuthUserID()
    }

    /// Fixed-route prewarm for the pinned inference connection pool. The
    /// endpoint owns best-effort error handling; session state remains private.
    func performInferenceTransportPrewarm() async throws {
        let url = try endpointURL("identify-multimodal")
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 5
        )
        request.httpMethod = "OPTIONS"
        _ = try await sessionTransport.data(for: request)
    }

    /// Dispatches only the authenticated, non-reserving admission RPC over the
    /// shared pinned transport. The caller owns decoding and intentionally gets
    /// no Auth refresh, replay, or generic raw-request capability.
    func performPinnedScanAdmissionPreviewRequest(
        _ request: URLRequest,
        timeoutInterval: TimeInterval
    ) async throws -> (Data, URLResponse) {
        guard let baseURL = SecureTransportPolicy.httpsURL(from: supabaseUrl),
              let requestURL = request.url else {
            throw MerianError.invalidURL
        }
        let expectedURL = baseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent("get_my_scan_admission_preview")
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let apiKey = request.value(forHTTPHeaderField: "apikey")
        guard request.httpMethod == "POST",
              requestURL == expectedURL,
              authorization?.hasPrefix("Bearer ") == true,
              authorization.map({
                  String($0.dropFirst("Bearer ".count))
                      .trimmingCharacters(in: .whitespacesAndNewlines)
              })?.isEmpty == false,
              apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false else {
            throw MerianError.invalidURL
        }
        return try await sessionTransport.data(
            for: request,
            timeoutInterval: timeoutInterval
        )
    }

    /// Builds one authenticated inference request without exposing endpoint URLs,
    /// Auth headers, or account-work leases to the endpoint extension.
    func makeAuthenticatedInferenceURLRequest(
        function: String,
        bodyData: Data,
        idempotencyKey: String,
        expectedAuthUserID: UUID
    ) async throws -> URLRequest {
        let url = try endpointURL(function)
        return try await authenticatedTransport.makeAuthenticatedJSONRequest(
            url: url,
            bodyData: bodyData,
            idempotencyKey: idempotencyKey,
            expectedAuthUserID: expectedAuthUserID
        )
    }

    /// Dispatches prepared Identify JSON through the existing private Auth,
    /// cancellation, refresh, and replay implementation.
    func performAuthenticatedInferenceJSONPost(
        function: String,
        body: Data,
        timeoutInterval: TimeInterval,
        idempotencyKey: String,
        expectedAuthUserID: UUID
    ) async throws -> Data {
        let url = try endpointURL(function)
        let (data, _) = try await performAuthenticatedRequest(
            url: url,
            method: "POST",
            body: body,
            timeoutInterval: timeoutInterval,
            idempotencyKey: idempotencyKey,
            expectedAuthUserID: expectedAuthUserID
        )
        return data
    }

    /// Dispatches a previously bound request while preserving its exact body,
    /// stable idempotency key, account, timeout, and queue-owned retry policy.
    func performAuthenticatedInferenceRequest(
        _ authenticatedRequest: AuthenticatedInferenceRequest,
        timeoutInterval: TimeInterval,
        allowsTransientTransportRetry: Bool,
        onRequestBodySent: (@Sendable () -> Void)?
    ) async throws -> Data {
        let request = authenticatedRequest.request
        guard let url = request.url, let bodyData = request.httpBody else {
            throw MerianError.invalidURL
        }
        let (data, _) = try await performAuthenticatedRequest(
            url: url,
            method: "POST",
            body: bodyData,
            timeoutInterval: timeoutInterval,
            idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
            allowsTransientTransportRetry: allowsTransientTransportRetry,
            onRequestBodySent: onRequestBodySent,
            expectedAuthUserID: authenticatedRequest.expectedAuthUserID
        )
        return data
    }

    /// Raw signed uploads reuse the pinned session without Edge authentication,
    /// response decoding, retry, or cancellation translation.
    func performPresignedUpload(request: URLRequest) async throws -> (Data, URLResponse) {
        try await sessionTransport.data(for: request)
    }

    func performPresignedUpload(request: URLRequest, fileURL: URL) async throws -> (Data, URLResponse) {
        try await sessionTransport.upload(for: request, fromFile: fileURL)
    }

    /// Returns JSON response bytes for endpoint-owned explicit-key decoding.
    /// Account binding, Auth leases, replay, and cancellation remain in the private transport.
    func performAuthenticatedJSONDataPost(
        function: String,
        payload: [String: Any],
        expectedAuthUserID: UUID? = nil
    ) async throws -> Data {
        let url = try endpointURL(function)
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await performAuthenticatedRequest(
            url: url,
            method: "POST",
            body: body,
            expectedAuthUserID: expectedAuthUserID
        )
        return data
    }

    /// Sends an already-serialized JSON body without changing its bytes.
    /// Endpoints with pre-dispatch validation first check configuration, then
    /// prepare the body and validate it before entering the private transport.
    func performAuthenticatedPreparedJSONPost(
        function: String,
        body: Data,
        timeoutInterval: TimeInterval = 30.0,
        idempotencyKey: String? = nil
    ) async throws -> Data {
        let url = try endpointURL(function)
        let (data, _) = try await performAuthenticatedRequest(
            url: url,
            method: "POST",
            body: body,
            timeoutInterval: timeoutInterval,
            idempotencyKey: idempotencyKey
        )
        return data
    }

    /// Fixed-route deletion bridge. Resolve configuration before the nonescaping
    /// body builder and forward the exact transition owner to private Auth transport.
    func performAccountDeletionJSONPost(
        ownedBy authTransitionOwner: AuthTransitionToken?,
        body: () throws -> Data?
    ) async throws -> (data: Data, statusCode: Int) {
        let url = try endpointURL("safe-delete")
        let bodyData = try body()
        let (data, response) = try await performAuthenticatedRequest(
            url: url,
            method: "POST",
            body: bodyData,
            authTransitionOwner: authTransitionOwner
        )
        return (data, response.statusCode)
    }

    /// Capability-only continuation deliberately bypasses user Auth. Its private
    /// transport retains the existing response bound, retry, and cancellation rules.
    func performAccountDeletionRecoveryJSONPost(
        body: () throws -> Data
    ) async throws -> (data: Data, statusCode: Int) {
        let url = try endpointURL("recover-account-deletion")
        let bodyData = try body()
        let (data, response) = try await performPublicAccountDeletionRecoveryRequest(
            url: url,
            body: bodyData
        )
        return (data, response.statusCode)
    }

    /// Preserves endpoint-configuration failure precedence before validation or
    /// cache lookup. The URL builder and authenticated transport remain private.
    func validateEndpointConfiguration(_ function: String) throws {
        _ = try endpointURL(function)
    }

    /// Keeps memo access inside the client. Callers supply request values, never
    /// a cache entry or loader that could bypass authenticated response validation.
    func performCachedSpeciesDictionaryRequest(
        payload: [String: Any],
        requestedSpeciesId: String?,
        requestedScientificName: String?
    ) async throws -> SpeciesDictionaryEntry {
        if let cached = speciesDictionaryResponses.dictionaryEntry(
            speciesId: requestedSpeciesId,
            scientificName: requestedScientificName
        ) {
            return cached
        }

        let response = try await performAuthenticatedJSONPost(
            function: "species-dictionary",
            payload: payload,
            responseType: SpeciesDictionaryResponse.self
        )
        let entry = try SpeciesDictionaryResponseValidator.dictionaryEntry(
            response,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
        speciesDictionaryResponses.storeDictionaryEntry(entry)
        return entry
    }

    /// A warm memo hit intentionally precedes transport cancellation and Auth.
    /// A miss can populate the memo only after the fixed stats validator accepts it.
    func performCachedSpeciesObservationStatsRequest(
        queryItems: [URLQueryItem],
        requestedSpeciesId: String,
        requestedScientificName: String
    ) async throws -> SpeciesObservationStatsEntry {
        if let cached = speciesDictionaryResponses.observationStatsEntry(
            speciesId: requestedSpeciesId,
            scientificName: requestedScientificName
        ) {
            return cached
        }

        let response = try await performAuthenticatedJSONGet(
            function: "species-observation-stats",
            queryItems: queryItems,
            responseType: SpeciesObservationStatsResponse.self,
            timeoutInterval: 20
        )
        let entry = try SpeciesDictionaryResponseValidator.observationStats(
            response,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
        speciesDictionaryResponses.storeObservationStatsEntry(
            entry,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
        return entry
    }

    /// Typed authenticated GET for endpoint-owned ordered query items. This uses
    /// the same header, Auth lease, retry, and cancellation path as JSON POST.
    private func performAuthenticatedJSONGet<Response: Decodable>(
        function: String,
        queryItems: [URLQueryItem],
        responseType: Response.Type,
        timeoutInterval: TimeInterval
    ) async throws -> Response {
        let url = try endpointURL(function)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let requestURL = components?.url else { throw MerianError.invalidURL }
        let (data, _) = try await performAuthenticatedRequest(
            url: requestURL,
            method: "GET",
            timeoutInterval: timeoutInterval
        )
        return try makeExploreDecoder().decode(responseType, from: data)
    }

    private func performAuthenticatedRequest(
        url: URL,
        method: String,
        body: Data? = nil,
        timeoutInterval: TimeInterval = 30.0,
        idempotencyKey: String? = nil,
        allowsTransientTransportRetry: Bool = true,
        onRequestBodySent: (@Sendable () -> Void)? = nil,
        authTransitionOwner: AuthTransitionToken? = nil,
        expectedAuthUserID: UUID? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let executor = AuthenticatedRequestExecutor(
            dependencies: .live(
                requestPayloadAuthUserID: { [self] in
                    try await self.authenticatedTransport
                        .requestPayloadAuthUserID()
                },
                performTransport: { [self] attempt in
                    try await self.authenticatedTransport.perform(attempt)
                },
                refreshOrdinarySession: { [self] in
                    await self.authenticatedTransport
                        .refreshActiveSessionForRetry()
                }
            )
        )
        return try await executor.execute(
            AuthenticatedRequestExecutor.Request(
                url: url,
                method: method,
                body: body,
                timeoutInterval: timeoutInterval,
                idempotencyKey: idempotencyKey,
                allowsTransientTransportRetry:
                    allowsTransientTransportRetry,
                onRequestBodySent: onRequestBodySent,
                authTransitionOwner: authTransitionOwner,
                expectedAuthUserID: expectedAuthUserID
            )
        )
    }

    // MARK: - Account Deletion Recovery Transport

    private func performPublicAccountDeletionRecoveryRequest(
        url: URL,
        body: Data,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sessionTransport.data(for: request)
        } catch let urlError as URLError {
            try Task.checkCancellation()
            let transientCodes: Set<URLError.Code> = [
                .timedOut,
                .networkConnectionLost,
                .cannotConnectToHost,
                .dnsLookupFailed,
                .notConnectedToInternet
            ]
            if transientCodes.contains(urlError.code), !isRetry {
                try await Task.sleep(for: .seconds(2))
                return try await performPublicAccountDeletionRecoveryRequest(
                    url: url,
                    body: body,
                    isRetry: true
                )
            }
            throw urlError
        }

        try Task.checkCancellation()
        guard data.count <= 64 * 1024,
              let httpResponse = response as? HTTPURLResponse else {
            throw MerianError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode >= 500, !isRetry {
                try await Task.sleep(for: .seconds(2))
                return try await performPublicAccountDeletionRecoveryRequest(
                    url: url,
                    body: body,
                    isRetry: true
                )
            }
            let message = String(data: data, encoding: .utf8) ?? ""
            throw MerianError.httpError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
        return (data, httpResponse)
    }

}
