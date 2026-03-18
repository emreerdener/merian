import SwiftUI

struct NewDiscoveryCelebrationView: View {
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    
    let commonName: String
    let onDismiss: () -> Void
    
    @State private var showIcon = false
    @State private var showText = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                if showIcon {
                    ZStack {
                        Circle()
                            .fill(Color(white: 0.15))
                            .frame(width: 120, height: 120)
                            .shadow(color: .white.opacity(0.1), radius: 20)
                        
                        // Fallback gracefully on heavy thermal conditions natively
                        if !hardwareOrchestrator.isCriticalHeatWarningActive {
                            if #available(iOS 17.0, *) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.yellow, .cyan)
                                    .symbolEffect(.bounce, value: showIcon)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.yellow, .cyan)
                            }
                        } else {
                            Image(systemName: "star.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.yellow)
                        }
                    }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                
                if showText {
                    VStack(spacing: 12) {
                        Text("New species discovered!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(commonName)
                            .font(.largeTitle)
                            .fontWeight(.black)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .transition(.offset(y: 20).combined(with: .opacity))
                    .accessibilityAddTraits(.isHeader)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .padding(24)
        }
        .allowsHitTesting(false)
        .onAppear {
            AppTelemetry.trackNewDiscovery(isPro: RevenueCatManager.shared.isProActive)
            HapticManager.shared.triggerSuccessPulse()
            
            // Staggered sequence for high-end sleekness
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                showIcon = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) {
                showText = true
            }
            
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "New species discovered! \(commonName)")
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    onDismiss()
                }
            }
        }
    }
}
