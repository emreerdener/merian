import Foundation
import CoreImage
import AVFoundation
import Observation

// MARK: - Viewfinder Constants
enum VUIHint: String {
    case tooDark = "Too dark"
    case moveCloser = "Move closer"
    case optimal = "Optimal"
}

// MARK: - Core Artificial Intelligence Engine
/// Viewfinder Intelligence (VUI) Manager
/// Evaluates incoming camera buffers asynchronously utilizing CoreImage statistics to prevent wasted AI inference API calls on flawed imagery.
@MainActor
@Observable final class ViewfinderIntelligence {
    // MARK: - Singleton Architecture
    static let shared = ViewfinderIntelligence()
    
    // MARK: - State Management
    var currentHint: VUIHint = .optimal
    var isOptimal: Bool = true
    
    // MARK: - Asynchronous Trackers
    private var isAnalyzing = false
    private var pauseUntil: Date = .distantPast
    
    // MARK: - Lifecycle Bootstrapping
    private init() {}
    
    // MARK: - Analysis Controls
    func pauseAnalysis(for duration: TimeInterval) {
        pauseUntil = Date().addingTimeInterval(duration)
        Task { await updateHint(.optimal) }
    }
    
    func analyze(brightness: Float, distance: Float?) {
        guard Date() > pauseUntil else { return }
        
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
            // (Extracted synchronously in CameraManager to prevent asynchronous EXC_BAD_ACCESS CVPixelBuffer memory recycling crashes)
            
            // Strict threshold rejecting lighting boundaries before Gemini processing
            if brightness < 0.20 {
                await self.updateHint(.tooDark)
                return
            }
            
            // All checks passed
            await self.updateHint(.optimal)
        }
    }
    
    // MARK: - Property Mutators
    private func updateHint(_ hint: VUIHint) async {
        await MainActor.run {
            if self.currentHint != hint {
                self.currentHint = hint
            }
            let newOptimalState = (hint == .optimal)
            if self.isOptimal != newOptimalState {
                self.isOptimal = newOptimalState
            }
        }
    }
}
