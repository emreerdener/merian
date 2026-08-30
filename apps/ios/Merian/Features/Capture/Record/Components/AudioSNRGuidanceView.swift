import SwiftUI

/// Lifecycle-owned guidance for the current audio signal quality.
struct AudioSNRGuidanceView: View {
    let snrLevel: SNRLevel
    let audioHintsEnabled: Bool

    @State private var showInitialTooltip =
        !AudioSNRGuidanceView.hasShownInitialTooltipThisSession
    @State private var hintsAllowed =
        AudioSNRGuidanceView.hasShownInitialTooltipThisSession
    @State private var promptTask: Task<Void, Never>?
    private static var hasShownInitialTooltipThisSession = false

    var body: some View {
        Group {
            if audioHintsEnabled {
                if showInitialTooltip {
                    guidanceBadge(text: "Record 15 seconds")
                } else if hintsAllowed && snrLevel != .clear {
                    guidanceBadge(
                        text: AudioSNRPresentation.label(for: snrLevel)
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showInitialTooltip)
        .animation(
            .spring(response: 0.3, dampingFraction: 0.7),
            value: snrLevel
        )
        .allowsHitTesting(false)
        .onAppear {
            if showInitialTooltip {
                schedulePromptDismissal()
            }
        }
        .onDisappear {
            promptTask?.cancel()
            promptTask = nil
        }
    }

    private func guidanceBadge(text: String) -> some View {
        Text(text)
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

    private func schedulePromptDismissal() {
        AudioSNRGuidanceView.hasShownInitialTooltipThisSession = true
        promptTask?.cancel()
        promptTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3.5))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation { showInitialTooltip = false }
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            hintsAllowed = true
        }
    }
}
