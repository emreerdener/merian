import Foundation

enum ExploreErrorFormatter {
    private struct ErrorEnvelope: Decodable {
        let error: String?
        let message: String?
    }

    static func message(for error: Error) -> String {
        if let merianError = error as? MerianError {
            switch merianError {
            case .httpError(let statusCode, let rawMessage):
                if statusCode >= 500 {
                    return "Something went wrong. Please try again."
                }
                return parsedMessage(from: rawMessage) ?? fallbackMessage(from: rawMessage)
            default:
                break
            }
        }

        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return parsedMessage(from: localized) ?? fallbackMessage(from: localized)
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
            return "Something went wrong. Please try again."
        }
        return trimmed
    }
}
