import Foundation

/// Owns the ephemeral on-device analysis session that enriches foreground
/// scanning copy. The coordinator never owns durable inference, persistence,
/// or presentation identity; `InferenceEngine` supplies an exact-session
/// predicate before any result can be published.
@MainActor
final class InferenceLocalAnalysisCoordinator {
    struct Session: Sendable, Equatable {
        let scanId: String?
        let attemptGeneration: UUID
        let foregroundGeneration: UUID?
    }

    struct Dependencies {
        let classifier: any VisionSubjectClassifying
        let traitExtractor: any LocalVisualTraitExtracting
        let foundationCueProvider: any FoundationVisualCueProviding
        let foundationCueEligibilityChecker:
            any FoundationVisualCueEligibilityChecking
        let phraseSleeper: any ScanningPhraseSleeping
        let startFeedback: @MainActor () -> Void
    }

    private struct SessionContext {
        let session: Session
        let isCurrent: @MainActor (Session) -> Bool
        let publishPhrase: @MainActor (String) -> Void
    }

    private let dependencies: Dependencies

    private var activeContext: SessionContext?
    private var classificationTask: Task<Void, Never>?
    private var traitTask: Task<Void, Never>?
    private var foundationCueTask: Task<Void, Never>?
    private var phraseRotationTask: Task<Void, Never>?
    private var analysisImage: ImageDownsampler.SendableImage?
    private var visionClassification: VisionSubjectClassification?
    private var didFinishVisionClassification = false
    private var didSendInferenceRequestBody = false
    private var isPausedForInactivity = false
    private var phraseCoordinator = ScanningPhraseCoordinator()

    #if DEBUG
    private var progressiveAnalyzingStep = 0
    #endif

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// Starts one local visual session. Image preparation and model work remain
    /// independent of the remote request and are never awaited by it.
    @discardableResult
    func start(
        imageData: Data,
        focusRegion: NormalizedImageFocusRegion?,
        session: Session,
        isCurrent: @escaping @MainActor (Session) -> Bool,
        publishPhrase: @escaping @MainActor (String) -> Void
    ) -> Task<Void, Never> {
        cancel()
        activeContext = SessionContext(
            session: session,
            isCurrent: isCurrent,
            publishPhrase: publishPhrase
        )
        publishPhrase(phraseCoordinator.reset())
        startPhraseRotation()
        dependencies.startFeedback()

        let classifier = dependencies.classifier
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let image = await LocalVisualAnalysisImageBuilder.makeImage(
                data: imageData,
                focusRegion: focusRegion
            ),
                !Task.isCancelled,
                self?.isSessionCurrent(session) == true else {
                return
            }

            let classification: VisionSubjectClassification
            do {
                classification = try await classifier.classify(image: image)
            } catch {
                guard !Task.isCancelled else { return }
                classification = VisionSubjectClassification(
                    category: nil,
                    candidates: []
                )
            }

            guard !Task.isCancelled,
                  let self,
                  self.isSessionCurrent(session) else {
                return
            }
            self.analysisImage = image
            self.visionClassification = classification
            self.didFinishVisionClassification = true

            if let category = classification.category,
               let context = self.activeContext {
                context.publishPhrase(
                    self.phraseCoordinator.promote(to: category)
                )
                self.startPhraseRotation()
            }
            self.startFoundationCuesIfReady(session: session)
            self.startTraits(
                image: image,
                classification: classification,
                session: session
            )
        }
        classificationTask = task
        return task
    }

    /// Opens the optional richer-cue stage only after transport confirms that
    /// the request body has left the device.
    func markInferenceRequestBodySent(for session: Session) {
        guard isSessionCurrent(session) else { return }
        didSendInferenceRequestBody = true
        startFoundationCuesIfReady(session: session)
    }

    var handoffPhraseDeck: [String] {
        phraseCoordinator.handoffPhraseDeck
    }

    func cancel(resetPhraseCoordinator: Bool = true) {
        cancelTasksAndAnalysisState()
        activeContext = nil
        isPausedForInactivity = false
        if resetPhraseCoordinator {
            _ = phraseCoordinator.reset()
        }
    }

    /// App inactivity stops all model work and cadence. Only an exact active
    /// visual presentation may retain enough context to resume its cadence.
    func pauseForInactivity(canResume: Bool) {
        if isPausedForInactivity {
            guard canResume,
                  activeContext.map({ $0.isCurrent($0.session) }) == true else {
                isPausedForInactivity = false
                activeContext = nil
                return
            }
            return
        }

        let shouldResume = phraseRotationTask != nil
            && canResume
            && activeContext.map { $0.isCurrent($0.session) } == true
        cancelTasksAndAnalysisState()
        isPausedForInactivity = shouldResume
        if !shouldResume {
            activeContext = nil
        }
    }

    func resumeAfterInactivity(canResume: Bool) {
        guard isPausedForInactivity else { return }
        isPausedForInactivity = false
        guard canResume,
              let context = activeContext,
              context.isCurrent(context.session) else {
            activeContext = nil
            return
        }
        startPhraseRotation()
    }

    private func startTraits(
        image: ImageDownsampler.SendableImage,
        classification: VisionSubjectClassification,
        session: Session
    ) {
        traitTask?.cancel()
        let extractor = dependencies.traitExtractor
        traitTask = Task(priority: .utility) { [weak self] in
            let extractedCues = await extractor.extractCues(from: image)
            guard !Task.isCancelled,
                  let self,
                  self.isSessionCurrent(session) else {
                return
            }

            self.traitTask = nil
            let forbiddenIdentityTerms =
                FoundationVisualCueValidator.identityTerms(
                    from: classification.candidates
                )
            for extractedCue in extractedCues {
                guard let cue = FoundationVisualCueValidator.validatedCue(
                    extractedCue,
                    forbiddenIdentityTerms: forbiddenIdentityTerms,
                    existingPhrases:
                        self.phraseCoordinator.acceptedLocalTraitPhrases
                ) else {
                    continue
                }
                _ = self.phraseCoordinator.acceptLocalTraitCue(cue)
            }
        }
    }

    private func startFoundationCuesIfReady(session: Session) {
        guard foundationCueTask == nil,
              didSendInferenceRequestBody,
              didFinishVisionClassification,
              dependencies.foundationCueEligibilityChecker
                  .isEligibleForVisualCues(),
              let image = analysisImage,
              isSessionCurrent(session) else {
            return
        }

        let classification = visionClassification
            ?? VisionSubjectClassification(category: nil, candidates: [])
        let request = FoundationVisualCueRequest(
            image: image,
            broadCategory: classification.category,
            forbiddenIdentityTerms:
                FoundationVisualCueValidator.identityTerms(
                    from: classification.candidates
                )
        )
        let provider = dependencies.foundationCueProvider
        let eligibilityChecker =
            dependencies.foundationCueEligibilityChecker

        foundationCueTask = Task(priority: .utility) { [weak self] in
            do {
                guard let snapshots = try await provider.cueSnapshots(
                    for: request
                ) else {
                    return
                }
                var buffer = FoundationVisualCueBuffer()
                var acceptedCount = 0

                for try await snapshot in snapshots {
                    guard !Task.isCancelled,
                          let self,
                          self.isSessionCurrent(session),
                          eligibilityChecker.isEligibleForVisualCues() else {
                        return
                    }
                    guard let bufferedCue = buffer.consume(snapshot),
                          let cue = FoundationVisualCueValidator.validatedCue(
                              bufferedCue,
                              forbiddenIdentityTerms:
                                  request.forbiddenIdentityTerms,
                              existingPhrases:
                                  self.phraseCoordinator
                                      .acceptedFoundationPhrases.union(
                                          self.phraseCoordinator
                                              .acceptedLocalTraitPhrases
                                      )
                          ),
                          self.phraseCoordinator.acceptFoundationCue(cue) else {
                        continue
                    }
                    acceptedCount += 1
                    if acceptedCount
                        == FoundationVisualCueRequest.maximumCueCount {
                        return
                    }
                }
            } catch {
                // Local cues are best-effort and intentionally have no
                // user-visible error.
            }
        }
    }

    private func startPhraseRotation() {
        phraseRotationTask?.cancel()
        guard let context = activeContext else { return }
        let sleeper = dependencies.phraseSleeper
        phraseRotationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleeper.sleepUntilNextPhrase()
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      let self,
                      self.activeContext?.session == context.session,
                      context.isCurrent(context.session) else {
                    return
                }
                if let nextPhrase = self.phraseCoordinator.nextPhrase() {
                    context.publishPhrase(nextPhrase)
                }
            }
        }
    }

    private func isSessionCurrent(_ session: Session) -> Bool {
        guard let context = activeContext,
              context.session == session else {
            return false
        }
        return context.isCurrent(session)
    }

    private func cancelTasksAndAnalysisState() {
        classificationTask?.cancel()
        traitTask?.cancel()
        foundationCueTask?.cancel()
        phraseRotationTask?.cancel()
        classificationTask = nil
        traitTask = nil
        foundationCueTask = nil
        phraseRotationTask = nil
        analysisImage = nil
        visionClassification = nil
        didFinishVisionClassification = false
        didSendInferenceRequestBody = false
    }

    #if DEBUG
    func startDebugProgression(
        session: Session,
        automaticallyAdvances: Bool,
        isCurrent: @escaping @MainActor (Session) -> Bool,
        publishPhrase: @escaping @MainActor (String) -> Void
    ) {
        cancel()
        activeContext = SessionContext(
            session: session,
            isCurrent: isCurrent,
            publishPhrase: publishPhrase
        )
        publishPhrase(phraseCoordinator.reset())
        progressiveAnalyzingStep = 0
        guard automaticallyAdvances else { return }

        let sleeper = dependencies.phraseSleeper
        phraseRotationTask = Task { @MainActor [weak self] in
            do {
                try await sleeper.sleepUntilNextPhrase()
                guard !Task.isCancelled, let self else { return }
                self.advanceDebugProgression()

                try await sleeper.sleepUntilNextPhrase()
                guard !Task.isCancelled else { return }
                self.advanceDebugProgression()
            } catch {
                return
            }
        }
    }

    func advanceDebugProgression() {
        guard let context = activeContext else { return }
        switch progressiveAnalyzingStep {
        case 0:
            context.publishPhrase(
                phraseCoordinator.promote(to: .arthropod)
            )
            progressiveAnalyzingStep = 1
        case 1:
            let cue = FoundationVisualCue(
                kind: .colorPattern,
                detail: "amber banded wings"
            )
            guard phraseCoordinator.acceptLocalTraitCue(cue),
                  let phrase = phraseCoordinator.nextPhrase() else {
                return
            }
            context.publishPhrase(phrase)
            progressiveAnalyzingStep = 2
        default:
            break
        }
    }

    func startDebugFoundationCueStream(
        image: ImageDownsampler.SendableImage,
        classification: VisionSubjectClassification,
        session: Session,
        isCurrent: @escaping @MainActor (Session) -> Bool,
        publishPhrase: @escaping @MainActor (String) -> Void
    ) {
        cancel()
        activeContext = SessionContext(
            session: session,
            isCurrent: isCurrent,
            publishPhrase: publishPhrase
        )
        publishPhrase(phraseCoordinator.reset())
        if let category = classification.category {
            publishPhrase(phraseCoordinator.promote(to: category))
        }
        analysisImage = image
        visionClassification = classification
        didFinishVisionClassification = true
        didSendInferenceRequestBody = true
        startPhraseRotation()
        startFoundationCuesIfReady(session: session)
    }

    func waitForFoundationCueStream() async {
        await foundationCueTask?.value
    }

    func waitForTraits() async {
        await traitTask?.value
    }

    var acceptedFoundationPhraseCount: Int {
        phraseCoordinator.acceptedFoundationPhrases.count
    }

    var localVisionCategory: LocalSubjectCategory? {
        visionClassification?.category
    }

    var isRunning: Bool {
        classificationTask != nil || traitTask != nil
            || foundationCueTask != nil || phraseRotationTask != nil
    }

    var isTraitExtractionRunning: Bool {
        traitTask != nil
    }
    #endif
}
