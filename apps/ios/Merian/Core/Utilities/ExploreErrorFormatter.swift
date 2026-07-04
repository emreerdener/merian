import Foundation

enum ExploreErrorFormatter {
    private static let genericMessage = "Something went wrong. Please try again."
    private static let persistenceFallbackMessage = "We couldn’t finish that. Please try again."
    private static let duplicateScanMessage = "This scan is already saved. Try sharing again."

    private struct ErrorEnvelope: Decodable {
        let error: String?
        let message: String?
    }

    static func message(for error: Error) -> String {
        if let merianError = error as? MerianError {
            switch merianError {
            case .httpError(let statusCode, let rawMessage):
                if let parsed = parsedMessage(from: rawMessage) {
                    return sanitizedMessage(from: parsed) ?? parsed
                }
                if let sanitized = sanitizedMessage(from: rawMessage) {
                    return sanitized
                }
                if statusCode >= 500 {
                    return genericMessage
                }
                return fallbackMessage(from: rawMessage)
            default:
                break
            }
        }

        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = parsedMessage(from: localized) {
            return sanitizedMessage(from: parsed) ?? parsed
        }
        return fallbackMessage(from: localized)
    }

    static func titledMessage(_ title: String, for error: Error) -> String {
        "\(title)\n\(message(for: error))"
    }

    private static func parsedMessage(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidateJSON: String
        if let braceIndex = trimmed.firstIndex(of: "{") {
            candidateJSON = String(trimmed[braceIndex...])
        } else {
            candidateJSON = trimmed
        }

        guard let data = candidateJSON.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return nil
        }

        let message = envelope.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? envelope.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return message?.isEmpty == false ? message : nil
    }

    private static func fallbackMessage(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return genericMessage
        }
        if let sanitized = sanitizedMessage(from: trimmed) {
            return sanitized
        }
        return trimmed
    }

    private static func sanitizedMessage(from raw: String) -> String? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return nil }

        if normalized.contains("scans_pkey")
            || (normalized.contains("duplicate key") && normalized.contains("scans")) {
            return duplicateScanMessage
        }

        let technicalMarkers = [
            "duplicate key value",
            "violates unique constraint",
            "violates foreign key constraint",
            "null value in column",
            "row-level security",
            "permission denied for table",
            "postgrest",
            "sqlstate",
            "pgrst"
        ]

        if technicalMarkers.contains(where: normalized.contains) {
            return persistenceFallbackMessage
        }

        return nil
    }
}
