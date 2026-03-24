import Foundation
import CoreImage
import AVFoundation
import Observation

// MARK: - Viewfinder Constants
enum VUIHint: String {
    case tooDark = "Too dark"
    case tooBright = "Move to shade"
    case tooClose = "Move back"
    case moveCloser = "Move closer"
    case holdStill = "Hold still"
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
    
    func analyze(brightness: Float, distance: Float?, lumaStdDev: Float) {
        guard Date() > pauseUntil else { return }

        // Drop frames instantly if we're currently processing one to maintain zero latency in the viewfinder
        guard !isAnalyzing else { return }
        isAnalyzing = true

        // Push hint evaluation off the main thread. [weak self] prevents a strong capture of
        // the @MainActor-isolated type inside a Task.detached, satisfying Swift 6 isolation rules.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in self?.isAnalyzing = false }
            }

            // 1. Distance heuristics
            if let dist = distance, dist > 3.0 {
                await self.updateHint(.moveCloser)
                return
            }
            if let dist = distance, dist < 0.12 {
                await self.updateHint(.tooClose)
                return
            }

            // 2. Exposure heuristics
            // (Extracted synchronously in CameraManager to prevent asynchronous EXC_BAD_ACCESS CVPixelBuffer memory recycling crashes)
            if brightness < 0.20 {
                await self.updateHint(.tooDark)
                return
            }
            if brightness > 0.88 {
                await self.updateHint(.tooBright)
                return
            }

            // 3. Sharpness heuristic — low luma variance indicates motion blur or insufficient image detail
            if lumaStdDev < 20.0 {
                await self.updateHint(.holdStill)
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
