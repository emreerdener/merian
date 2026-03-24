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
        updateHint(.optimal)
    }
    
    func analyze(brightness: Float, distance: Float?, lumaStdDev: Float) {
        guard Date() > pauseUntil else { return }

        // Drop frames instantly if we're currently processing one to maintain zero latency.
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        // All checks are pure float comparisons — no I/O, no heavy CPU work.
        // Running directly on @MainActor (the caller already dispatches here via
        // Task { @MainActor in }) eliminates the Task.detached + nested defer-Task
        // allocation chain that previously cost 3 Task heap objects per frame at 3 Hz.

        // 1. Distance heuristics
        if let dist = distance, dist > 3.0 {
            updateHint(.moveCloser); return
        }
        if let dist = distance, dist < 0.12 {
            updateHint(.tooClose); return
        }

        // 2. Exposure heuristics
        // (Brightness extracted synchronously in CameraManager to prevent async
        //  EXC_BAD_ACCESS from CVPixelBuffer memory recycling.)
        if brightness < 0.20 {
            updateHint(.tooDark); return
        }
        if brightness > 0.88 {
            updateHint(.tooBright); return
        }

        // 3. Sharpness — low luma variance indicates motion blur or insufficient detail
        if lumaStdDev < 20.0 {
            updateHint(.holdStill); return
        }

        // All checks passed
        updateHint(.optimal)
    }

    // MARK: - Property Mutators
    private func updateHint(_ hint: VUIHint) {
        if currentHint != hint { currentHint = hint }
        let newOptimalState = (hint == .optimal)
        if isOptimal != newOptimalState { isOptimal = newOptimalState }
    }
}
