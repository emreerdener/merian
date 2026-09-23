import Foundation

/// Content-free diagnostics for an observed HTTP response. No request identity,
/// response body, evidence, region or arbitrary header text enters the record.
enum IdentificationBenchmarkRecord {
    static let marker = "[⏱ BENCH] Identification measurement "
    private static let null = NSNull()
    private static let spanNames: Set<String> = ["provider", "edge_total"]
    private static let maxTimingMetrics = 32

    private struct Header: Decodable {
        let version: Int
        let provider: String
        let requestedModel: String
        let returnedModel: String?
        let backendBundleSha256: String
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let promptTokens: Int?
        let candidateTokens: Int?
        let thinkingTokens: Int?
        let totalTokens: Int?
        let cachedTokens: Int?
        let toolTokens: Int?

        var projection: [String: Any] {
            [
                "promptTokens": token(promptTokens),
                "candidateTokens": token(candidateTokens),
                "thinkingTokens": token(thinkingTokens),
                "totalTokens": token(totalTokens),
                "cachedTokens": token(cachedTokens),
                "toolTokens": token(toolTokens)
            ]
        }

        private func token(_ value: Int?) -> Any {
            guard let value, (0...10_000_000).contains(value) else { return null }
            return value
        }
    }

    static func make(response: HTTPURLResponse, appInfo: [String: Any]) -> String? {
        let replayHeader = response.value(forHTTPHeaderField: "X-Merian-Idempotent-Replay")
        let replay = ["stored", "reconstructed"].contains(replayHeader ?? "")
        let diagnostics = response.statusCode == 200 && replayHeader == nil
            ? diagnosticProjection(response.value(forHTTPHeaderField: "X-Merian-Identification"))
            : nil
        // Keep the logged record compact. Detailed overlapping spans remain in
        // the HTTP header; these two establish the provider/other-work boundary.
        let timing = timingProjection(response.value(forHTTPHeaderField: "Server-Timing"))
        let spans = timing.spans
        let otherEdgeMs: Any
        if let total = spans["edge_total"], let provider = spans["provider"], total >= provider {
            otherEdgeMs = total - provider
        } else {
            otherEdgeMs = null
        }
        let record: [String: Any] = [
            "version": "identification_app_measurement_v1",
            "status": response.statusCode,
            "delivery": replay ? "replay" : diagnostics == nil ? "unavailable" : "fresh",
            "app": [
                "version": bounded(appInfo["CFBundleShortVersionString"], "^[0-9]{1,5}(\\.[0-9]{1,5}){0,3}$") as Any? ?? null,
                "build": bounded(appInfo["CFBundleVersion"], "^[0-9]{1,10}(\\.[0-9]{1,5}){0,2}$") as Any? ?? null,
                "sourceRevision": bounded(appInfo["MERIAN_SOURCE_REVISION"], "^[0-9a-f]{40}([0-9a-f]{24})?$") as Any? ?? null,
                "sourceFingerprint": bounded(appInfo["MERIAN_SOURCE_FINGERPRINT"], "^[0-9a-f]{64}$") as Any? ?? null,
                "sourceState": bounded(appInfo["MERIAN_SOURCE_STATE"], "^(clean|dirty)$") as Any? ?? null
            ],
            "diagnostics": diagnostics as Any? ?? null,
            "timingStatus": timing.status,
            "serverTimingMs": spans,
            "otherEdgeMs": otherEdgeMs
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func bounded(_ value: Any?, _ pattern: String) -> String? {
        guard let value = value as? String, value.utf8.count <= 128,
              value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex else { return nil }
        return value
    }

    private static func diagnosticProjection(_ value: String?) -> [String: Any]? {
        guard let value, value.utf8.count <= 2_048,
              let header = try? JSONDecoder().decode(Header.self, from: Data(value.utf8)),
              header.version == 1, header.provider == "gemini",
              ["gemini-2.5-flash", "gemini-2.5-pro"].contains(header.requestedModel),
              let digest = bounded(header.backendBundleSha256, "^[0-9a-f]{64}$") else { return nil }
        return [
            "version": 1,
            "provider": header.provider,
            "requestedModel": header.requestedModel,
            "returnedModel": bounded(header.returnedModel, "^gemini-[a-zA-Z0-9.-]{1,100}$") as Any? ?? null,
            "backendBundleSha256": digest,
            "usage": header.usage?.projection as Any? ?? null
        ]
    }

    private static func timingProjection(_ value: String?) -> (spans: [String: Double], status: String) {
        guard let value else { return ([:], "absent") }
        guard value.utf8.count <= 2_048 else { return ([:], "oversized") }
        // Intermediaries may append metrics and quoted descriptions. Split only
        // outside quotes so description text can never masquerade as a metric.
        var entries: [Substring] = []
        var start = value.startIndex
        var quoted = false, escaped = false
        for index in value.indices {
            let character = value[index]
            if escaped {
                escaped = false
            } else if quoted && character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if character == "," && !quoted {
                entries.append(value[start..<index])
                guard entries.count < maxTimingMetrics else { return ([:], "too_many_metrics") }
                start = value.index(after: index)
            }
        }
        guard !quoted && !escaped else { return ([:], "invalid_syntax") }
        entries.append(value[start...])
        var result: [String: Double] = [:]
        for entry in entries {
            let text = entry.trimmingCharacters(in: .whitespaces)
            let name = String(text.prefix { $0 != ";" }).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return ([:], "invalid_syntax") }
            // Only the two retained spans need validation. Unrelated metric
            // names, parameters and descriptions never enter the projection.
            guard spanNames.contains(name) else { continue }
            let parts = text.components(separatedBy: ";dur=")
            guard parts.count == 2, parts[0] == name else { return ([:], "invalid_syntax") }
            guard result[parts[0]] == nil else { return ([:], "duplicate_metric") }
            guard
                  parts[1].range(of: "^[0-9]{1,6}(\\.[0-9]{1,6})?$", options: .regularExpression) == parts[1].startIndex..<parts[1].endIndex,
                  let duration = Double(parts[1]), duration.isFinite,
                  (0...600_000).contains(duration) else { return ([:], "invalid_duration") }
            result[parts[0]] = duration
        }
        return (result, "valid")
    }
}
