import Foundation

/// Structured description attached to a biological observation.
///
/// This value crosses Capture, inference, persistence, historical loading, and
/// Insights, so its durable representation belongs with the shared captured-
/// media graph rather than any one feature's presentation state.
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

    /// Serializes the context into a structured plain-text block for the AI prompt.
    func serialized() -> String {
        trimmedFreeText
    }
}
