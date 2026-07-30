import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightSheetViewModelTests {

    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        ScanRepository.shared.configure(with: context)
        return context
    }

    private func contribution(
        kind: FieldTripScanContribution.SourceKind,
        sourceId: String,
        title: String
    ) -> FieldTripScanContribution {
        let isEvent = kind == .event
        return FieldTripScanContribution(
            sourceKind: kind,
            sourceId: sourceId,
            userFieldTripId: isEvent ? "linked-trip" : sourceId,
            participationId: isEvent ? sourceId : nil,
            templateId: "template-\(sourceId)",
            challengeId: isEvent ? "challenge-\(sourceId)" : nil,
            title: title,
            slug: title.lowercased().replacingOccurrences(of: " ", with: "_"),
            itemId: "item-\(sourceId)",
            prompt: isEvent ? "Bird" : "Butterfly or moth",
            levelNumber: 1,
            levelTitle: "Level 1",
            completedCount: isEvent ? 2 : 3,
            targetCount: isEvent ? 6 : 4,
            isComplete: false,
            artworkPrompt: isEvent ? "Bird" : "Butterfly or moth",
            artworkTemplateSlug: nil,
            destinationKind: isEvent ? "field_trip_challenge" : "field_trip",
            destinationTemplateId: isEvent ? nil : "template-\(sourceId)",
            destinationChecklistItemId: isEvent ? nil : "item-\(sourceId)",
            destinationChallengeId: isEvent ? "challenge-\(sourceId)" : nil
        )
    }

    private func biologicalEngine(scanId: String) -> InferenceEngine {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: scanId,
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "A butterfly.", hazardType: "none"),
            confidenceScore: 0.98,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        return engine
    }

    private func bindToolbarPresentation(
        _ viewModel: InsightSheetViewModel,
        scanId: String
    ) {
        let record = LocalScanRecord(
            id: scanId,
            speciesId: "toolbar_candidate_species",
            scientificName: "Uresiphita reversalis",
            commonName: "Genista Broom Moth"
        )
        viewModel.activeLocalRecord = record
        viewModel.activeLocalRecordId = record.id
        viewModel.toolbarRecordSnapshot =
            InsightToolbarRecordSnapshot(record: record)
    }

    @Test func testEvaluateScrollOffset() {
        let viewModel = InsightSheetViewModel()
        #expect(viewModel.state.isCommonNameScrolledPast == false)
        
        viewModel.evaluateScrollOffset(minY: 40.0)
        #expect(viewModel.state.isCommonNameScrolledPast == true)
        
        viewModel.evaluateScrollOffset(minY: 60.0)
        #expect(viewModel.state.isCommonNameScrolledPast == false)
    }

    @Test func testEvaluateHeroScrollOffsetUsesClearanceHysteresis() {
        let viewModel = InsightSheetViewModel()
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == true)

        viewModel.evaluateHeroScrollOffset(maxY: 45)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == true)

        viewModel.evaluateHeroScrollOffset(maxY: 44)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == false)

        viewModel.evaluateHeroScrollOffset(maxY: 47)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == false)

        viewModel.evaluateHeroScrollOffset(maxY: 48)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == true)

        viewModel.evaluateHeroScrollOffset(maxY: 40)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == false)

        viewModel.evaluateHeroScrollOffset(maxY: .infinity)
        viewModel.evaluateHeroScrollOffset(maxY: .nan)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == false)

        viewModel.reset()
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == true)
    }

    @Test func testResetMonotonicallyInvalidatesScanBoundRequests() {
        let viewModel = InsightSheetViewModel()
        viewModel.scanBoundActionGeneration = 7
        viewModel.sharedExploreStateRevision = 11
        viewModel.sharedExploreStateRequestToken = 13
        viewModel.fieldTripContributionRequestToken = 17

        viewModel.reset()

        #expect(viewModel.scanBoundActionGeneration == 8)
        #expect(viewModel.sharedExploreStateRevision == 12)
        #expect(viewModel.sharedExploreStateRequestToken == 14)
        #expect(viewModel.fieldTripContributionRequestToken == 18)
    }

    @Test func fieldTripContributionsLoadEveryCreditedExperience() async {
        let standard = contribution(
            kind: .standardOuting,
            sourceId: "trip-1",
            title: "Park Pollinators"
        )
        let event = contribution(
            kind: .event,
            sourceId: "participation-1",
            title: "Summer Bird Count"
        )
        let viewModel = InsightSheetViewModel(
            inferenceEngine: biologicalEngine(scanId: "saved-scan"),
            fieldTripContributionLoader: { scanId in
                #expect(scanId == "saved-scan")
                return [standard, event]
            },
            fieldTripAuthenticationResolver: { true },
            fieldTripAvailabilityResolver: { true },
            fieldTripEventsAvailabilityResolver: { true }
        )

        await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")

        #expect(viewModel.fieldTripScanContributions == [standard, event])
        #expect(viewModel.isLoadingFieldTripScanContributions == false)
    }

    @Test func fieldTripContributionsExposeLoadingStateUntilRequestCompletes() async {
        let standard = contribution(
            kind: .standardOuting,
            sourceId: "trip-1",
            title: "Park Pollinators"
        )
        let loaderGate = FieldTripContributionLoaderGate()
        let viewModel = InsightSheetViewModel(
            inferenceEngine: biologicalEngine(scanId: "saved-scan"),
            fieldTripContributionLoader: { _ in
                await loaderGate.load()
            },
            fieldTripAuthenticationResolver: { true },
            fieldTripAvailabilityResolver: { true },
            fieldTripEventsAvailabilityResolver: { true }
        )

        let loadTask = Task {
            await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")
        }
        await loaderGate.waitUntilStarted()

        #expect(viewModel.isLoadingFieldTripScanContributions)
        #expect(viewModel.fieldTripScanContributions.isEmpty)

        await loaderGate.finish(with: [standard])
        await loadTask.value

        #expect(viewModel.isLoadingFieldTripScanContributions == false)
        #expect(viewModel.fieldTripScanContributions == [standard])
    }

    @Test func fieldTripContributionsHideEventRowsWhenEventsAreDisabled() async {
        let standard = contribution(
            kind: .standardOuting,
            sourceId: "trip-1",
            title: "Park Pollinators"
        )
        let event = contribution(
            kind: .event,
            sourceId: "participation-1",
            title: "Summer Bird Count"
        )
        let viewModel = InsightSheetViewModel(
            inferenceEngine: biologicalEngine(scanId: "saved-scan"),
            fieldTripContributionLoader: { _ in [standard, event] },
            fieldTripAuthenticationResolver: { true },
            fieldTripAvailabilityResolver: { true },
            fieldTripEventsAvailabilityResolver: { false }
        )

        await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")

        #expect(viewModel.fieldTripScanContributions == [standard])
    }

    @Test func fieldTripContributionsHideSilentlyOnNetworkFailure() async {
        struct ExpectedFailure: Error {}
        let viewModel = InsightSheetViewModel(
            inferenceEngine: biologicalEngine(scanId: "saved-scan"),
            fieldTripContributionLoader: { _ in throw ExpectedFailure() },
            fieldTripAuthenticationResolver: { true },
            fieldTripAvailabilityResolver: { true },
            fieldTripEventsAvailabilityResolver: { true }
        )

        await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")

        #expect(viewModel.fieldTripScanContributions.isEmpty)
        #expect(viewModel.isLoadingFieldTripScanContributions == false)
    }

    @Test func fieldTripContributionsLoadAfterAuthenticationRestores() async {
        let standard = contribution(
            kind: .standardOuting,
            sourceId: "trip-1",
            title: "Park Pollinators"
        )
        var isAuthenticated = false
        var loaderCalls = 0
        let viewModel = InsightSheetViewModel(
            inferenceEngine: biologicalEngine(scanId: "saved-scan"),
            fieldTripContributionLoader: { _ in
                loaderCalls += 1
                return [standard]
            },
            fieldTripAuthenticationResolver: { isAuthenticated },
            fieldTripAvailabilityResolver: { true },
            fieldTripEventsAvailabilityResolver: { true }
        )

        await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")
        #expect(loaderCalls == 0)
        #expect(viewModel.fieldTripScanContributions.isEmpty)

        isAuthenticated = true
        await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")

        #expect(loaderCalls == 1)
        #expect(viewModel.fieldTripScanContributions == [standard])
    }

    @Test func fieldTripContributionLoadKeyChangesWhenAuthenticationRestores() {
        let signedOut = InsightFieldTripContributionLoadKey(
            scanId: "saved-scan",
            isAuthenticated: false,
            accountId: nil
        )
        let restored = InsightFieldTripContributionLoadKey(
            scanId: "saved-scan",
            isAuthenticated: true,
            accountId: "account-1"
        )

        #expect(signedOut != restored)
    }

    @Test func standardFieldTripInsightContributionRoutesToGoalsOverview() {
        let standard = contribution(
            kind: .standardOuting,
            sourceId: "trip-1",
            title: "Park Pollinators"
        )

        let destination = InsightFieldTripOverviewDestination(contribution: standard)

        #expect(destination == .standardOuting(templateId: "template-trip-1"))
    }

    @Test func eventFieldTripInsightContributionRoutesToChallengeOverview() {
        let event = contribution(
            kind: .event,
            sourceId: "participation-1",
            title: "Summer Bird Count"
        )

        let destination = InsightFieldTripOverviewDestination(contribution: event)

        #expect(destination == .event(challengeId: "challenge-participation-1"))
    }

    @Test func profileStatsRefreshKeyChangesWhenAuthenticationRestores() {
        let refreshToken = UUID()
        let signedOut = ProfileStatsRefreshKey(
            refreshToken: refreshToken,
            isAuthenticated: false,
            accountId: nil
        )
        let restored = ProfileStatsRefreshKey(
            refreshToken: refreshToken,
            isAuthenticated: true,
            accountId: "account-1"
        )

        #expect(signedOut != restored)
    }

    @Test func testToggleScanInCollection() async throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        
        let record = LocalScanRecord(speciesId: "scan_toggle", scientificName: "Test", commonName: "Test")
        ctx.insert(record)
        
        let collection = ScanCollection(name: "Favorites")
        ctx.insert(collection)
        try ctx.save()
        
        viewModel.activeLocalRecordId = record.id
        viewModel.activeLocalRecord = record
        
        viewModel.toggleScanInCollection(collection, modelContext: ctx)
        #expect(record.collections?.contains(where: { $0.id == collection.id }) == true)
        #expect(viewModel.state.toastMessage?.contains("Added to Favorites") == true)
        
        viewModel.toggleScanInCollection(collection, modelContext: ctx)
        #expect(record.collections?.contains(where: { $0.id == collection.id }) == false)
        #expect(viewModel.state.toastMessage?.contains("Removed from Favorites") == true)
    }

    @Test func testComputedHeaderProperties() async throws {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        
        let insightData = InsightData(aiReasoning: "A test object.\nWith multiple lines.", hazardType: "venomous")
        engine.speciesData = SpeciesData(
            scanId: "comp_1",
            commonName: "Common Name",
            scientificName: "Sci Name",
            insightData: insightData,
            confidenceScore: 0.99,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        viewModel.inferenceEngine = engine
        
        #expect(viewModel.resolvedHeaderTitle == "Common Name")
        #expect(viewModel.headerSubtitle == "Sci Name")
        #expect(viewModel.hazardType == "venomous")
        #expect(viewModel.isHazardous == true)
        #expect(viewModel.headerParagraphs.count == 2)
        #expect(viewModel.headerParagraphs.first == "A test object.")
    }

    @Test func testPetIdentificationDrivesHeaderTitleWithoutReplacingScientificSubtitle() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "pet_header",
            commonName: "Domestic Dog",
            scientificName: "Canis lupus familiaris",
            insightData: InsightData(aiReasoning: "A domestic dog.", hazardType: "none"),
            confidenceScore: 0.94,
            petIdentification: PetIdentification(
                speciesGroup: "dog",
                label: "Australian Cattle Dog",
                labelType: "breed",
                confidenceScore: 0.91,
                evidence: ["blue roan coat"]
            )
        )
        viewModel.inferenceEngine = engine

        #expect(viewModel.resolvedHeaderTitle == "Australian Cattle Dog")
        #expect(viewModel.headerSubtitle == "Canis lupus familiaris")
        #expect(engine.speciesData?.shouldSuppressReferenceImages == true)

        engine.speciesData = SpeciesData(
            scanId: "cat_header",
            commonName: "Domestic Cat",
            scientificName: "Felis catus",
            insightData: InsightData(aiReasoning: "A domestic cat.", hazardType: "none"),
            confidenceScore: 0.94,
            petIdentification: PetIdentification(
                speciesGroup: "cat",
                label: "Tuxedo Cat",
                labelType: "coat_pattern",
                confidenceScore: 0.91,
                evidence: ["black and white coat"]
            )
        )

        #expect(viewModel.resolvedHeaderTitle == "Tuxedo Cat")
        #expect(viewModel.headerSubtitle == "Felis catus")
        #expect(engine.speciesData?.shouldSuppressReferenceImages == true)
    }

    @Test func localNewDiscoveryDoesNotShowNewToMerianMilestone() {
        var species = milestoneTestSpecies()
        species.isNewDiscovery = true
        species.isNewToMerianDictionary = false

        #expect(ScanMilestoneCoordinator.isValidNewToMerianMilestone(species) == false)
    }

    @Test func globalDictionaryContributionQualifiesForNewToMerianMilestone() {
        var species = milestoneTestSpecies()
        species.isNewDiscovery = false
        species.isNewToMerianDictionary = true

        #expect(ScanMilestoneCoordinator.isValidNewToMerianMilestone(species))
    }

    @Test func invalidDictionaryContributionDoesNotShowNewToMerianMilestone() {
        var species = milestoneTestSpecies(commonName: "Unknown Subject", isBiological: true)
        species.isNewToMerianDictionary = true

        #expect(ScanMilestoneCoordinator.isValidNewToMerianMilestone(species) == false)
    }

    @Test func testNonBiologicalHeaderTitleUsesFriendlyDisplayName() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "nonbio_title",
            commonName: "Unknown Subject",
            scientificName: "Taxonomy Unavailable",
            insightData: InsightData(aiReasoning: "A non-biological subject.", hazardType: "none"),
            confidenceScore: 0.0,
            isBiological: false,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        viewModel.inferenceEngine = engine

        #expect(viewModel.resolvedHeaderTitle == "Non-biological")
    }

    @Test func testNetworkTimeoutPlaceholderKeepsErrorTitle() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        let species = SpeciesData(
            scanId: nil,
            commonName: "Network timeout",
            scientificName: "Offline mode",
            insightData: InsightData(
                aiReasoning: "Naturebook saved this scan and will retry automatically.",
                hazardType: "none"
            ),
            confidenceScore: 0.0,
            isBiological: false,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        engine.speciesData = species
        viewModel.inferenceEngine = engine

        #expect(species.isInferenceErrorPlaceholder == true)
        #expect(species.isClassifiedNonBiological == false)
        #expect(viewModel.contentMode == .nonBiological)
        #expect(viewModel.resolvedHeaderTitle == "Network timeout")
    }

    @Test func testRestoringScanPlaceholderKeepsRecoveryTitle() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        let species = SpeciesData(
            scanId: nil,
            commonName: "Restoring scan",
            scientificName: "Safely saved",
            insightData: InsightData(
                aiReasoning: "Your scan reached Naturebook safely. We’re restoring its saved result now.",
                hazardType: "none"
            ),
            confidenceScore: 0.0,
            isBiological: false,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        engine.speciesData = species
        viewModel.inferenceEngine = engine

        #expect(species.isInferenceErrorPlaceholder)
        #expect(!species.isClassifiedNonBiological)
        #expect(viewModel.resolvedHeaderTitle == "Restoring scan")
    }

    @Test func testNetworkTimeoutPlaceholderDoesNotShowNonBiologicalSuccessToast() throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: nil,
            commonName: "Network timeout",
            scientificName: "Offline mode",
            insightData: InsightData(
                aiReasoning: "Naturebook saved this scan and will retry automatically.",
                hazardType: "none"
            ),
            confidenceScore: 0.0,
            isBiological: false,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        viewModel.inferenceEngine = engine

        viewModel.evaluateProcessingCompletion(
            isStillProcessing: false,
            inferenceEngine: engine,
            modelContext: ctx
        )

        #expect(viewModel.state.toastMessage == nil)
    }

    @Test func successfulResultCommitTransitionsRouterWithCompletedCarousel() {
        let engine = InferenceEngine()
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)
        let scanId = "router-result-commit"
        let attemptGeneration = UUID()
        engine.activeScanId = scanId
        engine.activeLiveInferenceAttemptGeneration =
            attemptGeneration
        engine.isProcessing = true
        engine.activeMedia = ActiveScanMedia(items: [.liveImage(Data([0x01]))])

        #expect(viewModel.contentMode == .analyzing)

        let species = SpeciesData(
            scanId: scanId,
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings with black veins.", hazardType: "none"),
            confidenceScore: 0.97,
            referenceImageUrl: "https://example.com/one.jpg,https://example.com/two.jpg",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        let didCommit = engine.commitSuccessfulResult(
            for: scanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: nil,
            speciesData: species,
            persistedMediaItems: [.image("documents/router-result.webp")]
        )

        #expect(didCommit)
        #expect(viewModel.contentMode == .biological)
        #expect(viewModel.resolvedHeaderTitle == "Monarch Butterfly")
        #expect(viewModel.activeMedia.totalItems == 3)
        #expect(viewModel.isProcessing == false)
    }

    @Test func successfulProcessingCompletionUsesSingleResultHapticSource() throws {
        let ctx = try createIsolatedContext()
        let engine = InferenceEngine()
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)
        engine.speciesData = SpeciesData(
            scanId: "successful-haptic",
            commonName: "Field Notebook",
            scientificName: "Not applicable",
            insightData: InsightData(aiReasoning: "A non-biological object.", hazardType: "none"),
            confidenceScore: 0.95,
            isBiological: false,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )

        viewModel.evaluateProcessingCompletion(
            isStillProcessing: false,
            inferenceEngine: engine,
            modelContext: ctx
        )

        #expect(HapticManager.shared.lastAttempt?.event == "heavyImpact")
        #expect(HapticManager.shared.lastAttempt?.source == "insight.analysis.completed")
    }

    @Test func inferenceErrorCompletionDoesNotEmitResultHaptic() throws {
        let ctx = try createIsolatedContext()
        let engine = InferenceEngine()
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)
        HapticManager.shared.triggerSelectionPulse(source: "test.error-completion-baseline")
        engine.speciesData = SpeciesData(
            scanId: nil,
            commonName: "Network timeout",
            scientificName: "Offline mode",
            insightData: InsightData(
                aiReasoning: "Naturebook saved this scan and will retry automatically.",
                hazardType: "none"
            ),
            confidenceScore: 0,
            isBiological: false,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )

        viewModel.evaluateProcessingCompletion(
            isStillProcessing: false,
            inferenceEngine: engine,
            modelContext: ctx
        )

        #expect(HapticManager.shared.lastAttempt?.source == "test.error-completion-baseline")
    }

    private func milestoneTestSpecies(
        commonName: String = "Monarch Butterfly",
        isBiological: Bool = true
    ) -> SpeciesData {
        SpeciesData(
            scanId: "milestone_scan",
            commonName: commonName,
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings with black veins.", hazardType: "none"),
            confidenceScore: 0.97,
            isBiological: isBiological,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
    }

    @Test func testTopMenuHidesConfirmAndReviewForStrongNonCompetitiveCandidates() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "strong_hidden_candidates",
            commonName: "Genista Broom Moth",
            scientificName: "Uresiphita reversalis",
            insightData: InsightData(aiReasoning: "A strong identification.", hazardType: "none"),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            inferenceTier: "flash",
            candidates: [
                IdentificationCandidate(
                    scientificName: "Pieris rapae",
                    commonName: "Cabbage White",
                    confidenceScore: 0.70
                )
            ]
        )
        viewModel.inferenceEngine = engine
        bindToolbarPresentation(
            viewModel,
            scanId: "strong_hidden_candidates"
        )

        #expect(viewModel.canConfirm == false)
        #expect(viewModel.canReviewAlternatives == false)
        #expect(viewModel.canReanalyze == true)
    }

    @Test func testIdentificationConcernCandidatesUseStoredAlternativesWithoutChangingToolbarPolicy() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "strong_hidden_candidates",
            commonName: "Genista Broom Moth",
            scientificName: "Uresiphita reversalis",
            insightData: InsightData(aiReasoning: "A strong identification.", hazardType: "none"),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            inferenceTier: "flash",
            candidates: [
                IdentificationCandidate(
                    scientificName: "Pieris rapae",
                    commonName: "Cabbage White",
                    confidenceScore: 0.70
                )
            ]
        )
        viewModel.inferenceEngine = engine
        bindToolbarPresentation(
            viewModel,
            scanId: "strong_hidden_candidates"
        )

        #expect(viewModel.canReviewAlternatives == false)
        #expect(viewModel.canReviewIdentificationConcernCandidates == true)
        #expect(viewModel.candidateSwipeCandidates.isEmpty)

        viewModel.presentCandidateSwipe(source: .identificationConcern)

        #expect(viewModel.candidateSwipeCandidates.map(\.scientificName) == ["Pieris rapae"])
        #expect(
            viewModel.state.candidateSwipeEnginePresentationGeneration ==
                engine.scanPresentationGeneration
        )
    }

    @Test func testTopMenuShowsConfirmAndReviewForVisibleCompetitiveCandidates() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "strong_competitive_candidates",
            commonName: "Genista Broom Moth",
            scientificName: "Uresiphita reversalis",
            insightData: InsightData(aiReasoning: "A competitive alternative exists.", hazardType: "none"),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            inferenceTier: "flash",
            candidates: [
                IdentificationCandidate(
                    scientificName: "Pieris rapae",
                    commonName: "Cabbage White",
                    confidenceScore: 0.82
                )
            ]
        )
        viewModel.inferenceEngine = engine
        bindToolbarPresentation(
            viewModel,
            scanId: "strong_competitive_candidates"
        )

        #expect(viewModel.canConfirm == true)
        #expect(viewModel.canReviewAlternatives == true)
        #expect(viewModel.canReanalyze == true)
    }

    @Test func testShareRecommendationUsesFlashStrongThreshold() {
        let lowConfidence = shareRecommendationViewModel(confidence: 0.94, inferenceTier: "flash")
        #expect(lowConfidence.shareRecommendation == .askCommunity)
        #expect(lowConfidence.requiresExplorePublishConfirmation == true)

        let strongConfidence = shareRecommendationViewModel(confidence: 0.95, inferenceTier: "flash")
        #expect(strongConfidence.shareRecommendation == .publishToExplore)
        #expect(strongConfidence.requiresExplorePublishConfirmation == false)
    }

    @Test func testShareRecommendationUsesProStrongThreshold() {
        let lowConfidence = shareRecommendationViewModel(confidence: 0.84, inferenceTier: "pro")
        #expect(lowConfidence.shareRecommendation == .askCommunity)

        let strongConfidence = shareRecommendationViewModel(confidence: 0.85, inferenceTier: "pro")
        #expect(strongConfidence.shareRecommendation == .publishToExplore)
    }

    @Test func testShareRecommendationTreatsMissingConfidenceAsAskCommunity() {
        let missingConfidenceFallback = shareRecommendationViewModel(confidence: 0, inferenceTier: nil)
        #expect(missingConfidenceFallback.shareRecommendation == .askCommunity)
        #expect(missingConfidenceFallback.requiresExplorePublishConfirmation == true)
    }

    @Test func testShareRecommendationTreatsReviewedIdentificationAsExploreReady() {
        let confirmed = shareRecommendationViewModel(
            confidence: 0.42,
            inferenceTier: "flash",
            userConfirmedIdentification: true
        )
        #expect(confirmed.shareRecommendation == .publishToExplore)

        let overridden = shareRecommendationViewModel(
            confidence: 0.42,
            inferenceTier: "flash",
            userIdentificationOverride: "Rosa gallica"
        )
        #expect(overridden.shareRecommendation == .publishToExplore)
    }

    @Test func testShareRecommendationRestoresCommunityRequestStates() {
        let pending = shareRecommendationViewModel(confidence: 0.99, inferenceTier: "flash")
        pending.state.sharedCommunityIdentificationRequestId = "request_pending"
        pending.state.sharedCommunityIdentificationStatus = .needsId
        #expect(pending.shareRecommendation == .communityPending)

        let resolved = shareRecommendationViewModel(confidence: 0.99, inferenceTier: "flash")
        resolved.state.sharedCommunityIdentificationRequestId = "request_resolved"
        resolved.state.sharedCommunityIdentificationStatus = .resolved
        #expect(resolved.shareRecommendation == .communityResolvedNeedsPublish)

        resolved.state.sharedExplorePostId = "post_visible"
        resolved.state.isExploreFeedVisible = true
        #expect(resolved.shareRecommendation == .publishToExplore)
    }

    @Test func testTopMenuStateShowsExplorePostActionsForPublishedPost() {
        let state = InsightTopMenuState(
            sharedExplorePostId: "post_123",
            sharedCommunityIdentificationRequestId: nil,
            canEditExplorePost: true,
            canViewExplorePost: true,
            canAskCommunity: true,
            canViewCommunityRequest: false
        )

        #expect(state.showsExplorePostSection == true)
        #expect(state.communityAction == .askCommunity)
    }

    @Test func testTopMenuStateHidesExplorePostActionsWithoutPublishedPost() {
        let state = InsightTopMenuState(
            sharedExplorePostId: nil,
            sharedCommunityIdentificationRequestId: nil,
            canEditExplorePost: true,
            canViewExplorePost: true,
            canAskCommunity: true,
            canViewCommunityRequest: false
        )

        #expect(state.showsExplorePostSection == false)
        #expect(state.communityAction == .askCommunity)
    }

    @Test func testTopMenuStateUsesViewCommunityRequestWhenRequestExists() {
        let state = InsightTopMenuState(
            sharedExplorePostId: "post_123",
            sharedCommunityIdentificationRequestId: "request_123",
            canEditExplorePost: true,
            canViewExplorePost: true,
            canAskCommunity: true,
            canViewCommunityRequest: true
        )

        #expect(state.showsExplorePostSection == true)
        #expect(state.communityAction == .viewCommunityRequest)
        #expect(state.communityAction?.title == "View community request")
    }

    @Test func testTopMenuStateUsesAskCommunityWhenNoRequestExists() {
        let state = InsightTopMenuState(
            sharedExplorePostId: "post_123",
            sharedCommunityIdentificationRequestId: nil,
            canEditExplorePost: true,
            canViewExplorePost: true,
            canAskCommunity: true,
            canViewCommunityRequest: true
        )

        #expect(state.communityAction == .askCommunity)
        #expect(state.communityAction?.title == "Ask the community")
    }

    @Test func testFetchLocalRecord() async throws {
        // Validation that the viewmodel gracefully pulls state and assigns local memory
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        
        // Assert initial unassigned state
        #expect(viewModel.activeLocalRecord == nil)
        
        let record = LocalScanRecord(speciesId: "fetch_test_1", scientificName: "Equus caballus", commonName: "Horse")
        // Overriding default initializer value manually to test the read receipt flip logic isolated.
        record.hasBeenViewed = false
        
        let recordId = record.id
        ctx.insert(record)
        try ctx.save()
        viewModel.inferenceEngine = biologicalEngine(scanId: recordId)
        
        viewModel.fetchLocalRecord(for: recordId, modelContext: ctx)
        
        #expect(viewModel.activeLocalRecord?.id == recordId)
        #expect(viewModel.activeLocalRecord?.hasBeenViewed == true, "fetchLocalRecord must actively flag the read-receipt to false the unread states across the app ecosystem")
    }

    @Test func testFetchLocalRecordHydratesSharedExplorePostIdFromCache() async throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(speciesId: "shared_fetch_test", scientificName: "Rosa", commonName: "Rose")
        let sharedPostId = "post_\(UUID().uuidString)"

        ctx.insert(record)
        try ctx.save()
        ExploreShareStateStore.setSharedPostId(sharedPostId, for: record.id)
        defer { ExploreShareStateStore.setSharedPostId(nil, for: record.id) }

        viewModel.fetchLocalRecord(for: record.id, modelContext: ctx)

        #expect(viewModel.activeLocalRecord?.id == record.id)
        #expect(viewModel.state.sharedExplorePostId == sharedPostId)
    }

    @Test func testMissingDifferentRecordClearsStaleScanBoundState() async throws {
        let ctx = try createIsolatedContext()
        let staleScan = LocalScanRecord(
            speciesId: "stale_identity_species",
            scientificName: "Quercus alba",
            commonName: "White Oak",
            fieldNotes: "Old observation"
        )
        ctx.insert(staleScan)
        try ctx.save()

        let viewModel = InsightSheetViewModel()
        viewModel.inferenceEngine = biologicalEngine(scanId: staleScan.id)
        #expect(viewModel.fetchLocalRecord(for: staleScan.id, modelContext: ctx))
        viewModel.state.sharedExplorePostId = UUID().uuidString.lowercased()
        viewModel.state.sharedCommunityIdentificationRequestId = UUID().uuidString.lowercased()
        viewModel.state.sharedCommunityIdentificationStatus = .needsId
        viewModel.state.isExploreFeedVisible = true
        viewModel.state.sharedExploreHashtags = ["stale"]
        viewModel.state.fieldNotesText = "Old observation"
        viewModel.toastActionTitle = "View"
        viewModel.toastAction = {}

        let newScanId = UUID().uuidString.lowercased()
        viewModel.inferenceEngine = biologicalEngine(scanId: newScanId)

        #expect(!viewModel.fetchLocalRecord(for: newScanId, modelContext: ctx))
        #expect(viewModel.activeLocalRecord == nil)
        #expect(viewModel.activeLocalRecordId == nil)
        #expect(viewModel.toolbarRecordSnapshot == nil)
        #expect(viewModel.state.sharedExplorePostId == nil)
        #expect(viewModel.state.sharedCommunityIdentificationRequestId == nil)
        #expect(viewModel.state.sharedCommunityIdentificationStatus == nil)
        #expect(viewModel.state.isExploreFeedVisible == false)
        #expect(viewModel.state.sharedExploreHashtags.isEmpty)
        #expect(viewModel.state.fieldNotesText.isEmpty)
        #expect(viewModel.toastActionTitle == nil)
        #expect(viewModel.toastAction == nil)
        #expect(viewModel.presentedSpeciesScanId == newScanId)
    }

    @Test func testRecordSwitchInvalidatesPriorActionGeneration() async throws {
        let ctx = try createIsolatedContext()
        let firstScan = LocalScanRecord(
            speciesId: "first_generation_species",
            scientificName: "Quercus alba",
            commonName: "White Oak"
        )
        let secondScan = LocalScanRecord(
            speciesId: "second_generation_species",
            scientificName: "Acer rubrum",
            commonName: "Red Maple"
        )
        ctx.insert(firstScan)
        ctx.insert(secondScan)
        try ctx.save()

        let viewModel = InsightSheetViewModel()
        viewModel.inferenceEngine = biologicalEngine(scanId: firstScan.id)
        #expect(viewModel.fetchLocalRecord(for: firstScan.id, modelContext: ctx))
        let firstGeneration = viewModel.scanBoundActionGeneration
        viewModel.state.isSharingToExplore = true
        viewModel.state.isUpdatingExplorePostContent = true
        viewModel.state.isUpdatingExploreFieldNotes = true
        viewModel.state.isRequestingCommunityIdentification = true
        viewModel.state.isFieldNotesSheetPresented = true
        viewModel.state.fieldNotesPresentationScanId = firstScan.id
        viewModel.state.fieldNotesPresentationGeneration = firstGeneration
        viewModel.state.isInsightChatSheetPresented = true
        viewModel.state.isCandidateSwipePresented = true
        viewModel.state.candidateSwipePresentationScanId = firstScan.id
        viewModel.state.candidateSwipePresentationGeneration = firstGeneration
        viewModel.state.candidateSwipeEnginePresentationGeneration =
            viewModel.inferenceEngine?.scanPresentationGeneration
        viewModel.state.isSafariPresented = true
        viewModel.state.selectedWikiURL = URL(string: "https://en.wikipedia.org/wiki/Quercus_alba")
        viewModel.state.safariPresentationScanId = firstScan.id
        viewModel.state.safariPresentationGeneration = firstGeneration
        viewModel.state.showBottomBarTools = true
        viewModel.state.isExplorePostComposerPresented = true
        viewModel.state.explorePostComposerPresentationScanId = firstScan.id
        viewModel.state.explorePostComposerPresentationGeneration = firstGeneration
        viewModel.state.explorePostComposerPresentationPostId =
            UUID().uuidString.lowercased()
        viewModel.state.showExploreOnboarding = true
        viewModel.state.exploreOnboardingPresentationScanId = firstScan.id
        viewModel.state.exploreOnboardingPresentationGeneration = firstGeneration
        viewModel.state.isCommunityRequestSheetPresented = true
        viewModel.state.communityRequestPresentationScanId = firstScan.id
        viewModel.state.communityRequestPresentationGeneration = firstGeneration
        viewModel.state.communityRequestPresentationRequestId =
            UUID().uuidString.lowercased()
        viewModel.state.showExploreSheet = true
        viewModel.state.explorePresentationTarget = .post
        viewModel.state.explorePresentationScanId = firstScan.id
        viewModel.state.explorePresentationGeneration = firstGeneration

        viewModel.inferenceEngine = biologicalEngine(scanId: secondScan.id)
        #expect(viewModel.fetchLocalRecord(for: secondScan.id, modelContext: ctx))

        #expect(viewModel.scanBoundActionGeneration != firstGeneration)
        #expect(!viewModel.isPresentingLocalRecord(
            scanId: firstScan.id,
            generation: firstGeneration
        ))
        #expect(viewModel.isPresentingLocalRecord(scanId: secondScan.id))
        #expect(viewModel.state.isSharingToExplore == false)
        #expect(viewModel.state.isUpdatingExplorePostContent == false)
        #expect(viewModel.state.isUpdatingExploreFieldNotes == false)
        #expect(viewModel.state.isRequestingCommunityIdentification == false)
        #expect(viewModel.state.isFieldNotesSheetPresented == false)
        #expect(viewModel.state.fieldNotesPresentationScanId == nil)
        #expect(viewModel.state.fieldNotesPresentationGeneration == nil)
        #expect(viewModel.state.isInsightChatSheetPresented == false)
        #expect(viewModel.state.isCandidateSwipePresented == false)
        #expect(viewModel.state.candidateSwipePresentationScanId == nil)
        #expect(viewModel.state.candidateSwipePresentationGeneration == nil)
        #expect(viewModel.state.candidateSwipeEnginePresentationGeneration == nil)
        #expect(viewModel.state.isSafariPresented == false)
        #expect(viewModel.state.selectedWikiURL == nil)
        #expect(viewModel.state.safariPresentationScanId == nil)
        #expect(viewModel.state.safariPresentationGeneration == nil)
        #expect(viewModel.state.showBottomBarTools == false)
        #expect(viewModel.state.isExplorePostComposerPresented == false)
        #expect(viewModel.state.explorePostComposerPresentationScanId == nil)
        #expect(viewModel.state.explorePostComposerPresentationGeneration == nil)
        #expect(viewModel.state.explorePostComposerPresentationPostId == nil)
        #expect(viewModel.state.showExploreOnboarding == false)
        #expect(viewModel.state.exploreOnboardingPresentationScanId == nil)
        #expect(viewModel.state.exploreOnboardingPresentationGeneration == nil)
        #expect(viewModel.state.isCommunityRequestSheetPresented == false)
        #expect(viewModel.state.communityRequestPresentationScanId == nil)
        #expect(viewModel.state.communityRequestPresentationGeneration == nil)
        #expect(viewModel.state.communityRequestPresentationRequestId == nil)
        #expect(viewModel.state.showExploreSheet == false)
        #expect(viewModel.state.explorePresentationTarget == .automatic)
        #expect(viewModel.state.explorePresentationScanId == nil)
        #expect(viewModel.state.explorePresentationGeneration == nil)

        viewModel.presentExplore(
            target: .post,
            expectedScanId: firstScan.id,
            expectedGeneration: firstGeneration
        )
        #expect(viewModel.state.showExploreSheet == false)
    }

    @Test func testExploreSharingRequiresExactEngineAndRecordIdentity() throws {
        let viewModel = shareRecommendationViewModel(
            confidence: 0.99,
            inferenceTier: "flash"
        )
        let scanId = try #require(viewModel.inferenceEngine?.speciesData?.scanId)

        #expect(viewModel.presentedSpeciesScanId == scanId)
        #expect(viewModel.canShareToExplore)

        let postId = UUID().uuidString.lowercased()
        let requestId = UUID().uuidString.lowercased()
        viewModel.state.sharedExplorePostId = postId
        viewModel.state.sharedCommunityIdentificationRequestId = requestId
        viewModel.presentExplorePostComposer(
            expectedScanId: scanId,
            expectedGeneration: viewModel.scanBoundActionGeneration
        )
        viewModel.presentCommunityIdentificationRequest(
            expectedScanId: scanId,
            expectedGeneration: viewModel.scanBoundActionGeneration
        )
        #expect(viewModel.state.explorePostComposerPresentationPostId == postId)
        #expect(viewModel.state.communityRequestPresentationRequestId == requestId)

        viewModel.activeLocalRecordId = UUID().uuidString.lowercased()
        viewModel.inferenceEngine?.activeScanId = UUID().uuidString.lowercased()

        #expect(viewModel.presentedSpeciesScanId == nil)
        #expect(!viewModel.canShareToExplore)
        #expect(viewModel.persistentScanId == scanId)
    }

    @Test func testPreferredNameRejectsStalePresentationGeneration() async throws {
        let context = try createIsolatedContext()
        let first = LocalScanRecord(
            speciesId: "preferred_name_generation_1",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        let second = LocalScanRecord(
            speciesId: "preferred_name_generation_2",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        context.insert(first)
        context.insert(second)
        try context.save()
        let viewModel = InsightSheetViewModel()
        viewModel.inferenceEngine = biologicalEngine(scanId: first.id)
        #expect(viewModel.fetchLocalRecord(for: first.id, modelContext: context))
        let staleGeneration = viewModel.scanBoundActionGeneration

        viewModel.inferenceEngine = biologicalEngine(scanId: second.id)
        #expect(viewModel.fetchLocalRecord(for: second.id, modelContext: context))
        viewModel.inferenceEngine = biologicalEngine(scanId: first.id)
        #expect(viewModel.fetchLocalRecord(for: first.id, modelContext: context))

        viewModel.setPreferredCommonName(
            "Stale Monarch Name",
            for: "Danaus plexippus",
            expectedScanId: first.id,
            expectedGeneration: staleGeneration,
            modelContext: context
        )

        #expect(
            SpeciesPreferredNameRepository.preferredName(
                for: "Danaus plexippus",
                modelContext: context
            ) == nil
        )
        #expect(viewModel.state.toastMessage == nil)
    }

    private func shareRecommendationViewModel(
        confidence: Double,
        inferenceTier: String?,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false
    ) -> InsightSheetViewModel {
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "share_recommendation_species",
            scientificName: "Rosa gallica",
            commonName: "French Rose",
            coverImagePath: "rose.webp"
        )
        viewModel.activeLocalRecord = record
        viewModel.activeLocalRecordId = record.id
        viewModel.toolbarRecordSnapshot = InsightToolbarRecordSnapshot(record: record)

        let engine = InferenceEngine()
        engine.activeMedia = ActiveScanMedia(items: [.image("rose.webp")])
        engine.speciesData = SpeciesData(
            scanId: record.id,
            commonName: "French Rose",
            scientificName: "Rosa gallica",
            insightData: InsightData(aiReasoning: "A rose with visible petals.", hazardType: "none"),
            confidenceScore: confidence,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            inferenceTier: inferenceTier,
            userIdentificationOverride: userIdentificationOverride,
            userConfirmedIdentification: userConfirmedIdentification
        )
        viewModel.inferenceEngine = engine
        return viewModel
    }

    @Test func testToolbarSnapshotSurvivesLocalRecordDeletion() async throws {
        let ctx = try createIsolatedContext()
        let collection = ScanCollection(name: "Favorites")
        let record = LocalScanRecord(
            speciesId: "toolbar_snapshot_species",
            scientificName: "Bombus testus",
            commonName: "Test Bumblebee",
            coverImagePath: "scan.webp",
            semanticTags: ["bee", "pollinator"],
            taxonomyKingdom: "Animalia",
            taxonomyClass: "Insecta",
            taxonomyOrder: "Hymenoptera",
            taxonomyFamily: "Apidae",
            habitatDescription: "Meadow edge",
            imageQualityScore: 91
        )
        record.collections = [collection]
        ctx.insert(collection)
        ctx.insert(record)
        try ctx.save()

        let recordId = record.id
        let collectionId = collection.id
        let snapshot = InsightToolbarRecordSnapshot(record: record)
        ScanRepository.shared.eradicateScan(record: record, modelContext: ctx)

        #expect(snapshot.scanId == recordId)
        #expect(snapshot.coverImagePath == "scan.webp")
        #expect(snapshot.semanticTags == ["bee", "pollinator"])
        #expect(snapshot.taxonomyClass == "Insecta")
        #expect(snapshot.habitatDescription == "Meadow edge")
        #expect(snapshot.imageQualityScore == 91)
        #expect(snapshot.collectionIds == Set([collectionId]))
    }

    @Test func testFieldNotesRepositoryDoesNotTouchDeletedActiveRecord() async throws {
        let ctx = try createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "deleted_field_notes_species",
            scientificName: "Deleted specimen",
            commonName: "Deleted scan",
            fieldNotes: "Original note"
        )

        ctx.insert(record)
        try ctx.save()

        let recordId = record.id
        let bridgedNote = "Recovered bridge note"
        FieldNotesStore.setFieldNotes(bridgedNote, for: recordId)
        defer { FieldNotesStore.setFieldNotes(nil, for: recordId) }

        ScanRepository.shared.eradicateScan(record: record, modelContext: ctx)

        let resolvedNotes = FieldNotesRepository.fieldNotes(
            for: recordId,
            modelContext: ctx
        )

        #expect(resolvedNotes == bridgedNote)
    }

    @Test func testRefreshSharedExploreStateClearsMissingCache() async throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(speciesId: "shared_refresh_test", scientificName: "Quercus", commonName: "Oak")

        ctx.insert(record)
        try ctx.save()

        viewModel.fetchLocalRecord(for: record.id, modelContext: ctx)
        viewModel.state.sharedExplorePostId = "stale_post_id"

        ExploreShareStateStore.setSharedPostId(nil, for: record.id)
        viewModel.refreshSharedExploreStateFromLocalCache()

        #expect(viewModel.state.sharedExplorePostId == nil)
    }

    @Test func testLocalCacheRefreshPreservesRestoredCommunityRequestState() async throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(speciesId: "community_refresh_test", scientificName: "Rosa", commonName: "Rose")

        ctx.insert(record)
        try ctx.save()

        viewModel.fetchLocalRecord(for: record.id, modelContext: ctx)
        viewModel.state.sharedCommunityIdentificationRequestId = "request_refresh_test"
        viewModel.state.sharedCommunityIdentificationStatus = .needsId

        ExploreShareStateStore.setSharedPostId(nil, for: record.id)
        viewModel.refreshSharedExploreStateFromLocalCache()

        #expect(viewModel.state.sharedCommunityIdentificationRequestId == "request_refresh_test")
        #expect(viewModel.state.sharedCommunityIdentificationStatus == .needsId)
        #expect(viewModel.state.sharedExplorePostId == nil)
    }

    @Test func testPublishedExploreFieldNotesPromoteWhenLocalRecordIsEmpty() async throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "field_notes_repair_species",
            scientificName: "Quercus alba",
            commonName: "White Oak"
        )
        let notes = "Observed along the shaded creek edge."

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        viewModel.inferenceEngine = biologicalEngine(scanId: record.id)
        viewModel.bindPresentedRecord(record, modelContext: ctx)
        #expect(viewModel.fieldNotesText.isEmpty)

        viewModel.promotePublishedExploreFieldNotesIfLocalMissing(
            "  \(notes)  ",
            modelContext: ctx
        )

        #expect(viewModel.fieldNotesText == notes)
        #expect(record.fieldNotes == notes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == notes)
    }

    @Test func testPublishedExploreFieldNotesDoNotOverwriteLocalPrivateNotes() async throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "field_notes_private_species",
            scientificName: "Acer rubrum",
            commonName: "Red Maple",
            fieldNotes: "Private local note"
        )

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        viewModel.inferenceEngine = biologicalEngine(scanId: record.id)
        viewModel.bindPresentedRecord(record, modelContext: ctx)
        viewModel.promotePublishedExploreFieldNotesIfLocalMissing(
            "Published Explore note",
            modelContext: ctx
        )

        #expect(viewModel.fieldNotesText == "Private local note")
        #expect(record.fieldNotes == "Private local note")
        #expect(FieldNotesStore.fieldNotes(for: record.id) == "Private local note")
    }

    @Test func testShareComposerFieldNotesSyncImmediatelyIntoInsightState() async throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "share_composer_field_notes_species",
            scientificName: "Cyprinella lutrensis",
            commonName: "Red Shiner"
        )
        let notes = "Schooling in a shallow creek after rain."

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        viewModel.inferenceEngine = biologicalEngine(scanId: record.id)
        viewModel.bindPresentedRecord(record, modelContext: ctx)
        viewModel.state.dismissedFieldNotesCardScanId = record.id

        viewModel.syncComposerFieldNotes(notes, modelContext: ctx)

        #expect(viewModel.fieldNotesText == notes)
        #expect(record.fieldNotes == notes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == notes)
        #expect(viewModel.state.dismissedFieldNotesCardScanId == nil)
    }

    @Test func testFieldNotesRepositoryPromotesLegacyStoreIntoLocalRecord() async throws {
        let ctx = try createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "legacy_field_notes_species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        let legacyNotes = "Legacy bridged note"

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(legacyNotes, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        let resolvedNotes = FieldNotesRepository.fieldNotes(
            for: record.id,
            modelContext: ctx
        )

        #expect(resolvedNotes == legacyNotes)
        #expect(record.fieldNotes == legacyNotes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == legacyNotes)
    }

    @Test func testFieldNotesRepositoryClearsLocalRecordAndLegacyBridgeTogether() async throws {
        let ctx = try createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "clear_field_notes_species",
            scientificName: "Amanita muscaria",
            commonName: "Fly Agaric",
            fieldNotes: "Private note to clear"
        )

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(record.fieldNotes, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        FieldNotesRepository.setFieldNotes(
            "   ",
            for: record.id,
            modelContext: ctx
        )

        #expect(record.fieldNotes == nil)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == nil)
    }

    @Test func testFieldNotesRepositoryMirrorsUnchangedLocalRecordIntoLegacyBridge() async throws {
        let ctx = try createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "unchanged_field_notes_species",
            scientificName: "Taraxacum officinale",
            commonName: "Common Dandelion",
            fieldNotes: "Already saved locally"
        )

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        let changed = FieldNotesRepository.setFieldNotes(
            "Already saved locally",
            for: record.id,
            modelContext: ctx
        )

        #expect(changed == false)
        #expect(record.fieldNotes == "Already saved locally")
        #expect(FieldNotesStore.fieldNotes(for: record.id) == "Already saved locally")
    }

    @Test func testFieldNotesRepositoryPersistsBridgeOnlyWhenNoSwiftDataRecordExists() async throws {
        let ctx = try createIsolatedContext()
        let scanId = "bridge_only_field_notes_scan"

        FieldNotesStore.setFieldNotes(nil, for: scanId)
        defer { FieldNotesStore.setFieldNotes(nil, for: scanId) }

        let changed = FieldNotesRepository.setFieldNotes(
            "Bridge-only note",
            for: scanId,
            modelContext: ctx
        )

        #expect(changed == true)
        #expect(FieldNotesStore.fieldNotes(for: scanId) == "Bridge-only note")
    }

    @Test func testQueuedScanFieldNotesPersistToOfflineRecord() async throws {
        let ctx = try createIsolatedContext()
        let queuedScan = OfflineQueuedScan(id: "queued_field_notes_scan")

        ctx.insert(queuedScan)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: queuedScan.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: queuedScan.id) }

        let viewModel = InsightSheetViewModel(queuedContext: QueuedScanContext(from: queuedScan))
        viewModel.syncFieldNotesFromCurrentScan(modelContext: ctx)
        #expect(viewModel.currentFieldNotesScanId == queuedScan.id)
        #expect(viewModel.shouldShowFieldNotesCard == true)

        viewModel.updateFieldNotes("Queued field note", modelContext: ctx)

        #expect(viewModel.fieldNotesText == "Queued field note")
        #expect(queuedScan.fieldNotes == "Queued field note")
        #expect(FieldNotesStore.fieldNotes(for: queuedScan.id) == "Queued field note")
    }

    @Test func testFieldNotesRejectChangedPresentationIdentity() async throws {
        let ctx = try createIsolatedContext()
        let queuedScan = OfflineQueuedScan(id: "current_field_notes_scan")
        ctx.insert(queuedScan)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: queuedScan.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: queuedScan.id) }

        let viewModel = InsightSheetViewModel(
            queuedContext: QueuedScanContext(from: queuedScan)
        )
        viewModel.syncFieldNotesFromCurrentScan(modelContext: ctx)

        viewModel.presentFieldNotes(expectedScanId: "previous_field_notes_scan")
        viewModel.updateFieldNotes(
            "Stale note",
            expectedScanId: "previous_field_notes_scan",
            modelContext: ctx
        )

        #expect(viewModel.state.isFieldNotesSheetPresented == false)
        #expect(viewModel.state.fieldNotesPresentationScanId == nil)
        #expect(viewModel.state.fieldNotesPresentationGeneration == nil)
        #expect(viewModel.fieldNotesText.isEmpty)
        #expect(queuedScan.fieldNotes == nil)

        viewModel.presentFieldNotes(expectedScanId: queuedScan.id)

        #expect(viewModel.state.isFieldNotesSheetPresented)
        #expect(viewModel.state.fieldNotesPresentationScanId == queuedScan.id)
        #expect(
            viewModel.state.fieldNotesPresentationGeneration ==
                viewModel.scanBoundActionGeneration
        )
    }

    @Test func testQueuedRefreshRejectsChangedPresentationIdentity() {
        let first = QueuedScanContext(
            id: "queued_scan_1",
            capturedMediaItems: [.image("first.webp")],
            queueState: .pending,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let second = QueuedScanContext(
            id: "queued_scan_2",
            capturedMediaItems: [.image("second-old.webp")],
            queueState: .pending,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let staleFirstRefresh = QueuedScanContext(
            id: first.id,
            capturedMediaItems: [.image("stale-first.webp")],
            queueState: .failed,
            timestamp: first.timestamp,
            queueLastErrorCode: "stale"
        )
        let currentSecondRefresh = QueuedScanContext(
            id: second.id,
            capturedMediaItems: [.image("second-new.webp")],
            queueState: .uploading,
            timestamp: second.timestamp
        )
        let viewModel = InsightSheetViewModel(queuedContext: first)
        viewModel.queuedContext = second

        #expect(!viewModel.refreshQueuedContextIfCurrent(
            staleFirstRefresh,
            expectedScanId: first.id
        ))
        #expect(viewModel.queuedContext?.id == second.id)
        #expect(viewModel.queuedContext?.queueState == .pending)
        #expect(viewModel.refreshQueuedContextIfCurrent(
            currentSecondRefresh,
            expectedScanId: second.id
        ))
        #expect(viewModel.queuedContext?.queueState == .uploading)
        #expect(
            viewModel.cachedActiveMedia?.imagePathsForUpload ==
                ["second-new.webp"]
        )
    }

    @Test func testQueuedPresentationSwitchInvalidatesPriorQueueIdentity() {
        let first = QueuedScanContext(
            id: "queued_presentation_1",
            capturedMediaItems: [.image("first.webp")],
            queueState: .uploading,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let second = QueuedScanContext(
            id: "queued_presentation_2",
            capturedMediaItems: [.image("second.webp")],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let viewModel = InsightSheetViewModel(queuedContext: first)
        let firstGeneration = viewModel.scanBoundActionGeneration
        viewModel.state.fieldNotesText = "First queued note"
        viewModel.state.isFieldNotesSheetPresented = true
        viewModel.state.fieldNotesPresentationScanId = first.id
        viewModel.state.fieldNotesPresentationGeneration = firstGeneration
        viewModel.state.showDeleteConfirmation = true
        viewModel.state.toastMessage = "First queued toast"

        viewModel.bindQueuedPresentation(second)

        #expect(viewModel.queuedContext?.id == second.id)
        #expect(viewModel.queuedContext?.queueState == .inferencing)
        #expect(viewModel.scanBoundActionGeneration != firstGeneration)
        #expect(viewModel.state.fieldNotesText.isEmpty)
        #expect(!viewModel.state.isFieldNotesSheetPresented)
        #expect(viewModel.state.fieldNotesPresentationScanId == nil)
        #expect(viewModel.state.fieldNotesPresentationGeneration == nil)
        #expect(!viewModel.state.showDeleteConfirmation)
        #expect(viewModel.state.toastMessage == nil)
        #expect(viewModel.cachedActiveMedia?.imagePathsForUpload == ["second.webp"])
    }

    @Test func testQueuedPromotionRejectsChangedPresentationIdentity() throws {
        let context = try createIsolatedContext()
        let firstRecord = LocalScanRecord(
            speciesId: "queued_promotion_species_1",
            scientificName: "Quercus alba",
            commonName: "White Oak"
        )
        let secondRecord = LocalScanRecord(
            speciesId: "queued_promotion_species_2",
            scientificName: "Acer rubrum",
            commonName: "Red Maple"
        )
        secondRecord.hasBeenViewed = false
        context.insert(firstRecord)
        context.insert(secondRecord)
        try context.save()

        let firstContext = QueuedScanContext(
            id: firstRecord.id,
            capturedMediaItems: [],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let secondContext = QueuedScanContext(
            id: secondRecord.id,
            capturedMediaItems: [],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let engine = InferenceEngine()
        let viewModel = InsightSheetViewModel(
            queuedContext: secondContext,
            inferenceEngine: engine
        )
        let queuedGeneration = viewModel.scanBoundActionGeneration

        #expect(!viewModel.promoteQueuedScanIfLocalRecordExists(
            scanId: firstContext.id,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(viewModel.queuedContext?.id == secondContext.id)
        #expect(engine.speciesData == nil)
        #expect(viewModel.promoteQueuedScanIfLocalRecordExists(
            scanId: secondContext.id,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(viewModel.queuedContext == nil)
        #expect(viewModel.scanBoundActionGeneration != queuedGeneration)
        #expect(engine.speciesData?.scanId == secondRecord.id)
        #expect(secondRecord.hasBeenViewed)
    }

    @Test func testQueuedPresentationPrefersPersistedCompletionOverStaleRoute() throws {
        let context = try createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "queued_completed_route_species",
            scientificName: "Cardinalis cardinalis",
            commonName: "Northern Cardinal"
        )
        context.insert(record)
        try context.save()

        let staleQueuedRoute = QueuedScanContext(
            id: record.id,
            capturedMediaItems: [.audio(.documents("cardinal.wav"))],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 3)
        )
        let engine = InferenceEngine()
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)
        let queuedGeneration = viewModel.scanBoundActionGeneration

        #expect(viewModel.bindQueuedPresentationPreferringCompletedRecord(
            staleQueuedRoute,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(viewModel.queuedContext == nil)
        #expect(viewModel.presentedLocalRecordScanId == record.id)
        #expect(engine.speciesData?.scanId == record.id)
        #expect(engine.speciesData?.commonName == "Northern Cardinal")
        #expect(engine.speciesData?.isBiological == true)
        #expect(engine.speciesData?.isHumanSubject == false)
        #expect(viewModel.isProcessing == false)
        #expect(viewModel.scanBoundActionGeneration != queuedGeneration)
        #expect(viewModel.toolbarRecordSnapshot?.scanId == record.id)
        #expect(!viewModel.revealBottomBarTools(
            expectedScanId: record.id,
            expectedGeneration: queuedGeneration
        ))
        #expect(!viewModel.state.showBottomBarTools)
        #expect(viewModel.revealBottomBarTools(
            expectedScanId: record.id,
            expectedGeneration: viewModel.scanBoundActionGeneration
        ))
        #expect(viewModel.state.showBottomBarTools)

        let completedGeneration = viewModel.scanBoundActionGeneration
        #expect(viewModel.bindQueuedPresentationPreferringCompletedRecord(
            staleQueuedRoute,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(viewModel.scanBoundActionGeneration == completedGeneration)
        #expect(viewModel.queuedContext == nil)
        #expect(viewModel.presentedLocalRecordScanId == record.id)
        #expect(viewModel.state.showBottomBarTools)
    }

    @Test func testQueuedPresentationRemainsQueuedWhenCompletionIsAbsent() throws {
        let context = try createIsolatedContext()
        let queuedRoute = QueuedScanContext(
            id: "queued_route_without_completion",
            capturedMediaItems: [.audio(.documents("pending.wav"))],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 4)
        )
        let engine = InferenceEngine()
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)

        #expect(!viewModel.bindQueuedPresentationPreferringCompletedRecord(
            queuedRoute,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(viewModel.queuedContext?.id == queuedRoute.id)
        #expect(viewModel.presentedLocalRecordScanId == nil)
        #expect(engine.speciesData == nil)
        #expect(viewModel.cachedActiveMedia?.items.count == 1)
        #expect(!viewModel.revealBottomBarTools(
            expectedScanId: queuedRoute.id,
            expectedGeneration: viewModel.scanBoundActionGeneration
        ))
        #expect(!viewModel.state.showBottomBarTools)
    }

    @Test func testTotalImagesWithReferenceImageLoading() async throws {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        viewModel.inferenceEngine = engine
        
        // Base state: 1 live captured image, no reference image yet
        engine.activeMedia = ActiveScanMedia(items: [.liveImage(Data())], referenceState: .empty)
        engine.speciesData = SpeciesData(
            scanId: "load_test",
            commonName: "Test",
            scientificName: "Test",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.9,
            referenceImageUrl: nil,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        
        #expect(viewModel.totalImages == 1, "Should count 1 live image only when not loading")
        
        // Toggle hydration flag
        engine.activeMedia.referenceState = .loading
        #expect(viewModel.totalImages == 2, "Should append +1 for the loading skeleton")
        
        // Simulate network resolving and injecting a URL while task clears
        engine.activeMedia.referenceState = .loaded(["https://example.com/gbif.jpg"])
        #expect(viewModel.totalImages == 2, "Should count the real URL and drop skeleton")
        
        engine.activeMedia.referenceState = .loaded(["https://example.com/gbif.jpg"])
        #expect(viewModel.totalImages == 2, "Final state should remain 2 after task cleanup")
    }

    @Test func testHumanSubjectSuppressesReferenceImagesButKeepsUserMedia() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        viewModel.inferenceEngine = engine

        engine.activeMedia = ActiveScanMedia(
            items: [.image("documents/human-capture.webp"), .audio("documents/context.m4a")],
            referenceState: .loaded([
                "https://upload.wikimedia.org/human.jpg",
                "https://static.inaturalist.org/photos/human.jpg"
            ])
        )
        engine.speciesData = SpeciesData(
            scanId: "human_reference_suppression",
            commonName: "Human",
            scientificName: "Homo sapiens",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.96,
            referenceImageUrl: "https://upload.wikimedia.org/human.jpg,https://static.inaturalist.org/photos/human.jpg",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        #expect(viewModel.refUrls.isEmpty)
        #expect(viewModel.activeMedia.items == [.image("documents/human-capture.webp"), .audio("documents/context.m4a")])
        #expect(viewModel.activeMedia.referenceState == .empty)
        #expect(viewModel.totalImages == 2)
    }

    @Test func testDomesticCatAndDogSubjectsSuppressReferenceImagesButKeepUserMedia() {
        let subjects = [
            (commonName: "Domestic cat", scientificName: "Felis catus"),
            (commonName: "Domestic dog", scientificName: "Canis lupus familiaris")
        ]

        for subject in subjects {
            let viewModel = InsightSheetViewModel()
            let engine = InferenceEngine()
            viewModel.inferenceEngine = engine
            engine.activeMedia = ActiveScanMedia(
                items: [.image("documents/user-capture.webp")],
                referenceState: .loaded(["https://example.com/unsuitable-reference.jpg"])
            )
            engine.speciesData = SpeciesData(
                scanId: "domestic_reference_suppression",
                commonName: subject.commonName,
                scientificName: subject.scientificName,
                insightData: InsightData(aiReasoning: "", hazardType: "none"),
                confidenceScore: 0.96,
                referenceImageUrl: "https://example.com/unsuitable-reference.jpg"
            )

            #expect(viewModel.refUrls.isEmpty)
            #expect(viewModel.activeMedia.items == [.image("documents/user-capture.webp")])
            #expect(viewModel.activeMedia.referenceState == .empty)
            #expect(viewModel.totalImages == 1)
        }
    }

    @Test func testWildCatKeepsReferenceImages() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        viewModel.inferenceEngine = engine
        engine.activeMedia = ActiveScanMedia(
            items: [.image("documents/user-capture.webp")],
            referenceState: .loaded(["https://example.com/wildcat-reference.jpg"])
        )
        engine.speciesData = SpeciesData(
            scanId: "wildcat_reference_gallery",
            commonName: "European wildcat",
            scientificName: "Felis silvestris",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.96,
            referenceImageUrl: "https://example.com/wildcat-reference.jpg",
            taxonomy: TaxonomyData(
                kingdom: "Animalia",
                phylum: "Chordata",
                className: "Mammalia",
                order: "Carnivora",
                family: "Felidae",
                genus: "Felis"
            )
        )

        #expect(viewModel.refUrls == ["https://example.com/wildcat-reference.jpg"])
        #expect(viewModel.activeMedia.referenceState == .loaded(["https://example.com/wildcat-reference.jpg"]))
        #expect(viewModel.totalImages == 2)
    }

    @Test func testPersistentScanIdUsesActiveScanIdDuringLiveAnalysis() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.activeScanId = "scan_in_flight_123"
        viewModel.inferenceEngine = engine

        #expect(viewModel.persistentScanId == "scan_in_flight_123", "Carousel identity should stay stable before speciesData arrives")

        engine.speciesData = SpeciesData(
            scanId: "scan_in_flight_123",
            commonName: "Test subject",
            scientificName: "Testus subjectus",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.8,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        engine.activeScanId = nil

        #expect(viewModel.persistentScanId == "scan_in_flight_123", "Carousel identity should remain the same after inference completes")
    }

    @Test func testHasLiveRetainsStatePostInference() async throws {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        viewModel.inferenceEngine = engine
        
        // 1. Simulate initial live capture state
        engine.activeMedia = ActiveScanMedia(items: [.liveImage(Data())])
        #expect(viewModel.activeMedia.liveImageData != nil, "hasLive should be true when activeImageData is present")
        
        // 2. Simulate background task populating validHistoricImagePaths (the previous bug trigger)
        engine.activeMedia.items.append(.image("sandbox/UUID.webp"))
        
        // 3. Assert the Carousel structural teardown is prevented
        #expect(viewModel.activeMedia.liveImageData != nil, "hasLive MUST remain true even when valid paths are populated to prevent LiveCapturePageView from tearing down and causing image disappearance")
        
        // 4. Verify queued scans still correctly override to false
        let queuedScan = OfflineQueuedScan(id: "offline", capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("test.webp")]), encoding: .utf8))
        viewModel.queuedContext = QueuedScanContext(from: queuedScan)
        #expect(viewModel.activeMedia.liveImageData == nil, "hasLive should evaluate to false when viewing a queued scan")
    }

    @Test func testAudioCarouselPagesPersistAfterInferenceCompletes() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        let scanId = "audio_handoff_scan"
        let audioPath = "documents/audio_handoff.wav"
        let imagePath = "documents/audio_handoff.webp"

        engine.activeScanId = scanId
        engine.activeMedia = ActiveScanMedia(items: [.audio(audioPath), .image(imagePath)])
        viewModel.inferenceEngine = engine

        let analyzingPageIDs = CarouselPageBuilder.buildPages(
            for: viewModel.activeMedia,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        ).map(\.id)

        #expect(viewModel.persistentScanId == scanId)
        #expect(analyzingPageIDs == ["audio-\(audioPath)", "image-\(imagePath)"])

        engine.speciesData = SpeciesData(
            scanId: scanId,
            commonName: "Northern Cardinal",
            scientificName: "Cardinalis cardinalis",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.97,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        engine.activeScanId = nil

        let completedPageIDs = CarouselPageBuilder.buildPages(
            for: viewModel.activeMedia,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        ).map(\.id)

        #expect(viewModel.persistentScanId == scanId, "The carousel key should remain stable across the analysis-to-result handoff")
        #expect(completedPageIDs == analyzingPageIDs, "Audio and mixed-media page identity must remain unchanged after inference finishes")
    }

    @Test func testReferenceCarouselPagesCarryAttributionLabels() {
        let media = ActiveScanMedia(referenceState: .loaded([
            "https://media.merian.app/reference.webp",
            "https://upload.wikimedia.org/species.jpg",
            "https://static.inaturalist.org/photos/1/original.jpg"
        ]))

        let pages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: "https://en.wikipedia.org/wiki/Test_species",
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        #expect(pages.map(\.referenceAttributionLabel) == ["Naturebook", "Wikipedia", "GBIF"])
        #expect(pages.map(\.imageOrigin) == [.reference, .reference, .reference])
    }

    @Test func testOriginalPhotoUnavailablePresentationExplainsRetainedIdentification() {
        let presentation = UnavailableVisualContext.originalPhoto.presentation(isOffline: false)

        #expect(presentation.systemImage == "photo.badge.exclamationmark")
        #expect(presentation.title == "Original photo unavailable")
        #expect(presentation.message == "We couldn’t load your photo, but your identification is still available.")
        #expect(
            presentation.accessibilityLabel
                == "Original photo unavailable. We couldn’t load your photo, but your identification is still available."
        )
    }

    @Test func testRemoteOriginalPhotoUnavailablePresentationExplainsOfflineRetry() {
        let presentation = UnavailableVisualContext.originalPhoto.presentation(isOffline: true)

        #expect(presentation.systemImage == "wifi.slash")
        #expect(presentation.title == "Original photo unavailable")
        #expect(presentation.message == "Reconnect to load your photo. Your identification is still available.")
        #expect(
            presentation.accessibilityLabel
                == "Original photo unavailable while offline. Reconnect to load your photo. Your identification is still available."
        )
    }

    @Test func testFailedUserImageIsHiddenAfterReferenceLoads() {
        let unavailablePath = "documents/unavailable.webp"
        let availablePath = "documents/available.webp"
        let videoPath = "documents/observation.mp4"
        let referenceURL = "https://example.com/reference.webp"
        let media = ActiveScanMedia(
            items: [
                .image(unavailablePath),
                .video(videoPath),
                .image(availablePath)
            ],
            referenceState: .loaded([referenceURL])
        )
        let sourcePages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath],
            loadedReferenceIdentifiers: [referenceURL]
        )

        #expect(visiblePages.map(\.id) == [
            "image-\(availablePath)",
            "video-\(videoPath)",
            "reference-\(referenceURL)"
        ])
        #expect(visiblePages[1].id == sourcePages[1].id, "Non-image carousel slots must remain stable")
        #expect(!visiblePages.contains { $0.imageIdentifier == unavailablePath })
        #expect(media.items.contains(.image(unavailablePath)))
    }

    @Test func testFailedUserImageRemainsWithoutUsableReferences() {
        let unavailablePath = "documents/unavailable.webp"

        for referenceState in [ReferenceState.empty, .loading] {
            let sourcePages = CarouselPageBuilder.buildPages(
                for: ActiveScanMedia(
                    items: [.image(unavailablePath)],
                    referenceState: referenceState
                ),
                referenceWikipediaUrl: nil,
                onImageFailure: { _ in },
                onDescriptionTap: nil
            )
            let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
                sourcePages,
                unavailableIdentifiers: [unavailablePath],
                loadedReferenceIdentifiers: []
            )

            #expect(visiblePages.contains { $0.imageIdentifier == unavailablePath })
        }
    }

    @Test func testFailedUserImageRemainsUntilAReferenceLoads() {
        let unavailablePath = "documents/unavailable.webp"
        let referenceURL = "https://example.com/reference.webp"
        let media = ActiveScanMedia(
            items: [.image(unavailablePath)],
            referenceState: .loaded([referenceURL])
        )
        let sourcePages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath],
            loadedReferenceIdentifiers: []
        )

        #expect(visiblePages.contains { $0.imageIdentifier == unavailablePath })
        #expect(visiblePages.contains { $0.imageIdentifier == referenceURL })
    }

    @Test func testFailedUserImageReturnsWhenEveryReferenceFails() {
        let unavailablePath = "documents/unavailable.webp"
        let referenceURL = "https://example.com/reference.webp"
        let media = ActiveScanMedia(
            items: [.image(unavailablePath)],
            referenceState: .loaded([referenceURL])
        )
        let sourcePages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let hiddenPages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath],
            loadedReferenceIdentifiers: [referenceURL]
        )
        let restoredPages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath, referenceURL],
            loadedReferenceIdentifiers: []
        )

        #expect(!hiddenPages.contains { $0.imageIdentifier == unavailablePath })
        #expect(restoredPages.contains { $0.imageIdentifier == unavailablePath })
    }

    @Test func testRemovedSelectedUserImagePrefersLoadedReference() {
        let unavailablePath = "documents/unavailable.webp"
        let availablePath = "documents/available.webp"
        let referenceURL = "https://example.com/reference.webp"
        let media = ActiveScanMedia(
            items: [.image(unavailablePath), .image(availablePath)],
            referenceState: .loaded([referenceURL])
        )
        let sourcePages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )
        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath],
            loadedReferenceIdentifiers: [referenceURL]
        )

        let selectedIndex = CarouselSelectionResolver.selectedIndex(
            preserving: "image-\(unavailablePath)",
            previousSelectedIndex: 0,
            in: visiblePages,
            loadedReferenceIdentifiers: [referenceURL]
        )

        #expect(visiblePages[selectedIndex].id == "reference-\(referenceURL)")
    }

    @Test func testAvailableLiveImageMovesAheadOfUnavailablePersistedImage() {
        let unavailablePath = "documents/unavailable.webp"
        let liveImageData = Data([0x01, 0x02, 0x03])
        let media = ActiveScanMedia(items: [
            .image(unavailablePath),
            .liveImage(liveImageData)
        ])
        let sourcePages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath],
            loadedReferenceIdentifiers: []
        )

        #expect(visiblePages.map(\.id) == [
            "liveImage-\(liveImageData.hashValue)",
            "image-\(unavailablePath)"
        ])
    }

    @Test func testReferenceDeduplicationIgnoresNaturebookURLDecorationsButKeepsStrictExternalIdentity() {
        let references = [
            "https://media.merian.app/public_uploads/pro/user/photo.webp?width=900",
            "https://example.com/species.jpg?size=small#first"
        ]

        let filtered = ReferenceImageDeduplicationPolicy.filteredReferenceURLs(
            references,
            excluding: [
                "HTTPS://MEDIA.MERIAN.APP/public_uploads/pro/user/photo.webp?width=1800#capture",
                "https://example.com/species.jpg?size=small#second"
            ]
        )

        #expect(filtered == ["https://example.com/species.jpg?size=small#first"])
    }

    @Test func testInsightMediaRemovesCurrentScanReferencesFromInlineAndFullscreenCarousels() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        let captureURL = "https://media.merian.app/public_uploads/pro/user/capture.webp"
        let communityURL = "https://media.merian.app/public_uploads/pro/other/reference.webp"
        let wikipediaURL = "https://upload.wikimedia.org/species.jpg"

        viewModel.inferenceEngine = engine
        engine.activeMedia = ActiveScanMedia(
            items: [.image("\(captureURL)?download=1")],
            referenceState: .loaded([
                "\(captureURL)?width=1200",
                communityURL,
                wikipediaURL
            ])
        )
        engine.speciesData = SpeciesData(
            scanId: "reference_deduplication",
            commonName: "Test species",
            scientificName: "Testus species",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.96,
            referenceImageUrl: [captureURL, communityURL, wikipediaURL].joined(separator: ","),
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "wild"
        )

        let visibleMedia = viewModel.activeMedia
        #expect(visibleMedia.referenceState == .loaded([communityURL, wikipediaURL]))
        #expect(viewModel.refUrls == [communityURL, wikipediaURL])
        #expect(viewModel.totalImages == 3)

        let pageIDs = CarouselPageBuilder.buildPages(
            for: visibleMedia,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        ).map(\.id)
        #expect(pageIDs == [
            "image-\(captureURL)?download=1",
            "reference-\(communityURL)",
            "reference-\(wikipediaURL)"
        ])

        let fullscreenIDs = InsightImageGalleryBuilder.buildItems(
            for: visibleMedia,
            referenceWikipediaUrl: nil
        ).map(\.id)
        #expect(fullscreenIDs == pageIDs)
    }

    @Test func testInsightMediaConvertsAnAllDuplicateReferenceSetToEmpty() {
        let captureURL = "https://media.merian.app/public_uploads/free/user/capture.webp"
        let media = ActiveScanMedia(
            items: [.image(captureURL)],
            referenceState: .loaded(["\(captureURL)?width=640"])
        ).removingDuplicateReferenceImages()

        #expect(media.referenceState == .empty)
        #expect(media.totalItems == 1)
    }

    @Test func testNativeCarouselResetsDataSourceWhenReferencesAppendAfterAudioPage() {
        let audioPath = "documents/audio_only.wav"
        let audioOnlyPages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(items: [.audio(audioPath)]),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let withReferencePages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(
                items: [.audio(audioPath)],
                referenceState: .loaded(["https://example.com/field-sparrow.jpg"])
            ),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        #expect(audioOnlyPages.map(\.id) == ["audio-\(audioPath)"])
        #expect(withReferencePages.map(\.id) == ["audio-\(audioPath)", "reference-https://example.com/field-sparrow.jpg"])
        #expect(NativePageCarousel.Coordinator.requiresDataSourceReset(previousPages: audioOnlyPages, nextPages: withReferencePages))
    }

    @Test func testInsightImageGalleryIncludesOnlyVisualLoadedPages() {
        let liveImageData = Data([1, 2, 3])
        let imagePath = "documents/original.webp"
        let media = ActiveScanMedia(
            items: [
                .audio("documents/audio.wav"),
                .liveImage(liveImageData),
                .description(ObservationContext(freeText: "A perched bird")),
                .image(imagePath)
            ],
            referenceState: .loaded([
                "https://media.merian.app/reference.webp",
                "https://upload.wikimedia.org/species.jpg",
                "https://static.inaturalist.org/photos/1/original.jpg"
            ])
        )

        let items = InsightImageGalleryBuilder.buildItems(
            for: media,
            referenceWikipediaUrl: "https://en.wikipedia.org/wiki/Test_species"
        )

        #expect(items.map(\.id) == [
            "liveImage-\(liveImageData.hashValue)",
            "image-\(imagePath)",
            "reference-https://media.merian.app/reference.webp",
            "reference-https://upload.wikimedia.org/species.jpg",
            "reference-https://static.inaturalist.org/photos/1/original.jpg"
        ])
        #expect(items.map(\.referenceAttributionLabel) == [nil, nil, "Naturebook", "Wikipedia", "GBIF"])
    }

    @Test func testInsightImageGalleryExcludesReferenceLoadingPlaceholder() {
        let media = ActiveScanMedia(
            items: [.audio("documents/audio.wav")],
            referenceState: .loading
        )

        let items = InsightImageGalleryBuilder.buildItems(
            for: media,
            referenceWikipediaUrl: nil
        )

        #expect(items.isEmpty)
    }

    @Test func testInsightImageGalleryPresentationMapsSelectedVisualPage() {
        let media = ActiveScanMedia(
            items: [
                .audio("documents/audio.wav"),
                .image("documents/first.webp"),
                .description(ObservationContext(freeText: "Wing bars")),
                .image("documents/second.webp")
            ],
            referenceState: .loaded(["https://example.com/reference.jpg"])
        )

        let presentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "image-documents/second.webp"
        )

        #expect(presentation?.items.map(\.id) == [
            "image-documents/first.webp",
            "image-documents/second.webp",
            "reference-https://example.com/reference.jpg"
        ])
        #expect(presentation?.initialSelectedIndex == 1)
    }

    @Test func testInsightImageGalleryMatchesVisibleCarouselOrder() {
        let unavailablePath = "documents/unavailable.webp"
        let availablePath = "documents/available.webp"
        let videoPath = "documents/observation.mp4"
        let referenceURL = "https://example.com/reference.webp"
        let media = ActiveScanMedia(
            items: [
                .image(unavailablePath),
                .video(videoPath),
                .image(availablePath)
            ],
            referenceState: .loaded([referenceURL])
        )
        let sourcePages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )
        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath],
            loadedReferenceIdentifiers: [referenceURL]
        )

        let presentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "reference-\(referenceURL)",
            orderedCarouselPageIDs: visiblePages.map(\.id)
        )
        let hiddenPresentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "image-\(unavailablePath)",
            orderedCarouselPageIDs: visiblePages.map(\.id)
        )

        #expect(presentation?.items.map(\.id) == [
            "image-\(availablePath)",
            "video-\(videoPath)",
            "reference-\(referenceURL)"
        ])
        #expect(presentation?.initialSelectedIndex == 2)
        #expect(hiddenPresentation == nil)
    }

    @Test func testInsightImageGalleryPresentationIncludesSelectedVideoPage() {
        let videoPath = "documents/observation.mp4"
        let media = ActiveScanMedia(
            items: [
                .image("documents/poster.webp"),
                .video(videoPath)
            ],
            referenceState: .loaded(["https://example.com/reference.jpg"])
        )

        let presentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "video-\(videoPath)",
            isVideoMuted: false
        )

        #expect(presentation?.items.map(\.id) == [
            "image-documents/poster.webp",
            "video-\(videoPath)",
            "reference-https://example.com/reference.jpg"
        ])
        #expect(presentation?.initialSelectedIndex == 1)
        #expect(presentation?.initialVideoMuted == false)
    }

    @Test func testInsightVideoCenterPlaybackZoneProtectsNavigationTap() {
        let containerSize = CGSize(width: 390, height: 440)
        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)

        #expect(InsightCarouselMediaInteractionPolicy.centerPlaybackHitSize == 96)
        #expect(InsightCarouselMediaInteractionPolicy.isCenterPlaybackTap(
            location: center,
            containerSize: containerSize,
            mediaKind: .video
        ))
        #expect(!InsightCarouselMediaInteractionPolicy.isCenterPlaybackTap(
            location: CGPoint(x: 24, y: 24),
            containerSize: containerSize,
            mediaKind: .video
        ))
        #expect(!InsightCarouselMediaInteractionPolicy.isCenterPlaybackTap(
            location: center,
            containerSize: containerSize,
            mediaKind: .visual
        ))
    }

    @Test func testInsightVideoPlaybackCoordinatorPausesBeforeFullscreenPresentation() {
        let coordinator = InsightCarouselVideoPlaybackCoordinator()
        var pauseCommandCount = 0
        let cancellable = coordinator.pauseForFullscreenPresentationPublisher.sink {
            pauseCommandCount += 1
        }

        coordinator.pauseForFullscreenPresentation()

        #expect(pauseCommandCount == 1)
        withExtendedLifetime(cancellable) {}
    }

    @Test func testInsightImageGalleryPresentationIgnoresNonVisualPages() {
        let media = ActiveScanMedia(
            items: [
                .audio("documents/audio.wav"),
                .description(ObservationContext(freeText: "Heard nearby"))
            ],
            referenceState: .loaded(["https://example.com/reference.jpg"])
        )

        let audioPresentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "audio-documents/audio.wav"
        )
        let descriptionPresentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "description-\(ObservationContext(freeText: "Heard nearby").serialized())"
        )
        let referencePresentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "reference-https://example.com/reference.jpg"
        )

        #expect(audioPresentation == nil)
        #expect(descriptionPresentation == nil)
        #expect(referencePresentation?.initialSelectedIndex == 0)
    }
}

private actor FieldTripContributionLoaderGate {
    private var continuation: CheckedContinuation<[FieldTripScanContribution], Never>?

    func load() async -> [FieldTripScanContribution] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func finish(with contributions: [FieldTripScanContribution]) {
        continuation?.resume(returning: contributions)
        continuation = nil
    }
}
