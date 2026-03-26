import SwiftUI
import Vision
import CoreImage

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
                    ZStack {
                        Image(uiImage: images[index])
                            .resizable()
                            .scaledToFill()
                        
                        // Apple Intelligence Saliency Bloom
                        // Overlay the neural glow exclusively onto the primary focal subject
                        if index == 0 {
                            SubjectSaliencyGlowView(sourceImage: images[index])
                        }
                    }
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
                    .font(.system(.callout, weight: .medium))
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
                    .padding(.top, 100)
                
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

// MARK: - Subject Saliency Heatmap
// Extracts the primary subject from the photo using Apple's Vision framework
// and renders it as a breathing neon heatmap.
struct SubjectSaliencyGlowView: View {
    let sourceImage: UIImage
    @State private var saliencyMask: Image?
    @State private var isPulsing = false
    
    var body: some View {
        Group {
            if let mask = saliencyMask {
                mask
                    .resizable()
                    // Scaled to fill perfectly matches the parent image modifier
                    .scaledToFill()
                    // Multiply turns the white heatmap core into vibrant cyan
                    .colorMultiply(.cyan)
                    // Screen blend makes the black non-salient background completely transparent
                    .blendMode(.screen)
                    // Blur the low-res saliency map heavily to create an organic, atmospheric bloom
                    .blur(radius: 20)
                    .opacity(isPulsing ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear {
                        isPulsing = true
                    }
            } else {
                Color.clear
            }
        }
        .task(id: sourceImage) {
            await generateSaliency(from: sourceImage)
        }
    }
    
    private func generateSaliency(from image: UIImage) async {
        guard let cgImage = image.cgImage else { return }
        
        // Use Apple's built-in subject attention classifier
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        
        // Pass the precise image orientation so the Vision pipeline 
        // reads the pixels geographically identically to the screen UI.
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        
        do {
            // Push off the main thread—Vision blocks natively
            try await Task.detached(priority: .userInitiated) {
                try handler.perform([request])
                // Swift 6: Native type inference makes casting redundant
                if let results = request.results,
                   let result = results.first {
                    let pixelBuffer = result.pixelBuffer
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    
                    // Swift 6: Instantiate CIContext strictly within the detached task to avoid @MainActor isolation crossing
                    let localContext = CIContext(options: [.cacheIntermediates: false])
                    
                    // Generate hardware-accelerated static bitmap
                    if let cgResult = localContext.createCGImage(ciImage, from: ciImage.extent) {
                        // Crucially format the result BACK to the origin UIImage orientation 
                        // so it perfectly aligns physically over the photo array layout.
                        let resultImg = UIImage(cgImage: cgResult, scale: 1.0, orientation: image.imageOrientation)
                        await MainActor.run {
                            self.saliencyMask = Image(uiImage: resultImg)
                        }
                    }
                }
            }.value
        } catch {
            print("Vision Saliency Extraction Error: \(error)")
        }
    }
}

// MARK: - CGImagePropertyOrientation Translation Matcher
extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}