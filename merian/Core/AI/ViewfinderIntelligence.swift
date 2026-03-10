import Foundation
import CoreImage
import AVFoundation

enum VUIHint: String {
    case tooDark = "Too dark"
    case moveCloser = "Move closer"
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
    
    private init() {}
    
    func analyze(pixelBuffer: CVPixelBuffer, distance: Float?) {
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
            if let dist = distance, dist > 2.5 {
                await self.updateHint(.moveCloser)
                return
            }
            
            // 2. Brightness Heuristic utilizing direct Luma plane extraction purely on CPU
            var brightness: Float = 1.0
            if CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
                CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                
                if let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
                    let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
                    let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
                    let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                    
                    var totalLuma: UInt64 = 0
                    let sampleStep = 10 // Subsample explicitly to keep iteration latency ~0ms
                    var sampleCount = 0
                    
                    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
                    for y in stride(from: 0, to: height, by: sampleStep) {
                        let rowOffset = y * bytesPerRow
                        for x in stride(from: 0, to: width, by: sampleStep) {
                            totalLuma += UInt64(buffer[rowOffset + x])
                            sampleCount += 1
                        }
                    }
                    
                    let averageLuma = sampleCount > 0 ? Float(totalLuma) / Float(sampleCount) : 255.0
                    brightness = averageLuma / 255.0
                }
                
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
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
