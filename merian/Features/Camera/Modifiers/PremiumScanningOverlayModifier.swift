import SwiftUI

// MARK: - Laser & Orbit Engine
// Renders the specific "Apple Intelligence" aesthetic. Sweeps a hardware-accelerated 
// blendMode(.plusLighter) line over the image while rotating a massive multi-color gradient bloom constraint.

public struct PremiumScanningOverlayModifier: ViewModifier {
    // MARK: - Animation State
    @State private var scanOffset: CGFloat = -0.2
    @State private var gradientRotation: Double = 0.0
    @State private var isPulsing: Bool = false
    
    // MARK: - Layout Assets
    // Premium AI Colors (Siri/Apple Intelligence aesthetic)
    private let premiumGradient = Gradient(colors: [
        .cyan, .blue, .indigo, .purple, .pink, .purple, .indigo, .blue, .cyan
    ])
    
    // MARK: - Rendering Physics
    public func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geometry in
                ZStack {
                    // Symmetrical Precision Laser Sweep
                    VStack(spacing: 0) {
                        // Leading soft glow
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .cyan.opacity(0.3)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                        
                        // The hot laser core
                        Rectangle()
                            .fill(Color.white)
                            .frame(height: 1.5)
                            .shadow(color: .cyan, radius: 4)
                            
                        // Trailing soft glow
                        LinearGradient(
                            gradient: Gradient(colors: [.cyan.opacity(0.3), .clear]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                    }
                    .offset(y: scanOffset * geometry.size.height)
                    // blendMode physically interacts with the image pixels underneath, illuminating them
                    .blendMode(.plusLighter)
                }
                // MARK: - Hardware Sequences
                // Infinite non-blocking animation hooks mapped natively on appearance.
                .onAppear {
                    // A slightly slower sweep feels more methodical and premium
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                        scanOffset = 1.0
                    }
                    withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
                        gradientRotation = 360.0
                    }
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                ZStack {
                    // LAYER A: The heavily blurred outer glow (OLED bloom)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AngularGradient(
                                gradient: premiumGradient,
                                center: .center,
                                angle: .degrees(gradientRotation)
                            ),
                            lineWidth: 6
                        )
                        .blur(radius: 8)
                        .opacity(isPulsing ? 0.6 : 0.2)
                    
                    // LAYER B: The razor-thin crisp core line
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AngularGradient(
                                gradient: premiumGradient,
                                center: .center,
                                angle: .degrees(gradientRotation)
                            ),
                            lineWidth: 1.5 // Much thinner, elegant border
                        )
                        .opacity(0.9)
                }
            )
            .allowsHitTesting(false)
        )
    }
}

public extension View {
    func premiumScanningOverlay() -> some View {
        modifier(PremiumScanningOverlayModifier())
    }
}
