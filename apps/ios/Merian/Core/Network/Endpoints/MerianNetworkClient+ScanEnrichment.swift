import Foundation

/// Late scan context and progressive enrichment requests. Capture and AI callers
/// retain durable context, enrichment scheduling, and stale-result ownership.
extension MerianNetworkClient {
    func updateDeferredScanContext(scanId: String, telemetry: CaptureTelemetry) async throws {
        try validateEndpointConfiguration("update-scan-context")
        var payload: [String: Any] = ["scan_id": scanId]
        if let gpsElevation = telemetry.gpsElevation {
            payload["gps_elevation"] = gpsElevation
        }
        if let condition = telemetry.weatherCondition {
            payload["weather_condition"] = condition
        }
        if let temperature = telemetry.weatherTemperatureF {
            payload["weather_temperature_f"] = temperature
        }
        if let locationName = telemetry.locationName {
            payload["semantic_location"] = locationName
        }
        guard payload.count > 1 else { return }
        try Self.validateJSONPayload(payload)

        try await performAuthenticatedJSONPost(
            function: "update-scan-context",
            payload: payload,
            timeoutInterval: 15
        )
    }

    func fetchEnrichment(
        scanId: String,
        scientificName: String,
        confidenceScore: Double,
        inferenceTier: String,
        scope: String
    ) async throws -> EnrichScanResponse {
        try validateEndpointConfiguration("enrich-scan")
        let payload: [String: Any] = [
            "scan_id": scanId,
            "scientific_name": scientificName,
            "confidence_score": confidenceScore,
            "inference_tier": inferenceTier,
            "scope": scope
        ]
        try Self.validateJSONPayload(payload)
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        // Scan IDs are UUIDs and remain stable across foreground, offline, and
        // server-recovery retries. The database namespaces idempotency by
        // operation, so enrichment and lookalike calls can safely share it.
        guard let idempotencyKey = UUID(uuidString: scanId)?.uuidString.lowercased() else {
            throw MerianError.invalidResponse
        }
        let data = try await performAuthenticatedPreparedJSONPost(
            function: "enrich-scan",
            body: bodyData,
            idempotencyKey: idempotencyKey
        )
        return try JSONDecoder().decode(EnrichScanResponse.self, from: data)
    }

    private static func validateJSONPayload(_ payload: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw CocoaError(.propertyListReadCorrupt)
        }
    }
}
