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

    /// Runs `VNClassifyImageRequest` on a background thread and immediately starts a
    /// subject-specific phrase rotation — well before the Gemini network call completes.
    /// Phrases progress through subject-relevant details over the typical 6–11 second scan window.
    private func classifySubjectLocally(from data: Data) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let cgImage = UIImage(data: data)?.cgImage else { return }

            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            let phrases = Self.phraseSeries(for: request.results ?? [])

            await MainActor.run { [weak self] in
                guard let self, self.isAnalyzingFullscreen else { return }
                self.startPhaseRotation(phrases: phrases)
            }
        }
    }

    private func startPhaseRotation(phrases: [String]) {
        phaseRotationTask?.cancel()
        phaseRotationTask = Task { @MainActor [weak self] in
            for (index, phrase) in phrases.enumerated() {
                guard !Task.isCancelled, let self else { return }
                self.scanningPhaseText = phrase
                // Don't sleep after the final phrase — let it sit until inference completes.
                guard index < phrases.count - 1 else { return }
                try? await Task.sleep(nanoseconds: 2_300_000_000)
            }
        }
    }

    /// Returns a one-shot phrase series tailored to the top Vision observation.
    /// Each phrase advances ~2.3s apart; the final phrase stays displayed until inference returns.
    /// Series are designed to read as a real analysis pipeline, not a looping animation.
    /// Falls back to a subject-agnostic series if Vision returns no confident observations.
    private nonisolated static func phraseSeries(for observations: [VNClassificationObservation]) -> [String] {
        for obs in observations.prefix(15) where obs.confidence > 0.15 {
            let id = obs.identifier.lowercased()

            if id.contains("bird") || id.contains("avian") || id.contains("raptor") ||
               id.contains("songbird") || id.contains("waterfowl") || id.contains("owl") {
                return [
                    "Spotted avian subject...",
                    "Analyzing plumage and markings...",
                    "Evaluating bill and wing morphology...",
                    "Reviewing seasonal variation patterns...",
                    "Cross-referencing eBird observations...",
                    "Verifying geographic range...",
                    "Checking subspecies distribution...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("insect") || id.contains("arthropod") || id.contains("butterfly") ||
               id.contains("moth") || id.contains("bee") || id.contains("beetle") ||
               id.contains("fly") || id.contains("ant") || id.contains("wasp") ||
               id.contains("dragonfly") || id.contains("cricket") || id.contains("grasshopper") {
                return [
                    "Detected arthropod subject...",
                    "Analyzing wing venation patterns...",
                    "Examining body segmentation...",
                    "Reviewing diagnostic field markers...",
                    "Evaluating taxonomic indicators...",
                    "Consulting entomology records...",
                    "Checking regional distribution data...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("spider") || id.contains("arachnid") || id.contains("scorpion") ||
               id.contains("tick") || id.contains("mite") {
                return [
                    "Detected arachnid subject...",
                    "Analyzing body segmentation...",
                    "Examining appendage morphology...",
                    "Reviewing leg span and spinnerets...",
                    "Checking taxonomic classification...",
                    "Consulting arachnology records...",
                    "Checking regional occurrence records...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("mushroom") || id.contains("fungi") || id.contains("fungus") ||
               id.contains("lichen") {
                return [
                    "Detected fungal specimen...",
                    "Analyzing cap and stipe morphology...",
                    "Examining gill and pore structure...",
                    "Evaluating coloration and texture...",
                    "Reviewing substrate and habitat context...",
                    "Consulting mycology database...",
                    "Checking seasonal fruiting patterns...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("flower") || id.contains("blossom") || id.contains("bloom") {
                return [
                    "Detected flowering plant...",
                    "Analyzing petal arrangement and form...",
                    "Examining reproductive structures...",
                    "Evaluating inflorescence pattern...",
                    "Reviewing pollinator associations...",
                    "Cross-referencing botanical records...",
                    "Checking regional flora records...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("tree") || id.contains("conifer") || id.contains("palm") {
                return [
                    "Detected arboreal subject...",
                    "Analyzing bark texture and pattern...",
                    "Examining leaf shape and arrangement...",
                    "Evaluating growth form...",
                    "Reviewing fruit and seed characteristics...",
                    "Cross-referencing botanical records...",
                    "Checking habitat and elevation range...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("plant") || id.contains("leaf") || id.contains("vegetation") ||
               id.contains("shrub") || id.contains("grass") || id.contains("fern") ||
               id.contains("moss") || id.contains("algae") || id.contains("vine") {
                return [
                    "Detected botanical subject...",
                    "Analyzing leaf morphology...",
                    "Examining venation and margin patterns...",
                    "Evaluating growth habit...",
                    "Reviewing stem and root indicators...",
                    "Consulting flora database...",
                    "Checking native range distribution...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("reptile") || id.contains("snake") || id.contains("lizard") ||
               id.contains("turtle") || id.contains("crocodile") || id.contains("gecko") {
                return [
                    "Detected reptilian subject...",
                    "Analyzing scale patterns and coloration...",
                    "Examining body plan and proportions...",
                    "Reviewing dorsal pattern variation...",
                    "Checking taxonomic classification...",
                    "Cross-referencing herpetology records...",
                    "Checking regional population data...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("amphibian") || id.contains("frog") || id.contains("toad") ||
               id.contains("salamander") || id.contains("newt") || id.contains("caecilian") {
                return [
                    "Detected amphibian subject...",
                    "Analyzing skin texture and markings...",
                    "Examining body form and proportions...",
                    "Evaluating taxonomic indicators...",
                    "Reviewing call and behavioral traits...",
                    "Consulting herpetology database...",
                    "Checking wetland habitat associations...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("fish") || id.contains("shark") || id.contains("ray") ||
               id.contains("eel") || id.contains("salmon") || id.contains("trout") {
                return [
                    "Detected aquatic vertebrate...",
                    "Analyzing fin morphology...",
                    "Examining lateral line and scale patterns...",
                    "Reviewing coloration and spotting patterns...",
                    "Evaluating body shape and proportions...",
                    "Consulting ichthyology records...",
                    "Checking watershed distribution...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("mammal") || id.contains("dog") || id.contains("cat") ||
               id.contains("deer") || id.contains("fox") || id.contains("bear") ||
               id.contains("rabbit") || id.contains("squirrel") || id.contains("raccoon") ||
               id.contains("rodent") || id.contains("primate") {
                return [
                    "Detected mammalian subject...",
                    "Analyzing body proportions...",
                    "Examining pelage and facial features...",
                    "Reviewing behavioral and territorial markers...",
                    "Cross-referencing range data...",
                    "Verifying habitat indicators...",
                    "Checking population range boundaries...",
                    "Awaiting species confirmation...",
                ]
            }
        }

        // Vision returned no confident observations — use a subject-agnostic series that
        // still reads as a meaningful pipeline rather than a generic spinner.
        return [
            "Scanning subject...",
            "Detecting morphological features...",
            "Evaluating biological characteristics...",
            "Analyzing structural patterns...",
            "Cross-referencing taxonomic data...",
            "Querying species databases...",
            "Incorporating location and habitat context...",
            "Awaiting identification...",
        ]
    }
}
