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
            // Mark a new unread scan only for real results (scanId is nil on error placeholders
            // like "Analysis Failed" / "Network Timeout" which are not persisted to the library).
            if diContainer.inferenceEngine.speciesData?.scanId != nil {
                UserDefaults.standard.set(true, forKey: "hasUnseenScan")
            }
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

    /// Runs `VNClassifyImageRequest` on a background thread and drives the scanning phrase rotation.
    ///
    /// Generic phrases start immediately so the UI is never blank. Vision runs in parallel and
    /// overrides with subject-specific phrases only when it returns a confident (≥ 0.5) match.
    /// Low-confidence or ambiguous results (e.g., broad taxonomy ancestors like "arthropod" scoring
    /// 0.2 for a plant image) leave the generic series running uninterrupted.
    private func classifySubjectLocally(from data: Data) {
        // Start generic phrases immediately — no blank state while Vision runs.
        startPhaseRotation(phrases: Self.genericFallbackPhrases)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let cgImage = UIImage(data: data)?.cgImage else { return }

            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            // specificPhraseSeries returns nil when no observation clears the confidence bar
            // or the margin check fails — generic rotation continues without interruption.
            guard let phrases = Self.specificPhraseSeries(for: request.results ?? []) else { return }

            // Hold for 3 seconds before switching. This ensures the generic series always
            // plays through the first phase of a scan, and subject-specific phrases only
            // appear once the inference call is well underway — reducing how long an
            // incorrect category label is visible if Vision misclassified the subject.
            try? await Task.sleep(nanoseconds: 3_000_000_000)

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

    /// Generic phrases used when Vision has no confident classification.
    /// Also used as the immediate starting point before Vision results arrive.
    private nonisolated static let genericFallbackPhrases: [String] = [
        "Scanning subject...",
        "Detecting morphological features...",
        "Evaluating biological characteristics...",
        "Analyzing structural patterns...",
        "Cross-referencing taxonomic data...",
        "Querying species databases...",
        "Incorporating location and habitat context...",
        "Awaiting identification...",
    ]

    /// Returns subject-specific phrases when Vision identifies a category with ≥ 0.65 confidence
    /// and a clear margin over the second-best observation.
    /// Returns nil when no observation clears the threshold — caller should keep the generic series.
    ///
    /// Only the top 5 observations are checked. The 0.65 threshold and ≥ 0.15 margin guard
    /// prevent cross-category misclassification (e.g., a plant briefly scoring 0.51 "bird")
    /// from surfacing subject-specific phrases that would be jarring or incorrect.
    private nonisolated static func specificPhraseSeries(for observations: [VNClassificationObservation]) -> [String]? {
        // Require a clear lead over the second-best result to filter split/ambiguous classifications.
        if observations.count >= 2 {
            guard observations[0].confidence - observations[1].confidence >= 0.15 else { return nil }
        }

        for obs in observations.prefix(5) where obs.confidence >= 0.65 {
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
            if id.contains("cactus") || id.contains("cactaceae") || id.contains("succulent") {
                return [
                    "Detected succulent subject...",
                    "Analyzing spine and areole patterns...",
                    "Examining stem morphology and rib structure...",
                    "Evaluating growth form and branching...",
                    "Reviewing surface texture and coloration...",
                    "Consulting flora database...",
                    "Checking native range distribution...",
                    "Awaiting species confirmation...",
                ]
            }
            if id.contains("plant") || id.contains("leaf") || id.contains("vegetation") ||
               id.contains("shrub") || id.contains("grass") || id.contains("fern") ||
               id.contains("moss") || id.contains("algae") || id.contains("vine") {
                return [
                    "Detected botanical subject...",
                    "Analyzing morphological features...",
                    "Examining structural patterns...",
                    "Evaluating growth habit...",
                    "Reviewing diagnostic field markers...",
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

        // No observation cleared the confidence threshold — caller keeps the generic series.
        return nil
    }
}
