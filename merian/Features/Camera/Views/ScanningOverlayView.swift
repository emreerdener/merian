import SwiftUI

struct ScanningOverlayView: View {
    let uiImage: UIImage
    let scanningPhaseText: String
    
    var body: some View {
        ZStack {
            // Base darkening layer, slightly darker for maximum neon contrast
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .aspectRatio(1.0, contentMode: .fit)
                // Perfectly clips the image flush to the continuous squircle
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(PremiumScanningOverlay()) 
                .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 15)
                .padding(.horizontal, 32)
            
            VStack {
                // Refined Text Pill
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                        .symbolEffect(.variableColor) 
                    
                    Text(scanningPhaseText)
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                // Microscopic inner rim to simulate a physical glass edge
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                .padding(.top, 80)
                
                Spacer()
            }
        }
    }
}

struct PremiumScanningOverlay: View {
    @State private var scanOffset: CGFloat = -0.2
    @State private var gradientRotation: Double = 0.0
    @State private var isPulsing: Bool = false
    
    // Premium AI Colors (Siri/Apple Intelligence aesthetic)
    private let premiumGradient = Gradient(colors: [
        .cyan, .blue, .indigo, .purple, .pink, .purple, .indigo, .blue, .cyan
    ])
    
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