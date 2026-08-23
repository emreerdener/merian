import Foundation

// MARK: - ObservationContext

/// Structured description of a biological subject the user observed without capturing an image.
///
/// Used as the primary data payload for the Describe submission path and reserved as an
/// optional enrichment parameter on the image scan path — allowing users to attach
/// descriptive context alongside a photo in a future release.
struct ObservationContext: Codable, Equatable, Sendable {

    /// Unstructured natural language descriptors provided by the user.
    var freeText: String = ""

    /// True when the user has not selected any identifying descriptors.
    var isEmpty: Bool {
        trimmedFreeText.isEmpty
    }

    var trimmedFreeText: String {
        freeText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Serializes the context into a structured plain-text block for the Gemini prompt.
    /// Since the Describe route is now purely text-first, this just wraps the input securely.
    func serialized() -> String {
        if !trimmedFreeText.isEmpty {
            return "\(trimmedFreeText)"
        }
        return ""
    }
}
