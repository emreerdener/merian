import Foundation
import CoreImage
import AVFoundation

enum VUIHint: String {
    case tooDark = "Too Dark"
    case moveCloser = "Move Closer"
    case optimal = "Optimal"
}

/// Viewfinder Intelligence (VUI) Manager
/// Evaluates incoming camera buffers asynchronously utilizing CoreImage statistics to prevent wasted AI inference API calls on flawed imagery.
@MainActor
final class ViewfinderIntelligence: ObservableObject {
    static let shared = ViewfinderIntelligence()
    
    @Published var currentHint: VUIHint = .optimal
    @Published var isOptimal: Bool = true
    
    private var isAnalyzing = false
    private let context = CIContext(options: [.workingColorSpace: NSNull()])
    
    private init() {}
    
    func analyze(pixelBuffer: CVPixelBuffer, distance: Float) {
        // Drop frames instantly if we're currently processing one to maintain zero latency in the viewfinder
        guard !isAnalyzing else { return }
        isAnalyzing = true
        
        // Push heavy CoreImage statistics completely off the Main Thread
        Task.detached(priority: .userInitiated) {
            defer {
                Task { @MainActor in self.isAnalyzing = false }
            }
            
            // 1. Distance Heuristic
            // Standard botanical / biological subjects normally sit below 2.5 meters.
            if distance > 2.5 {
                await self.updateHint(.moveCloser)
                return
            }
            
            // 2. Brightness Heuristic utilizing Core Image native hardware-acceleration
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return }
            avgFilter.setValue(ciImage, forKey: kCIInputImageKey)
            avgFilter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
            
            var brightness: Float = 1.0
            if let outputImage = avgFilter.outputImage {
                var bitmap = [UInt8](repeating: 0, count: 4)
                self.context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
                
                let r = Float(bitmap[0])
                let g = Float(bitmap[1])
                let b = Float(bitmap[2])
                // Standard Relative Luminance formula mapping identically to visual perception models
                brightness = (r * 0.299 + g * 0.587 + b * 0.114) / 255.0
            }
            
            // Strict threshold rejecting lighting boundaries before Gemini processing
            if brightness < 0.20 {
                await self.updateHint(.tooDark)
                return
            }
            
            // All checks passed
            await self.updateHint(.optimal)
        }
    }
    
    private func updateHint(_ hint: VUIHint) async {
        await MainActor.run {
            self.currentHint = hint
            self.isOptimal = (hint == .optimal)
        }
    }
}
