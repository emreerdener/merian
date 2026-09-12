import CoreGraphics

enum ImagePreparationPolicy {
    /// Lossy quality for WebP-encoded captures before storage or upload.
    static let compressionQuality: CGFloat = 0.85

    /// Longest-edge cap for Pro inference payloads.
    static let proInferenceMaxDimension: CGFloat = 1_024

    /// Longest-edge cap for Flash inference payloads.
    static let flashInferenceMaxDimension: CGFloat = 768

    /// Largest inference cap used when a source is already tier-bounded.
    static let maximumInferenceDimension = max(
        proInferenceMaxDimension,
        flashInferenceMaxDimension
    )

    /// Longest-edge cap for images stored for display.
    static let displayMaxDimension: CGFloat = 2_048

    static func inferenceMaxDimension(isProActive: Bool) -> CGFloat {
        isProActive ? proInferenceMaxDimension : flashInferenceMaxDimension
    }
}
