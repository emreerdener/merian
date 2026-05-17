import SwiftUI

// MARK: - SNR Gauge

/// Tooltip indicator showing the current signal-to-noise level.
struct SNRGaugeView: View {
    let snrLevel: SNRLevel

    @Environment(AppSettings.self) private var appSettings
    @State private var showInitialTooltip: Bool = !SNRGaugeView.hasShownInitialTooltipThisSession
    @State private var hintsAllowed: Bool = SNRGaugeView.hasShownInitialTooltipThisSession
    @State private var promptTask: Task<Void, Never>?
    private static var hasShownInitialTooltipThisSession: Bool = false

    var body: some View {
        Group {
            if appSettings.audioHintsEnabled {
                if showInitialTooltip {
                    Text("Record 15 seconds")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .clipShape(Capsule())
                        .transition(.opacity)
                } else if hintsAllowed && snrLevel != .clear {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .clipShape(Capsule())
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showInitialTooltip)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: snrLevel)
        .onAppear {
            if showInitialTooltip {
                schedulePromptDismissal()
            }
        }
    }

    private func schedulePromptDismissal() {
        SNRGaugeView.hasShownInitialTooltipThisSession = true
        promptTask?.cancel()
        promptTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showInitialTooltip = false }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            hintsAllowed = true
        }
    }

    // MARK: - Styling
    private var label: String {
        switch snrLevel {
        case .clear:    return "Clear"
        case .caution:  return "Some noise"
        case .warning:  return "Shield mic"
        case .clipping: return "Move mic away"
        }
    }
}
