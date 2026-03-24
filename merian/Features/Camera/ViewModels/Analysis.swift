import SwiftUI
import SwiftData
import Vision

extension CameraViewModel {

    // MARK: - Submit Active Scan

    /// Kicks off the inference pipeline for the accumulated `activeScanImages`.
    ///
    /// Call order:
    /// 1. Snapshot images into the analysis overlay and show fullscreen scanning UI.
    /// 2. Await the pre-fetched `EnvironmentContext` (started at shutter press) to build telemetry.
    /// 3. Clear the staging buffers so the user cannot double-submit.
    /// 4. Fire `InferenceEngine.analyze` — `handleInferenceProcessingChange` will dismiss the overlay when done.
    func submitActiveScan(modelContext: ModelContext) {
        guard !activeScannedDatas.isEmpty else { return }

        // 1. Move staged images into the overlay and surface the scanning fullscreen view.
        analysisImages = activeScanImages
        isAnalyzingFullscreen = true
        scanningPhaseText = "Analyzing subject..."

        // 2. Capture the context needed for inference before clearing the staging buffers.
        let datasToAnalyze = activeScannedDatas
        let capturedOriginals = activeOriginals
        let capturedPreFetchTask = preFetchTask

        // 3. Clear the staging buffers immediately so the UI resets behind the overlay.
        activeScanImages.removeAll()
        activeScannedDatas.removeAll()
        activeOriginals.removeAll()
        preFetchTask = nil

        // 4. Fire on-device Vision classification concurrently — updates the status pill
        //    before the network round-trip completes (Vision typically responds in <100ms).
        if let firstData = datasToAnalyze.first {
            classifySubjectLocally(from: firstData)
        }

        Task {
            // 5. Resolve the pre-fetched environment context (started at shutter press).
            let resolvedContext = await capturedPreFetchTask?.value

            // Build telemetry — prefer the pre-fetched context; fall back to the
            // historical context baked into the first gallery original if present.
            let telemetry: CaptureTelemetry
            if let context = resolvedContext {
                telemetry = CaptureTelemetry(
                    from: context,
                    distance: diContainer.cameraManager.subjectDistanceInMeters
                )
            } else if let historicalContext = capturedOriginals.first?.environmentContext {
                telemetry = CaptureTelemetry(
                    from: historicalContext,
                    distance: nil
                )
            } else {
                telemetry = CaptureTelemetry(
                    subjectDistanceInMeters: diContainer.cameraManager.subjectDistanceInMeters,
                    gpsLatitude: nil,
                    gpsLongitude: nil,
                    gpsElevation: nil,
                    locationName: nil,
                    weatherCondition: nil,
                    weatherTemperatureF: nil,
                    timeOfDay: nil,
                    timestamp: DateUtilities.iso8601Formatter.string(from: Date())
                )
            }

            // 6. Fire the inference pipeline.
            await MainActor.run {
                diContainer.inferenceEngine.analyze(
                    imageDatas: datasToAnalyze,
                    telemetry: telemetry,
                    modelContext: modelContext
                )
            }
        }
    }

    // MARK: - Inference Processing Change

    /// Responds to changes in `InferenceEngine.isProcessing`.
    ///
    /// When processing completes (false), dismisses the fullscreen overlay and
    /// surfaces the insight sheet if the engine produced a result.
    func handleInferenceProcessingChange(isStillProcessing: Bool) {
        guard !isStillProcessing else { return }
        isAnalyzingFullscreen = false
        if diContainer.inferenceEngine.speciesData != nil {
            activeSheet = .insight
        }
    }

    // MARK: - Analysis State Synchronization

    /// Responds to changes in `isAnalyzingFullscreen`.
    ///
    /// Cleans up overlay state when the fullscreen scanning view is dismissed.
    func synchronizeAnalysisState(isFullscreen: Bool) {
        guard !isFullscreen else { return }
        phaseRotationTask?.cancel()
        phaseRotationTask = nil
        analysisImages.removeAll()
        scanningPhaseText = "Analyzing subject..."
    }

    // MARK: - On-Device Subject Classification

    /// Runs `VNClassifyImageRequest` on a background thread and updates `scanningPhaseText`
    /// as soon as the on-device model responds — well before the Gemini network call completes.
    /// If Vision can't identify the subject, starts the fallback phrase rotation instead.
    private func classifySubjectLocally(from data: Data) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let cgImage = UIImage(data: data)?.cgImage else { return }

            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            let observations = request.results ?? []
            let phaseText = Self.phaseText(for: observations)

            await MainActor.run { [weak self] in
                guard let self, self.isAnalyzingFullscreen else { return }
                if phaseText == Self.fallbackPhrase {
                    self.startPhaseRotation()
                } else {
                    self.phaseRotationTask?.cancel()
                    self.phaseRotationTask = nil
                    self.scanningPhaseText = phaseText
                }
            }
        }
    }

    private nonisolated static let fallbackPhrase = "Analyzing subject..."

    private static let rotatingFallbackPhrases: [String] = [
        "Analyzing subject...",
        "Identifying species...",
        "Examining details...",
        "Evaluating features...",
        "Consulting field guide...",
    ]

    private func startPhaseRotation() {
        phaseRotationTask?.cancel()
        var index = 0
        phaseRotationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.scanningPhaseText = CameraViewModel.rotatingFallbackPhrases[index]
                index = (index + 1) % CameraViewModel.rotatingFallbackPhrases.count
                try? await Task.sleep(nanoseconds: 2_300_000_000)
            }
        }
    }

    private nonisolated static func phaseText(for observations: [VNClassificationObservation]) -> String {
        for obs in observations.prefix(15) where obs.confidence > 0.15 {
            let id = obs.identifier.lowercased()
            if id.contains("insect") || id.contains("arthropod") || id.contains("butterfly") ||
               id.contains("moth") || id.contains("bee") || id.contains("beetle") ||
               id.contains("spider") || id.contains("arachnid") { return "Examining insect..." }
            if id.contains("bird") { return "Examining bird..." }
            if id.contains("mammal") || id.contains("dog") || id.contains("cat") ||
               id.contains("deer") || id.contains("fox") || id.contains("bear") { return "Examining mammal..." }
            if id.contains("reptile") || id.contains("snake") || id.contains("lizard") ||
               id.contains("turtle") { return "Examining reptile..." }
            if id.contains("amphibian") || id.contains("frog") || id.contains("toad") ||
               id.contains("salamander") { return "Examining amphibian..." }
            if id.contains("fish") { return "Examining fish..." }
            if id.contains("mushroom") || id.contains("fungi") || id.contains("fungus") { return "Examining fungi..." }
            if id.contains("flower") || id.contains("blossom") { return "Examining flower..." }
            if id.contains("tree") { return "Examining tree..." }
            if id.contains("plant") || id.contains("leaf") || id.contains("vegetation") ||
               id.contains("shrub") || id.contains("grass") || id.contains("fern") { return "Examining plant..." }
        }
        return fallbackPhrase
    }
}
