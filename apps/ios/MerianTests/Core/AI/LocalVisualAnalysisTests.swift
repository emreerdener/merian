import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import Merian

private struct AlwaysEligibleFoundationCueChecker: FoundationVisualCueEligibilityChecking {
    @MainActor
    func isEligibleForVisualCues() -> Bool { true }
}

private actor ControlledVisionSubjectClassifier: VisionSubjectClassifying {
    private let result: VisionSubjectClassification
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var started = false

    init(result: VisionSubjectClassification) {
        self.result = result
    }

    func classify(
        image _: ImageDownsampler.SendableImage
    ) async throws -> VisionSubjectClassification {
        started = true
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return result
    }

    func complete() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }
}

private actor ControlledScanningPhraseClock: ScanningPhraseSleeping {
    private var tick = 0
    private var waitingCount = 0
    private var sleepCallCount = 0

    func sleepUntilNextPhrase() async throws {
        let targetTick = tick + 1
        sleepCallCount += 1
        waitingCount += 1
        defer { waitingCount -= 1 }
        while tick < targetTick {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    func advance() {
        tick += 1
    }

    func waitUntilWaiting() async {
        while waitingCount == 0 {
            await Task.yield()
        }
    }

    func waitUntilSleepCallCount(_ expectedCount: Int) async {
        while sleepCallCount < expectedCount {
            await Task.yield()
        }
    }
}

private actor CompletionFlag {
    private var isMarked = false

    var value: Bool { isMarked }

    func mark() {
        isMarked = true
    }
}

private actor ControlledFoundationVisualCueProvider: FoundationVisualCueProviding {
    private var continuation:
        AsyncThrowingStream<FoundationVisualCueSnapshot, Error>.Continuation?
    private var started = false
    private var terminated = false

    func cueSnapshots(
        for _: FoundationVisualCueRequest
    ) async throws -> AsyncThrowingStream<FoundationVisualCueSnapshot, Error>? {
        var streamContinuation:
            AsyncThrowingStream<FoundationVisualCueSnapshot, Error>.Continuation?
        let stream = AsyncThrowingStream<FoundationVisualCueSnapshot, Error> { continuation in
            streamContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.markTerminated() }
            }
        }
        continuation = streamContinuation
        started = true
        return stream
    }

    func yield(_ snapshot: FoundationVisualCueSnapshot) {
        continuation?.yield(snapshot)
    }

    func finish(throwing error: Error? = nil) {
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func waitUntilTerminated() async {
        while !terminated {
            await Task.yield()
        }
    }

    private func markTerminated() {
        terminated = true
    }
}

private struct ThrowingFoundationVisualCueProvider: FoundationVisualCueProviding {
    struct ExpectedError: Error {}

    func cueSnapshots(
        for _: FoundationVisualCueRequest
    ) async throws -> AsyncThrowingStream<FoundationVisualCueSnapshot, Error>? {
        throw ExpectedError()
    }
}

@MainActor
@Suite("Local Visual Analysis Tests", .serialized)
struct LocalVisualAnalysisTests {
    @Test func visionResolverEnforcesConfidenceAndMargin() {
        let belowThreshold = VisionSubjectClassificationResolver.resolve(
            candidates: [
                VisionClassificationCandidate(identifier: "bird", confidence: 0.64)
            ],
            confidenceThreshold: 0.65,
            marginThreshold: 0.15
        )
        #expect(belowThreshold.category == nil)

        let narrowMargin = VisionSubjectClassificationResolver.resolve(
            candidates: [
                VisionClassificationCandidate(identifier: "bird", confidence: 0.90),
                VisionClassificationCandidate(identifier: "tree", confidence: 0.80)
            ],
            confidenceThreshold: 0.65,
            marginThreshold: 0.15
        )
        #expect(narrowMargin.category == nil)

        let qualifying = VisionSubjectClassificationResolver.resolve(
            candidates: [
                VisionClassificationCandidate(identifier: "songbird", confidence: 0.90),
                VisionClassificationCandidate(identifier: "tree", confidence: 0.70)
            ],
            confidenceThreshold: 0.65,
            marginThreshold: 0.15
        )
        #expect(qualifying.category == .avian)
    }

    @Test func visionIdentifiersMapToEverySupportedBroadCategory() {
        let expected: [(String, LocalSubjectCategory)] = [
            ("waterfowl", .avian),
            ("dragonfly insect", .arthropod),
            ("orb spider", .arachnid),
            ("mushroom", .fungal),
            ("flower blossom", .floweringPlant),
            ("conifer tree", .tree),
            ("cactaceae", .succulent),
            ("fern plant", .botanical),
            ("gecko reptile", .reptile),
            ("salamander", .amphibian),
            ("shark fish", .fish),
            ("raccoon mammal", .mammal)
        ]

        for (identifier, category) in expected {
            #expect(LocalSubjectCategory(identifier: identifier) == category)
        }
        #expect(LocalSubjectCategory(identifier: "building facade") == nil)
        #expect(LocalSubjectCategory(identifier: "restaurant facade") == nil)
        #expect(LocalSubjectCategory(identifier: "flying fish") == .fish)
        #expect(LocalSubjectCategory(identifier: "flowering plants") == .floweringPlant)
        #expect(LocalSubjectCategory(identifier: "butterflies") == .arthropod)
    }

    @Test func localPhraseDecksAreShortAndDirectlyObservable() {
        let prohibitedTerms = [
            "record", "range", "database", "taxonom", "species", "confidence",
            "match", "identif", "confirm", "habitat"
        ]

        for phrase in ScanningPhraseCoordinator.genericPhrases
            + LocalSubjectCategory.allCases.flatMap(\.phraseSeries) {
            #expect(phrase.count + 3 <= 36)
            let lowercased = phrase.lowercased()
            #expect(!prohibitedTerms.contains(where: lowercased.contains))
        }
    }

    @Test func queuedAndNonVisualPhraseDeckRemainsUnchanged() {
        #expect(InferenceEngine.genericScanningPhasePhrases == [
            "Scanning subject...",
            "Analyzing subject morphology",
            "Analyzing biological traits",
            "Analyzing structural patterns",
            "Checking taxonomic data",
            "Checking species records",
            "Checking habitat context",
            "Identifying species..."
        ])
    }

    @Test func phraseCoordinatorHandsOffImmediatelyAndNeverRegresses() {
        var coordinator = ScanningPhraseCoordinator()
        #expect(coordinator.reset() == "Analyzing subject")
        #expect(coordinator.specificity == .generic)

        let categoryPhrase = coordinator.promote(to: .arthropod)
        #expect(categoryPhrase == "Arthropod form visible")
        #expect(coordinator.specificity == .vision)
        #expect(coordinator.nextPhrase() == "Examining wing veins")

        let cue = FoundationVisualCue(
            kind: .colorPattern,
            detail: "amber banded wings"
        )
        let acceptedCue = coordinator.acceptFoundationCue(cue)
        let acceptedDuplicate = coordinator.acceptFoundationCue(cue)
        let acceptedDuplicateDetail = coordinator.acceptFoundationCue(
            FoundationVisualCue(
                kind: .marking,
                detail: "amber banded wings"
            )
        )
        #expect(acceptedCue)
        #expect(!acceptedDuplicate)
        #expect(!acceptedDuplicateDetail)
        #expect(coordinator.nextPhrase() == "Color: amber banded wings")
        #expect(coordinator.specificity == .foundation)

        #expect(coordinator.promote(to: .avian) == "Color: amber banded wings")
        #expect(coordinator.nextPhrase() == nil)
    }

    @Test func foundationSnapshotsStayBufferedUntilComplete() {
        var buffer = FoundationVisualCueBuffer()
        #expect(buffer.consume(FoundationVisualCueSnapshot(
            index: 0,
            kind: .marking,
            detail: nil,
            isComplete: false
        )) == nil)
        #expect(buffer.consume(FoundationVisualCueSnapshot(
            index: 0,
            kind: nil,
            detail: "two pale bands",
            isComplete: false
        )) == nil)

        let completed = buffer.consume(FoundationVisualCueSnapshot(
            index: 0,
            kind: nil,
            detail: nil,
            isComplete: true
        ))
        #expect(completed == FoundationVisualCue(
            kind: .marking,
            detail: "two pale bands"
        ))
        #expect(buffer.consume(FoundationVisualCueSnapshot(
            index: 0,
            kind: .shape,
            detail: "rounded body",
            isComplete: true
        )) == nil)
    }

    @Test func foundationCueValidationRejectsUnsafeOrUnfitText() {
        let candidates = [
            VisionClassificationCandidate(
                identifier: "monarch butterfly",
                confidence: 0.91
            ),
            VisionClassificationCandidate(
                identifier: "bee",
                confidence: 0.82
            )
        ]
        let forbidden = FoundationVisualCueValidator.identityTerms(from: candidates)
        #expect(forbidden.contains("bee"))

        let valid = FoundationVisualCueValidator.validatedCue(
            FoundationVisualCue(
                kind: .colorPattern,
                detail: "  amber   banded wings "
            ),
            forbiddenIdentityTerms: forbidden
        )
        #expect(valid?.pillText == "Color: amber banded wings")

        let invalidDetails = [
            "amber",
            "one two three four five six",
            "extraordinarily elongated iridescent surface",
            "likely pale bands",
            "butterfly wing pattern",
            "small bee body",
            "moth-like markings",
            "leaf like outline",
            "species match",
            "database lookup pending",
            "identified avian form"
        ]
        for detail in invalidDetails {
            #expect(FoundationVisualCueValidator.validatedCue(
                FoundationVisualCue(kind: .marking, detail: detail),
                forbiddenIdentityTerms: forbidden
            ) == nil)
        }
        #expect(FoundationVisualCueValidator.validatedCue(
            FoundationVisualCue(kind: .marking, detail: "two pale bands"),
            forbiddenIdentityTerms: [],
            existingPhrases: ["marking: two pale bands"]
        ) == nil)
    }

    @Test func runtimeEligibilityRejectsPowerThermalAndLifecycleFallbacks() {
        #expect(FoundationVisualCueRuntimeState(
            isApplicationActive: true,
            isLowPowerModeEnabled: false,
            thermalState: .nominal
        ).isEligible)
        #expect(!FoundationVisualCueRuntimeState(
            isApplicationActive: false,
            isLowPowerModeEnabled: false,
            thermalState: .nominal
        ).isEligible)
        #expect(!FoundationVisualCueRuntimeState(
            isApplicationActive: true,
            isLowPowerModeEnabled: true,
            thermalState: .nominal
        ).isEligible)
        #expect(!FoundationVisualCueRuntimeState(
            isApplicationActive: true,
            isLowPowerModeEnabled: false,
            thermalState: .serious
        ).isEligible)
        #expect(!FoundationVisualCueRuntimeState(
            isApplicationActive: true,
            isLowPowerModeEnabled: false,
            thermalState: .critical
        ).isEligible)
    }

    @Test func currentToolchainFoundationProviderIsSilentFallback() async throws {
        let stream = try await UnavailableFoundationVisualCueProvider().cueSnapshots(
            for: FoundationVisualCueRequest(
                image: try makeImage(),
                broadCategory: .avian,
                forbiddenIdentityTerms: ["bird"]
            )
        )
        #expect(stream == nil)
    }

    @Test func localImageCropUsesTopLeftNormalizedFocusCoordinates() throws {
        let region = NormalizedImageFocusRegion(
            x: 0.10,
            y: 0.20,
            width: 0.40,
            height: 0.50
        )
        let crop = try #require(LocalVisualAnalysisImageBuilder.pixelCropRect(
            focusRegion: region,
            pixelWidth: 500,
            pixelHeight: 400
        ))
        #expect(crop == CGRect(x: 50, y: 80, width: 200, height: 200))
    }

    @Test func enginePublishesVisionCategoryImmediatelyAndRestartsCadence() async throws {
        let classifier = ControlledVisionSubjectClassifier(
            result: VisionSubjectClassification(
                category: .arthropod,
                candidates: [
                    VisionClassificationCandidate(
                        identifier: "insect",
                        confidence: 0.99
                    )
                ]
            )
        )
        let clock = ControlledScanningPhraseClock()
        let engine = InferenceEngine(
            visionSubjectClassifier: classifier,
            scanningPhraseSleeper: clock
        )
        let classificationTask = try #require(
            engine.debugStartLocalClassification(imageData: try makeImageData())
        )
        await classifier.waitUntilStarted()
        await clock.waitUntilSleepCallCount(1)
        #expect(engine.scanningPhaseText == "Analyzing subject")

        await classifier.complete()
        await classificationTask.value
        #expect(engine.scanningPhaseText == "Arthropod form visible")
        await clock.waitUntilSleepCallCount(2)
        #expect(engine.scanningPhaseText == "Arthropod form visible")

        await clock.advance()
        #expect(await eventually {
            engine.scanningPhaseText == "Examining wing veins"
        })
        engine.cancelActiveRequest()
    }

    @Test func enginePublishesOnlyCompleteUniqueFoundationCuesOnClockTicks() async throws {
        let provider = ControlledFoundationVisualCueProvider()
        let clock = ControlledScanningPhraseClock()
        let engine = InferenceEngine(
            foundationVisualCueProvider: provider,
            foundationVisualCueEligibilityChecker:
                AlwaysEligibleFoundationCueChecker(),
            scanningPhraseSleeper: clock
        )
        let image = try makeImage()
        engine.debugStartFoundationCueStream(
            image: image,
            classification: VisionSubjectClassification(
                category: .arthropod,
                candidates: []
            )
        )
        await provider.waitUntilStarted()

        await provider.yield(FoundationVisualCueSnapshot(
            index: 0,
            kind: .colorPattern,
            detail: nil,
            isComplete: false
        ))
        await Task.yield()
        #expect(engine.debugAcceptedFoundationPhraseCount == 0)

        await provider.yield(FoundationVisualCueSnapshot(
            index: 0,
            kind: nil,
            detail: "amber banded wings",
            isComplete: true
        ))
        #expect(await eventually {
            engine.debugAcceptedFoundationPhraseCount == 1
        })
        #expect(engine.scanningPhaseText == "Arthropod form visible")

        await clock.waitUntilWaiting()
        await clock.advance()
        #expect(await eventually {
            engine.scanningPhaseText == "Color: amber banded wings"
        })

        await provider.yield(FoundationVisualCueSnapshot(
            index: 1,
            kind: .marking,
            detail: "amber banded wings",
            isComplete: true
        ))
        await Task.yield()
        #expect(engine.debugAcceptedFoundationPhraseCount == 1)
        await provider.finish()
        engine.cancelActiveRequest()
    }

    @Test func invalidAndThrowingFoundationStreamsRemainSilent() async throws {
        let provider = ControlledFoundationVisualCueProvider()
        let engine = InferenceEngine(
            foundationVisualCueProvider: provider,
            foundationVisualCueEligibilityChecker:
                AlwaysEligibleFoundationCueChecker()
        )
        engine.debugStartFoundationCueStream(
            image: try makeImage(),
            classification: VisionSubjectClassification(category: .avian, candidates: [])
        )
        await provider.waitUntilStarted()
        await provider.yield(FoundationVisualCueSnapshot(
            index: 0,
            kind: .shape,
            detail: "likely bird species",
            isComplete: true
        ))
        await provider.finish()
        await Task.yield()
        #expect(engine.debugAcceptedFoundationPhraseCount == 0)
        engine.cancelActiveRequest()

        let throwingEngine = InferenceEngine(
            foundationVisualCueProvider: ThrowingFoundationVisualCueProvider(),
            foundationVisualCueEligibilityChecker:
                AlwaysEligibleFoundationCueChecker()
        )
        throwingEngine.debugStartFoundationCueStream(
            image: try makeImage(),
            classification: VisionSubjectClassification(category: .avian, candidates: [])
        )
        await Task.yield()
        #expect(throwingEngine.debugAcceptedFoundationPhraseCount == 0)
        throwingEngine.cancelActiveRequest()
    }

    @Test func replacementAndGeminiCompletionFenceHungOrStaleCues() async throws {
        let replacementProvider = ControlledFoundationVisualCueProvider()
        let replacementClock = ControlledScanningPhraseClock()
        let replacementEngine = InferenceEngine(
            foundationVisualCueProvider: replacementProvider,
            foundationVisualCueEligibilityChecker:
                AlwaysEligibleFoundationCueChecker(),
            scanningPhraseSleeper: replacementClock
        )
        replacementEngine.debugStartFoundationCueStream(
            image: try makeImage(),
            classification: VisionSubjectClassification(category: .mammal, candidates: [])
        )
        await replacementProvider.waitUntilStarted()
        replacementEngine.prepareForNewScan()
        await replacementProvider.yield(FoundationVisualCueSnapshot(
            index: 0,
            kind: .marking,
            detail: "two pale bands",
            isComplete: true
        ))
        await Task.yield()
        #expect(replacementEngine.debugAcceptedFoundationPhraseCount == 0)
        #expect(replacementEngine.scanningPhaseText == "Analyzing subject...")

        let hungProvider = ControlledFoundationVisualCueProvider()
        let hungEngine = InferenceEngine(
            foundationVisualCueProvider: hungProvider,
            foundationVisualCueEligibilityChecker:
                AlwaysEligibleFoundationCueChecker()
        )
        hungEngine.debugStartFoundationCueStream(
            image: try makeImage(),
            classification: VisionSubjectClassification(category: .avian, candidates: [])
        )
        await hungProvider.waitUntilStarted()
        let startedAt = ContinuousClock.now
        hungEngine.debugSimulateGeminiResponseArrival()
        let elapsed = startedAt.duration(to: .now)
        #expect(elapsed < .milliseconds(100))
        #expect(!hungEngine.debugLocalVisualAnalysisIsRunning)
        await hungProvider.yield(FoundationVisualCueSnapshot(
            index: 0,
            kind: .marking,
            detail: "two pale bands",
            isComplete: true
        ))
        await Task.yield()
        #expect(hungEngine.debugAcceptedFoundationPhraseCount == 0)
        await hungProvider.waitUntilTerminated()
    }

    @Test func applicationDeactivationCancelsVisionAndPhraseRotation() async throws {
        let classifier = ControlledVisionSubjectClassifier(
            result: VisionSubjectClassification(
                category: .mammal,
                candidates: [
                    VisionClassificationCandidate(
                        identifier: "mammal",
                        confidence: 0.99
                    )
                ]
            )
        )
        let clock = ControlledScanningPhraseClock()
        let engine = InferenceEngine(
            visionSubjectClassifier: classifier,
            scanningPhraseSleeper: clock
        )
        let scanId = "deactivation-local-analysis"
        let attemptGeneration = UUID()
        let networkTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(30))
        }
        engine.inferenceTask = networkTask
        let classificationTask = try #require(
            engine.debugStartLocalClassification(
                imageData: try makeImageData(),
                scanId: scanId,
                attemptGeneration: attemptGeneration
            )
        )
        await classifier.waitUntilStarted()
        await clock.waitUntilWaiting()
        let phaseBeforeDeactivation = engine.scanningPhaseText

        engine.handleApplicationActiveStateChange(isActive: false)

        #expect(!engine.debugLocalVisualAnalysisIsRunning)
        #expect(!networkTask.isCancelled)
        #expect(engine.inferenceTask != nil)
        #expect(engine.activeScanId == scanId)
        #expect(engine.activeLiveInferenceAttemptGeneration == attemptGeneration)
        await classifier.complete()
        await classificationTask.value
        await clock.advance()
        await Task.yield()
        #expect(engine.debugLocalVisionCategory == nil)
        #expect(engine.scanningPhaseText == phaseBeforeDeactivation)
        engine.cancelActiveRequest()
        _ = try? await networkTask.value
    }

    @Test func applicationDeactivationTerminatesFoundationStream() async throws {
        let provider = ControlledFoundationVisualCueProvider()
        let clock = ControlledScanningPhraseClock()
        let engine = InferenceEngine(
            foundationVisualCueProvider: provider,
            foundationVisualCueEligibilityChecker:
                AlwaysEligibleFoundationCueChecker(),
            scanningPhraseSleeper: clock
        )
        engine.debugStartFoundationCueStream(
            image: try makeImage(),
            classification: VisionSubjectClassification(
                category: .avian,
                candidates: []
            )
        )
        await provider.waitUntilStarted()
        await clock.waitUntilWaiting()
        let phaseBeforeDeactivation = engine.scanningPhaseText

        engine.handleApplicationActiveStateChange(isActive: false)

        #expect(!engine.debugLocalVisualAnalysisIsRunning)
        await provider.waitUntilTerminated()
        await provider.yield(FoundationVisualCueSnapshot(
            index: 0,
            kind: .marking,
            detail: "two pale bands",
            isComplete: true
        ))
        await clock.advance()
        await Task.yield()
        #expect(engine.debugAcceptedFoundationPhraseCount == 0)
        #expect(engine.scanningPhaseText == phaseBeforeDeactivation)
        engine.cancelActiveRequest()
    }

    @Test func authTransitionDoesNotAwaitNonCooperativeLocalAnalysis() async throws {
        let classifier = ControlledVisionSubjectClassifier(
            result: VisionSubjectClassification(
                category: .mammal,
                candidates: [
                    VisionClassificationCandidate(
                        identifier: "mammal",
                        confidence: 0.99
                    )
                ]
            )
        )
        let engine = InferenceEngine(visionSubjectClassifier: classifier)
        let classificationTask = try #require(
            engine.debugStartLocalClassification(imageData: try makeImageData())
        )
        await classifier.waitUntilStarted()

        engine.beginAuthTransitionWriteFence()
        let completedDrain = CompletionFlag()
        let drain = Task { @MainActor in
            await engine.awaitAuthTransitionWriteQuiescence()
            await completedDrain.mark()
        }

        try await Task.sleep(for: .milliseconds(25))
        #expect(await completedDrain.value)
        #expect(!engine.debugLocalVisualAnalysisIsRunning)

        await classifier.complete()
        await classificationTask.value
        await drain.value
        #expect(engine.debugLocalVisionCategory == nil)
        engine.finishAuthTransitionWriteFence()
        engine.cancelActiveRequest()
    }

    private func makeImage() throws -> ImageDownsampler.SendableImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        return ImageDownsampler.SendableImage(
            cgImage: try #require(context.makeImage())
        )
    }

    private func makeImageData() throws -> Data {
        try #require(UIImage(cgImage: makeImage().cgImage).pngData())
    }

    private func eventually(
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            await Task.yield()
        }
        return false
    }
}
