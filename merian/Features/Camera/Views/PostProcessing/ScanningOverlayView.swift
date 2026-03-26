import SwiftUI

// MARK: - Semantic Modal Anchor
// Acts as the global UI isolation layer, completely blacking out the camera viewfinder 
// while presenting the geometric snapshot at a 1:1 ratio.
struct ScanningOverlayView: View {
    // MARK: - Dependencies
    let images: [UIImage]
    let scanningPhaseText: String

    // MARK: - Animation State
    /// Drives a brief micro-scale bounce on the pill each time the phrase updates,
    /// giving physical feedback that new analysis state has arrived.
    @State private var pillScale: CGFloat = 1.0

    // MARK: - View Engine
    var body: some View {
        ZStack {
            // 1. Immutable Canvas Base
            // Darkening layer for maximum neon contrast
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            // 2. Optical Scaler Plane
            HStack(spacing: 4) {
                ForEach(0..<images.count, id: \.self) { index in
                    Image(uiImage: images[index])
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                }
            }
            .aspectRatio(1.0, contentMode: .fit)
            // Perfectly clips the unified images flush to the continuous squircle
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(PremiumScanningOverlay())
            .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 15)
            .padding(.horizontal, 32)

            // 3. Floating Status Pill
            // Displays the dynamic engine checkpoints ("Identifying...", "Extracting context...")
            VStack {
                Text(scanningPhaseText)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 2) // Ensure contrast over complex camera views
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: scanningPhaseText)
                    .scaleEffect(pillScale)
                    .onChange(of: scanningPhaseText) { _, _ in
                        // Pop up then settle — spring physics gives it a natural snap.
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) {
                            pillScale = 1.04
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.1)) {
                            pillScale = 1.0
                        }
                    }
                    .padding(.top, 80)
                
                Spacer()
            }
        }
    }
}

// MARK: - Laser & Orbit Engine
// Renders the specific "Apple Intelligence" aesthetic. Sweeps a hardware-accelerated 
// blendMode(.plusLighter) line over the image while rotating a massive multi-color gradient bloom constraint.
struct PremiumScanningOverlay: View {
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
    var body: some View {
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
    }
}