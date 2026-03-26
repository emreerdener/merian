import SwiftUI

struct CelebrationBanner: View {
    let commonName: String
    @Binding var showCelebration: Bool
    
    var body: some View {
        if showCelebration {
            NewDiscoveryCelebrationView(
                commonName: commonName,
                onDismiss: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showCelebration = false
                    }
                }
            )
            // 32pt places the banner natively at the top of the header, exactly where the Confidence Badge sits
            .padding(.top, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(100)
        }
    }
}

// MARK: - Internal Animated Discovery Pill
private struct NewDiscoveryCelebrationView: View {
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    
    let commonName: String
    let onDismiss: () -> Void
    
    @State private var dismissTask: Task<Void, Never>?
    @State private var hasFiredDiscoveryEvent = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 24))
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("New discovery")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Added to your scans")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
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
            if !hasFiredDiscoveryEvent {
                hasFiredDiscoveryEvent = true
                AppTelemetry.trackNewDiscovery(isPro: RevenueCatManager.shared.isProActive)
            }
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
