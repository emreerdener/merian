import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import Merian

private struct AlwaysEligibleFoundationCueChecker: FoundationVisualCueEligibilityChecking {
    @MainActor
    func isEligibleForVisualCues() -> Bool { true }
}

private struct StubLocalVisualTraitExtractor: LocalVisualTraitExtracting {
    let cues: [FoundationVisualCue]

    func extractCues(
        from _: ImageDownsampler.SendableImage
    ) async -> [FoundationVisualCue] {
        cues
    }
}

private actor ControlledLocalVisualTraitExtractor: LocalVisualTraitExtracting {
    private let cues: [FoundationVisualCue]
    private var continuation: CheckedContinuation<[FoundationVisualCue], Never>?
    private var started = false

    init(cues: [FoundationVisualCue]) {
        self.cues = cues
    }

    func extractCues(
        from _: ImageDownsampler.SendableImage
    ) async -> [FoundationVisualCue] {
        started = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete() {
        continuation?.resume(returning: cues)
        continuation = nil
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }
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
        let prohibitedTermPrefixes = [
            "record", "range", "database", "taxonom", "species", "confidence",
            "match", "identif", "confirm", "habitat"
        ]

        for phrase in ScanningPhraseCoordinator.genericPhrases
            + LocalSubjectCategory.allCases.flatMap(\.phraseSeries) {
            #expect(phrase.count + 3 <= 36)
            let tokens = phrase.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            #expect(!tokens.contains { token in
                prohibitedTermPrefixes.contains { token.hasPrefix($0) }
            })
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

        let localCue = FoundationVisualCue(
            kind: .colorPattern,
            detail: "green and brown colors"
        )
        let acceptedLocalCue = coordinator.acceptLocalTraitCue(localCue)
        let acceptedLocalDuplicate = coordinator.acceptLocalTraitCue(localCue)
        #expect(acceptedLocalCue)
        #expect(!acceptedLocalDuplicate)
        #expect(coordinator.nextPhrase() == "Analyzing green and brown colors")
        #expect(coordinator.specificity == .localTrait)
        #expect(coordinator.promote(to: .avian) == "Analyzing green and brown colors")

        let foundationCue = FoundationVisualCue(
            kind: .colorPattern,
            detail: "amber banded wings"
        )
        let acceptedCue = coordinator.acceptFoundationCue(foundationCue)
        let acceptedDuplicate = coordinator.acceptFoundationCue(foundationCue)
        let acceptedDuplicateDetail = coordinator.acceptFoundationCue(
            FoundationVisualCue(
                kind: .marking,
                detail: "amber banded wings"
            )
        )
        #expect(acceptedCue)
        #expect(!acceptedDuplicate)
        #expect(!acceptedDuplicateDetail)
        #expect(coordinator.nextPhrase() == "Analyzing amber banded wings")
        #expect(coordinator.specificity == .foundation)

        #expect(coordinator.promote(to: .avian) == "Analyzing amber banded wings")
        #expect(coordinator.nextPhrase() == nil)
    }

    @Test func phraseCoordinatorWrapsOnlyAfterExhaustingEachActiveDeck() throws {
        var coordinator = ScanningPhraseCoordinator()
        let firstGenericPhrase = coordinator.reset()
        var genericCycle = Set([firstGenericPhrase.lowercased()])
        for _ in 1..<ScanningPhraseCoordinator.genericPhrases.count {
            let nextPhrase = coordinator.nextPhrase()
            let phrase = try #require(nextPhrase)
            #expect(genericCycle.insert(phrase.lowercased()).inserted)
        }
        let wrappedGenericPhrase = coordinator.nextPhrase()
        #expect(wrappedGenericPhrase == firstGenericPhrase)

        let categoryPhrase = coordinator.promote(to: .arthropod)
        var categoryCycle = Set([categoryPhrase.lowercased()])
        for _ in 1..<LocalSubjectCategory.arthropod.phraseSeries.count {
            let nextPhrase = coordinator.nextPhrase()
            let phrase = try #require(nextPhrase)
            #expect(categoryCycle.insert(phrase.lowercased()).inserted)
        }
        let wrappedCategoryPhrase = coordinator.nextPhrase()
        #expect(wrappedCategoryPhrase == categoryPhrase)

        let localCues = [
            FoundationVisualCue(
                kind: .colorPattern,
                detail: "green and brown colors"
            ),
            FoundationVisualCue(
                kind: .colorIntensity,
                detail: "mostly vivid colors"
            ),
            FoundationVisualCue(
                kind: .tone,
                detail: "light and shadow areas"
            ),
            FoundationVisualCue(
                kind: .contrast,
                detail: "stark lighting"
            ),
            FoundationVisualCue(
                kind: .surfaceTexture,
                detail: "broad smooth areas"
            )
        ]
        for cue in localCues {
            let accepted = coordinator.acceptLocalTraitCue(cue)
            #expect(accepted)
        }
        let acceptedOverflow = coordinator.acceptLocalTraitCue(
            FoundationVisualCue(
                kind: .arrangement,
                detail: "alternating light bands"
            )
        )
        #expect(!acceptedOverflow)
        var localCycle: [String] = []
        for _ in localCues.indices {
            let nextPhrase = coordinator.nextPhrase()
            localCycle.append(try #require(nextPhrase))
        }
        #expect(Set(localCycle).count == localCues.count)
        #expect(localCycle == localCues.map(\.pillText))
        let wrappedLocalPhrase = coordinator.nextPhrase()
        #expect(wrappedLocalPhrase == localCues[0].pillText)

        let nextScanPhrase = coordinator.reset()
        #expect(nextScanPhrase == "Analyzing subject")
        #expect(coordinator.shownPhrases == [nextScanPhrase.lowercased()])
        #expect(coordinator.nextPhrase() == "Examining visible form")
    }

    @Test func handoffDeckKeepsCurrentPhraseThenExhaustsUnseenOptions() {
        var coordinator = ScanningPhraseCoordinator()
        _ = coordinator.reset()
        _ = coordinator.promote(to: .arthropod)
        let cues = [
            FoundationVisualCue(
                kind: .colorPattern,
                detail: "green and brown colors"
            ),
            FoundationVisualCue(
                kind: .colorIntensity,
                detail: "mostly vivid colors"
            ),
            FoundationVisualCue(
                kind: .tone,
                detail: "light and shadow areas"
            ),
            FoundationVisualCue(
                kind: .contrast,
                detail: "stark lighting"
            ),
            FoundationVisualCue(
                kind: .surfaceTexture,
                detail: "broad smooth areas"
            )
        ]
        for cue in cues {
            let accepted = coordinator.acceptLocalTraitCue(cue)
            #expect(accepted)
        }

        #expect(coordinator.nextPhrase() == cues[0].pillText)
        #expect(coordinator.nextPhrase() == cues[1].pillText)
        #expect(coordinator.handoffPhraseDeck == [
            cues[1].pillText,
            cues[2].pillText,
            cues[3].pillText,
            cues[4].pillText,
            cues[0].pillText
        ])
    }

    @Test func deterministicTraitExtractorVariesCuesWithImagePixels() async throws {
        let extractor = AppleImageVisualTraitExtractor()
        let redGreenCues = await extractor.extractCues(
            from: try makeSplitImage(
                left: UIColor(red: 1, green: 0, blue: 0, alpha: 1).cgColor,
                right: UIColor(red: 0, green: 1, blue: 0, alpha: 1).cgColor
            )
        )
        let yellowBlueCues = await extractor.extractCues(
            from: try makeSplitImage(
                left: UIColor(red: 1, green: 1, blue: 0, alpha: 1).cgColor,
                right: UIColor(red: 0, green: 0, blue: 1, alpha: 1).cgColor
            )
        )

        #expect(redGreenCues.count == LocalVisualTraitCuePolicy.maximumCueCount)
        #expect(yellowBlueCues.count == LocalVisualTraitCuePolicy.maximumCueCount)
        #expect(redGreenCues[0].pillText == "Analyzing red and green colors")
        #expect(yellowBlueCues[0].pillText == "Analyzing yellow and blue colors")
        #expect(redGreenCues[0] != yellowBlueCues[0])
        #expect(redGreenCues[1].pillText == "Reviewing mostly vivid colors")
        #expect(redGreenCues[2].pillText == "Observing light and shadow areas")
        #expect(redGreenCues[3].pillText == "Assessing stark lighting")
        #expect(redGreenCues[4].pillText == "Noting broad smooth areas")

        for cue in redGreenCues + yellowBlueCues {
            #expect(FoundationVisualCueValidator.validatedCue(
                cue,
                forbiddenIdentityTerms: []
            ) == cue)
        }
    }

    @Test func deterministicTraitExtractorUsesConcreteMidrangeWording() async throws {
        let extractor = AppleImageVisualTraitExtractor()
        let softlyColoredCues = await extractor.extractCues(
            from: try makeSplitImage(
                left: UIColor(
                    red: 0.60,
                    green: 0.40,
                    blue: 0.40,
                    alpha: 1
                ).cgColor,
                right: UIColor(
                    red: 0.40,
                    green: 0.60,
                    blue: 0.40,
                    alpha: 1
                ).cgColor
            )
        )
        let mixedIntensityCues = await extractor.extractCues(
            from: try makeSplitImage(
                left: UIColor(
                    red: 0.50,
                    green: 0.50,
                    blue: 0.50,
                    alpha: 1
                ).cgColor,
                right: UIColor(
                    red: 0,
                    green: 0.60,
                    blue: 0,
                    alpha: 1
                ).cgColor
            )
        )
        let variedLightingCues = await extractor.extractCues(
            from: try makeSplitImage(
                left: UIColor(white: 0.35, alpha: 1).cgColor,
                right: UIColor(white: 0.65, alpha: 1).cgColor
            )
        )

        #expect(softlyColoredCues.count == LocalVisualTraitCuePolicy.maximumCueCount)
        #expect(mixedIntensityCues.count == LocalVisualTraitCuePolicy.maximumCueCount)
        #expect(variedLightingCues.count == LocalVisualTraitCuePolicy.maximumCueCount)
        #expect(softlyColoredCues[1].pillText == "Reviewing softly colored areas")
        #expect(softlyColoredCues[2].pillText == "Observing evenly lit areas")
        #expect(softlyColoredCues[3].pillText == "Assessing subtle light changes")
        #expect(mixedIntensityCues[1].pillText == "Reviewing muted and vivid colors")
        #expect(variedLightingCues[2].pillText == "Observing light and shadow areas")
        #expect(variedLightingCues[3].pillText == "Assessing varied lighting")

        for cue in softlyColoredCues + mixedIntensityCues + variedLightingCues {
            let lowercasePhrase = cue.pillText.lowercased()
            #expect(!lowercasePhrase.contains("balanced"))
            #expect(!lowercasePhrase.contains("moderate"))
            #expect(!lowercasePhrase.contains("levels"))
            #expect(!lowercasePhrase.contains("values"))
            #expect(FoundationVisualCueValidator.validatedCue(
                cue,
                forbiddenIdentityTerms: []
            ) == cue)
        }
    }

    @Test func deterministicTraitExtractorUsesConcreteLightingAndSurfaceExtremes() async throws {
        let extractor = AppleImageVisualTraitExtractor()
        let shadowCues = await extractor.extractCues(
            from: try makeSplitImage(
                left: UIColor(white: 0.10, alpha: 1).cgColor,
                right: UIColor(white: 0.10, alpha: 1).cgColor
            )
        )
        let brightCues = await extractor.extractCues(
            from: try makeSplitImage(
                left: UIColor(white: 0.90, alpha: 1).cgColor,
                right: UIColor(white: 0.90, alpha: 1).cgColor
            )
        )
        let detailedCues = await extractor.extractCues(
            from: try makeCheckerboardImage(
                first: UIColor(white: 0.425, alpha: 1).cgColor,
                second: UIColor(white: 0.575, alpha: 1).cgColor
            )
        )
        let fineEdgeCues = await extractor.extractCues(
            from: try makeCheckerboardImage(
                first: UIColor.black.cgColor,
                second: UIColor.white.cgColor
            )
        )

        #expect(shadowCues[2].pillText == "Observing mostly shadowed areas")
        #expect(brightCues[2].pillText == "Observing mostly bright areas")
        #expect(detailedCues[4].pillText == "Noting smooth and detailed areas")
        #expect(fineEdgeCues[4].pillText == "Noting many fine edges")

        for cue in shadowCues + brightCues + detailedCues + fineEdgeCues {
            #expect(FoundationVisualCueValidator.validatedCue(
                cue,
                forbiddenIdentityTerms: []
            ) == cue)
        }
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
        #expect(valid?.pillText == "Analyzing amber banded wings")

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
            existingPhrases: ["reviewing two pale bands"]
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

    @Test func enginePublishesVisionCategoryThenImageTraitsOnCadence() async throws {
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
            localVisualTraitExtractor: StubLocalVisualTraitExtractor(cues: [
                FoundationVisualCue(
                    kind: .colorPattern,
                    detail: "green and brown colors"
                ),
                FoundationVisualCue(
                    kind: .colorIntensity,
                    detail: "mostly vivid colors"
                ),
                FoundationVisualCue(
                    kind: .tone,
                    detail: "light and shadow areas"
                ),
                FoundationVisualCue(
                    kind: .contrast,
                    detail: "stark lighting"
                ),
                FoundationVisualCue(
                    kind: .surfaceTexture,
                    detail: "broad smooth areas"
                )
            ]),
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
        await engine.debugWaitForLocalVisualTraits()
        #expect(engine.scanningPhaseText == "Arthropod form visible")
        await clock.waitUntilSleepCallCount(2)
        #expect(engine.scanningPhaseText == "Arthropod form visible")

        await clock.advance()
        await clock.waitUntilSleepCallCount(3)
        #expect(engine.scanningPhaseText == "Analyzing green and brown colors")

        await clock.advance()
        await clock.waitUntilSleepCallCount(4)
        #expect(engine.scanningPhaseText == "Reviewing mostly vivid colors")

        await clock.advance()
        await clock.waitUntilSleepCallCount(5)
        #expect(engine.scanningPhaseText == "Observing light and shadow areas")

        await clock.advance()
        await clock.waitUntilSleepCallCount(6)
        #expect(engine.scanningPhaseText == "Assessing stark lighting")

        await clock.advance()
        await clock.waitUntilSleepCallCount(7)
        #expect(engine.scanningPhaseText == "Noting broad smooth areas")

        await clock.advance()
        await clock.waitUntilSleepCallCount(8)
        #expect(engine.scanningPhaseText == "Analyzing green and brown colors")
        engine.cancelActiveRequest()
    }

    @Test func hungLocalTraitExtractorCannotDelayOrPublishAfterGeminiCompletion() async throws {
        let classifier = ControlledVisionSubjectClassifier(
            result: VisionSubjectClassification(
                category: .arthropod,
                candidates: []
            )
        )
        let extractor = ControlledLocalVisualTraitExtractor(cues: [
            FoundationVisualCue(
                kind: .colorPattern,
                detail: "green and brown colors"
            )
        ])
        let engine = InferenceEngine(
            visionSubjectClassifier: classifier,
            localVisualTraitExtractor: extractor
        )
        let classificationTask = try #require(
            engine.debugStartLocalClassification(imageData: try makeImageData())
        )
        await classifier.waitUntilStarted()
        await classifier.complete()
        await classificationTask.value
        await extractor.waitUntilStarted()
        let phaseBeforeCompletion = engine.scanningPhaseText

        let startedAt = ContinuousClock.now
        engine.debugSimulateGeminiResponseArrival()
        let elapsed = startedAt.duration(to: .now)

        #expect(elapsed < .milliseconds(100))
        #expect(!engine.debugLocalVisualAnalysisIsRunning)
        #expect(!engine.debugLocalVisualTraitIsRunning)
        await extractor.complete()
        await Task.yield()
        #expect(engine.scanningPhaseText == phaseBeforeCompletion)
    }

    @Test func replacementRejectsDelayedLocalTraitCue() async throws {
        let classifier = ControlledVisionSubjectClassifier(
            result: VisionSubjectClassification(
                category: .arthropod,
                candidates: []
            )
        )
        let extractor = ControlledLocalVisualTraitExtractor(cues: [
            FoundationVisualCue(
                kind: .colorPattern,
                detail: "green and brown colors"
            )
        ])
        let engine = InferenceEngine(
            visionSubjectClassifier: classifier,
            localVisualTraitExtractor: extractor
        )
        let classificationTask = try #require(
            engine.debugStartLocalClassification(imageData: try makeImageData())
        )
        await classifier.waitUntilStarted()
        await classifier.complete()
        await classificationTask.value
        await extractor.waitUntilStarted()

        engine.prepareForNewScan()
        let replacementPhrase = engine.scanningPhaseText
        #expect(!engine.debugLocalVisualAnalysisIsRunning)

        await extractor.complete()
        await Task.yield()
        #expect(engine.scanningPhaseText == replacementPhrase)
        #expect(engine.scanningPhaseText == "Analyzing subject")
    }

    @Test func sameScanQueueHandoffPreservesContextualPhraseSession() {
        let engine = InferenceEngine()
        engine.simulateProgressiveAnalyzing(automaticallyAdvances: false)
        engine.debugAdvanceProgressiveAnalyzing()
        engine.debugAdvanceProgressiveAnalyzing()
        let contextualPhrase = engine.scanningPhaseText

        #expect(engine.debugTransitionProgressiveAnalyzingToQueue(
            scanId: "same-scan-handoff"
        ))

        #expect(contextualPhrase == "Analyzing amber banded wings")
        #expect(engine.scanningPhaseText == contextualPhrase)
        #expect(engine.liveQueueHandoffScanningPhrases(
            for: "same-scan-handoff"
        ) == [contextualPhrase])
        #expect(engine.liveQueueHandoffScanningPhrases(
            for: "another-scan"
        ).isEmpty)
        engine.cancelActiveRequest()
    }

    @Test func preparedVisualQueueHandoffUsesCompleteGenericDeckWithoutLiveMedia() {
        let engine = InferenceEngine()
        let scanId = "prepared-visual-handoff"
        let attemptGeneration = UUID()
        engine.activeMedia = ActiveScanMedia(
            items: [.liveImage(Data([0x01]))]
        )
        engine.prepareForNewScan(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .visual
        )

        #expect(engine.transitionToQueuedPresentation(
            scanId: scanId,
            source: .prepared(attemptGeneration: attemptGeneration)
        ))
        #expect(
            engine.liveQueueHandoffScanningPhrases(for: scanId)
                == ScanningPhraseCoordinator.genericPhrases
        )
        #expect(!engine.hasLiveQueueHandoffMedia(for: scanId))
        engine.cancelActiveRequest()
    }

    @Test func staleQueueHandoffCannotRebrandAnotherVisualSession() async throws {
        let engine = InferenceEngine()
        let scanId = "owned-visual-handoff"
        let attemptGeneration = UUID()
        engine.debugStartFoundationCueStream(
            image: try makeImage(),
            classification: VisionSubjectClassification(
                category: .arthropod,
                candidates: []
            ),
            scanId: scanId,
            attemptGeneration: attemptGeneration
        )
        let contextualPhrase = engine.scanningPhaseText
        engine.activeMedia = ActiveScanMedia(
            items: [.liveImage(try makeImageData())]
        )

        #expect(!engine.transitionToQueuedPresentation(
            scanId: "stale-visual-handoff",
            source: .active(attemptGeneration: attemptGeneration)
        ))
        #expect(engine.queuedPresentationScanId == nil)
        #expect(engine.scanningPhaseText == contextualPhrase)
        #expect(!engine.hasLiveVisualQueueHandoff(for: "stale-visual-handoff"))

        #expect(engine.transitionToQueuedPresentation(
            scanId: scanId,
            source: .active(attemptGeneration: attemptGeneration)
        ))
        #expect(!engine.liveQueueHandoffScanningPhrases(for: scanId).isEmpty)
        #expect(engine.hasLiveQueueHandoffMedia(for: scanId))

        #expect(!engine.transitionToQueuedPresentation(
            scanId: "stale-visual-handoff",
            source: .active(attemptGeneration: UUID())
        ))
        #expect(engine.queuedPresentationScanId == scanId)
        #expect(engine.liveQueueHandoffScanningPhrases(for: scanId).isEmpty)
        #expect(!engine.hasLiveVisualQueueHandoff(for: scanId))
        #expect(!engine.hasLiveQueueHandoffMedia(for: scanId))
        #expect(engine.liveQueueHandoffScanningPhrases(
            for: "stale-visual-handoff"
        ).isEmpty)
        #expect(!engine.hasLiveVisualQueueHandoff(for: "stale-visual-handoff"))
        #expect(!engine.hasLiveQueueHandoffMedia(for: "stale-visual-handoff"))
        engine.cancelActiveRequest()
    }

    @Test func nonVisualPresentationNeverInheritsVisualPhrasesOrRotation() {
        for (index, phrase) in ["Listening", "Identifying describe"].enumerated() {
            let engine = InferenceEngine()
            let scanId = "nonvisual-handoff-\(index)"
            let attemptGeneration = engine.debugStartNonVisualPresentation(
                scanId: scanId,
                phrase: phrase
            )
            engine.activeMedia = ActiveScanMedia(
                items: index == 0
                    ? [.audio("documents/nonvisual.wav")]
                    : [.description(ObservationContext(
                        freeText: "Observed beside a path"
                    ))]
            )

            engine.handleApplicationActiveStateChange(isActive: false)
            engine.handleApplicationActiveStateChange(isActive: true)
            #expect(engine.scanningPhaseText == phrase)
            #expect(!engine.debugLocalVisualAnalysisIsRunning)

            #expect(engine.transitionToQueuedPresentation(
                scanId: scanId,
                source: .active(attemptGeneration: attemptGeneration)
            ))
            #expect(engine.liveQueueHandoffScanningPhrases(for: scanId).isEmpty)
            #expect(!engine.hasLiveVisualQueueHandoff(for: scanId))
            #expect(!engine.hasLiveQueueHandoffMedia(for: scanId))
            engine.cancelActiveRequest()
        }
    }

    @Test func appDeactivationStopsLocalWorkWithoutResettingVisibleContext() {
        let engine = InferenceEngine()
        engine.simulateProgressiveAnalyzing(automaticallyAdvances: false)
        engine.debugAdvanceProgressiveAnalyzing()
        engine.debugAdvanceProgressiveAnalyzing()
        let contextualPhrase = engine.scanningPhaseText

        engine.handleApplicationActiveStateChange(isActive: false)

        #expect(engine.scanningPhaseText == contextualPhrase)
        #expect(!engine.debugLocalVisualAnalysisIsRunning)
        engine.cancelActiveRequest()
    }

    @Test func initialApplicationActivationDoesNotInventACadenceResume() {
        let engine = InferenceEngine()
        engine.simulateProgressiveAnalyzing(automaticallyAdvances: false)
        let initialPhrase = engine.scanningPhaseText

        engine.handleApplicationActiveStateChange(isActive: true)

        #expect(engine.scanningPhaseText == initialPhrase)
        #expect(!engine.debugLocalVisualAnalysisIsRunning)
        engine.cancelActiveRequest()
    }

    @Test func applicationReactivationResumesOnlyAnActiveCadence() {
        let engine = InferenceEngine()
        engine.simulateProgressiveAnalyzing(automaticallyAdvances: false)
        let initialPhrase = engine.scanningPhaseText

        engine.handleApplicationActiveStateChange(isActive: false)
        engine.handleApplicationActiveStateChange(isActive: true)

        #expect(engine.scanningPhaseText == initialPhrase)
        #expect(!engine.debugLocalVisualAnalysisIsRunning)
        engine.cancelActiveRequest()
    }

    @Test func dismissalFencesLateLocalCueWithoutCancellingNetwork() async throws {
        let classifier = ControlledVisionSubjectClassifier(
            result: VisionSubjectClassification(
                category: .arthropod,
                candidates: []
            )
        )
        let extractor = ControlledLocalVisualTraitExtractor(cues: [
            FoundationVisualCue(
                kind: .colorPattern,
                detail: "green and brown colors"
            )
        ])
        let engine = InferenceEngine(
            visionSubjectClassifier: classifier,
            localVisualTraitExtractor: extractor
        )
        engine.activeMedia = ActiveScanMedia(
            items: [.liveImage(try makeImageData())]
        )
        let networkTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(30))
        }
        engine.inferenceTask = networkTask
        let classificationTask = try #require(
            engine.debugStartLocalClassification(imageData: try makeImageData())
        )
        await classifier.waitUntilStarted()
        await classifier.complete()
        await classificationTask.value
        await extractor.waitUntilStarted()

        engine.dismissAnalyzingPresentation()

        #expect(!networkTask.isCancelled)
        #expect(!engine.debugLocalVisualAnalysisIsRunning)
        #expect(engine.scanningPhaseText == "Analyzing subject")
        #expect(engine.activeMedia.totalItems == 0)
        await extractor.complete()
        await Task.yield()
        #expect(engine.scanningPhaseText == "Analyzing subject")
        engine.cancelActiveRequest()
        _ = try? await networkTask.value
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
        await clock.waitUntilSleepCallCount(1)

        await provider.yield(FoundationVisualCueSnapshot(
            index: 0,
            kind: .colorPattern,
            detail: nil,
            isComplete: false
        ))
        await provider.yield(FoundationVisualCueSnapshot(
            index: 0,
            kind: nil,
            detail: "amber banded wings",
            isComplete: true
        ))
        await provider.yield(FoundationVisualCueSnapshot(
            index: 1,
            kind: .marking,
            detail: "amber banded wings",
            isComplete: true
        ))
        await provider.finish()
        await engine.debugWaitForFoundationVisualCueStream()

        #expect(engine.debugAcceptedFoundationPhraseCount == 1)
        #expect(engine.scanningPhaseText == "Arthropod form visible")

        await clock.advance()
        await clock.waitUntilSleepCallCount(2)
        #expect(engine.scanningPhaseText == "Analyzing amber banded wings")
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
        #expect(replacementEngine.scanningPhaseText == "Analyzing subject")

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

        engine.handleApplicationActiveStateChange(isActive: true)
        await clock.waitUntilSleepCallCount(2)
        await clock.advance()
        for _ in 0..<100 {
            if engine.scanningPhaseText != phaseBeforeDeactivation { break }
            await Task.yield()
        }
        #expect(engine.scanningPhaseText != phaseBeforeDeactivation)
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

    @Test func authTransitionClearsQueuedVisualPhraseAndMediaContext() {
        let engine = InferenceEngine()
        let scanId = "auth-visual-handoff"
        let liveImage = Data([0x01, 0x02, 0x03])
        engine.simulateProgressiveAnalyzing(automaticallyAdvances: false)
        engine.debugAdvanceProgressiveAnalyzing()
        engine.debugAdvanceProgressiveAnalyzing()
        engine.activeMedia = ActiveScanMedia(items: [.liveImage(liveImage)])
        #expect(engine.debugTransitionProgressiveAnalyzingToQueue(
            scanId: scanId
        ))
        #expect(!engine.liveQueueHandoffScanningPhrases(for: scanId).isEmpty)
        #expect(engine.hasLiveQueueHandoffMedia(for: scanId))

        engine.beginAuthTransitionWriteFence()

        #expect(engine.queuedPresentationScanId == nil)
        #expect(engine.liveQueueHandoffScanningPhrases(for: scanId).isEmpty)
        #expect(!engine.hasLiveQueueHandoffMedia(for: scanId))
        #expect(engine.activeMedia.totalItems == 0)
        #expect(engine.scanningPhaseText == "Analyzing subject")
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

    private func makeSplitImage(
        left: CGColor,
        right: CGColor
    ) throws -> ImageDownsampler.SendableImage {
        let width = 32
        let height = 32
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let halfWidth = CGFloat(width) / 2
        context.setFillColor(left)
        context.fill(CGRect(
            x: 0,
            y: 0,
            width: halfWidth,
            height: CGFloat(height)
        ))
        context.setFillColor(right)
        context.fill(CGRect(
            x: halfWidth,
            y: 0,
            width: halfWidth,
            height: CGFloat(height)
        ))
        return ImageDownsampler.SendableImage(
            cgImage: try #require(context.makeImage())
        )
    }

    private func makeCheckerboardImage(
        first: CGColor,
        second: CGColor
    ) throws -> ImageDownsampler.SendableImage {
        let width = 32
        let height = 32
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        for y in 0..<height {
            for x in 0..<width {
                context.setFillColor((x + y).isMultiple(of: 2) ? first : second)
                context.fill(CGRect(
                    x: CGFloat(x),
                    y: CGFloat(y),
                    width: 1,
                    height: 1
                ))
            }
        }
        return ImageDownsampler.SendableImage(
            cgImage: try #require(context.makeImage())
        )
    }

    private func makeImageData() throws -> Data {
        try #require(UIImage(cgImage: makeImage().cgImage).pngData())
    }

}
