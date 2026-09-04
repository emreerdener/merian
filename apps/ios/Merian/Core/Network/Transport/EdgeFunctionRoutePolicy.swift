import Foundation

struct EdgeFunctionRouteResponseEvidence: Sendable {
    let statusCode: Int
    let handlerMarker: String?
    let supabaseErrorCode: String?
    let hasGatewayVersion: Bool
    let hasExecutionId: Bool
    let retryAfterSeconds: TimeInterval?

    init(response: HTTPURLResponse) {
        statusCode = response.statusCode
        handlerMarker = response.value(forHTTPHeaderField: "X-Merian-Handler")
        supabaseErrorCode = response.value(forHTTPHeaderField: "SB-Error-Code")
        hasGatewayVersion = response.value(
            forHTTPHeaderField: "SB-Gateway-Version"
        ) != nil
        hasExecutionId = response.value(
            forHTTPHeaderField: "X-Deno-Execution-Id"
        ) != nil
        retryAfterSeconds = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .flatMap { (1...86_400).contains($0) ? TimeInterval($0) : nil }
    }
}

enum EdgeFunctionRoutePolicy {
    private static let unavailableRetryDelays: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        4_000_000_000
    ]

    static var unavailableRetryLimit: Int {
        unavailableRetryDelays.count
    }

    static func unavailableRetryDelay(forAttempt attempt: Int) -> UInt64? {
        guard unavailableRetryDelays.indices.contains(attempt) else {
            return nil
        }
        return unavailableRetryDelays[attempt]
    }

    static func endpointURL(
        baseURL: String,
        function: String
    ) throws -> URL {
        guard let url = SecureTransportPolicy.httpsURL(
            from: "\(baseURL)/functions/v1/\(function)"
        ) else {
            throw MerianError.invalidURL
        }
        return url
    }

    static func isUnavailable(
        evidence: EdgeFunctionRouteResponseEvidence,
        responseData: Data
    ) -> Bool {
        let handlerMarker = evidence.handlerMarker?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard evidence.statusCode == 404,
              handlerMarker != "1" else {
            return false
        }

        if evidence.supabaseErrorCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("NOT_FOUND") == .orderedSame {
            return true
        }

        if EdgeFunctionErrorPolicy.reportsMissingFunction(
            responseData: responseData
        ) {
            return true
        }

        if String(data: responseData, encoding: .utf8)?
            .localizedCaseInsensitiveContains(
                "Requested function was not found"
            ) == true {
            return true
        }

        return evidence.hasGatewayVersion && !evidence.hasExecutionId
    }
}
