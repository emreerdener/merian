import SwiftUI

/// Shared countdown treatment for finite-duration audio and video capture.
struct RecordingCountdownBadge: View {
    let progress: Double
    let duration: TimeInterval
    let accessibilityPrefix: String

    private var timeString: String {
        let clampedProgress = min(max(progress, 0), 1)
        let remainingSeconds = max(
            0,
            Int(ceil((1 - clampedProgress) * max(duration, 0)))
        )
        return "0:\(String(format: "%02d", remainingSeconds))"
    }

    var body: some View {
        Text(timeString)
            .font(.subheadline.monospacedDigit())
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(Capsule())
            .transition(.opacity)
            .accessibilityLabel("\(accessibilityPrefix) \(timeString)")
    }
}
