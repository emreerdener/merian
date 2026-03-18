import SwiftUI

struct NewDiscoveryCelebrationView: View {
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    
    let commonName: String
    let onDismiss: () -> Void
    
    @State private var dismissTask: Task<Void, Never>?
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon Fallback
            if !hardwareOrchestrator.isCriticalHeatWarningActive {
                if #available(iOS 17.0, *) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .symbolEffect(.pulse)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundStyle(.yellow, .cyan)
                }
            } else {
                Image(systemName: "star.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.yellow)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("NEW DISCOVERY")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Text(commonName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        .accessibilityAddTraits(.isHeader)
        .onTapGesture {
            dismissEarly()
        }
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.height < 0 {
                        dismissEarly()
                    }
                }
        )
        .onAppear {
            AppTelemetry.trackNewDiscovery(isPro: RevenueCatManager.shared.isProActive)
            HapticManager.shared.triggerSuccessPulse()
            
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "New species discovered! \(commonName)")
            }
            
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        onDismiss()
                    }
                }
            }
        }
    }
    
    private func dismissEarly() {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            onDismiss()
        }
    }
}
