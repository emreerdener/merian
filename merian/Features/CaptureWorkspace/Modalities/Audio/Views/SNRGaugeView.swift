import SwiftUI

// MARK: - SNR Gauge

/// Pill indicator showing the current signal-to-noise level. Shakes when clipping is detected.
struct SNRGaugeView: View {
    let snrLevel: SNRLevel

    @State private var shakePhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(background, in: Capsule())
        .offset(x: shakePhase)
        .onChange(of: snrLevel) { _, newLevel in
            if newLevel == .clipping {
                triggerShake()
            }
        }
    }

    // MARK: - Styling

    private var icon: String {
        switch snrLevel {
        case .clear:    return "waveform"
        case .caution:  return "waveform.badge.exclamationmark"
        case .warning:  return "ear.trianglebadge.exclamationmark"
        case .clipping: return "speaker.wave.3.fill"
        }
    }

    private var label: String {
        switch snrLevel {
        case .clear:    return "Clear"
        case .caution:  return "Some noise"
        case .warning:  return "Shield mic"
        case .clipping: return "Move mic away"
        }
    }

    private var background: Color {
        switch snrLevel {
        case .clear:    return Color.green.opacity(0.75)
        case .caution:  return Color.yellow.opacity(0.75)
        case .warning:  return Color.orange.opacity(0.75)
        case .clipping: return Color.red.opacity(0.85)
        }
    }

    // MARK: - Shake

    private func triggerShake() {
        let keyframes: [CGFloat] = [0, -8, 8, -6, 6, -3, 3, 0]
        var delay: TimeInterval = 0
        for offset in keyframes {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.05)) {
                    shakePhase = offset
                }
            }
            delay += 0.05
        }
    }
}
