import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightShellLifecycleTests {
    @Test func testToggleScanInCollection() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
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
        #expect(viewModel.state.toastMessage?.title.contains("Added to Favorites") == true)

        viewModel.toggleScanInCollection(collection, modelContext: ctx)
        #expect(record.collections?.contains(where: { $0.id == collection.id }) == false)
        #expect(viewModel.state.toastMessage?.title.contains("Removed from Favorites") == true)
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
        var species = InsightSheetTestSupport.milestoneTestSpecies()
        species.isNewDiscovery = true
        species.isNewToMerianDictionary = false

        #expect(ScanMilestoneCoordinator.isValidNewToMerianMilestone(species) == false)
    }

    @Test func globalDictionaryContributionQualifiesForNewToMerianMilestone() {
        var species = InsightSheetTestSupport.milestoneTestSpecies()
        species.isNewDiscovery = false
        species.isNewToMerianDictionary = true

        #expect(ScanMilestoneCoordinator.isValidNewToMerianMilestone(species))
    }

    @Test func invalidDictionaryContributionDoesNotShowNewToMerianMilestone() {
        var species = InsightSheetTestSupport.milestoneTestSpecies(commonName: "Unknown Subject", isBiological: true)
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
            presentationRole: .inferenceError,
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
            presentationRole: .inferenceError,
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

    @Test func testInferenceErrorPresentationRoleDoesNotDependOnDisplayCopy() {
        let errorPresentation = SpeciesData(
            presentationRole: .inferenceError,
            commonName: "Service paused",
            scientificName: "Scan saved",
            insightData: InsightData(
                aiReasoning: "Naturebook will resume this scan automatically.",
                hazardType: "none"
            ),
            confidenceScore: 0,
            isBiological: false
        )
        let similarlyNamedResult = SpeciesData(
            scanId: "network-timeout-species",
            commonName: "Network timeout",
            scientificName: "Example species",
            insightData: InsightData(
                aiReasoning: "A completed classification with unusual source copy.",
                hazardType: "none"
            ),
            confidenceScore: 0.9,
            isBiological: false
        )

        #expect(errorPresentation.isInferenceErrorPlaceholder)
        #expect(!errorPresentation.isClassifiedNonBiological)
        #expect(!similarlyNamedResult.isInferenceErrorPlaceholder)
        #expect(similarlyNamedResult.isClassifiedNonBiological)
    }

    @Test func testNetworkTimeoutPlaceholderDoesNotShowNonBiologicalSuccessToast() throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: nil,
            presentationRole: .inferenceError,
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

    @Test func lateFirstAnalysisRecordBindingRestartsResultToolbarReveal() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let scanId = "late-first-analysis-toolbar"
        let engine = InferenceEngine()
        engine.activeScanId = scanId
        engine.isProcessing = true
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)
        let analyzingKey = viewModel.resultToolbarRevealKey

        engine.speciesData = SpeciesData(
            scanId: scanId,
            commonName: "Cooper's Hawk",
            scientificName: "Accipiter cooperii",
            insightData: InsightData(
                aiReasoning: "An adult accipiter with a blocky head.",
                hazardType: "none"
            ),
            confidenceScore: 0.97,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        engine.isProcessing = false

        #expect(viewModel.presentedLocalRecordScanId == nil)
        #expect(viewModel.resultToolbarRevealKey == analyzingKey)

        let record = LocalScanRecord(
            id: scanId,
            speciesId: "late-first-analysis-species",
            scientificName: "Accipiter cooperii",
            commonName: "Cooper's Hawk"
        )
        context.insert(record)
        try context.save()

        #expect(viewModel.fetchLocalRecord(for: scanId, modelContext: context))
        let completedKey = viewModel.resultToolbarRevealKey
        #expect(completedKey != analyzingKey)
        #expect(completedKey.scanId == scanId)
        #expect(
            completedKey.presentationGeneration ==
                analyzingKey.presentationGeneration
        )
        #expect(viewModel.revealBottomBarTools(
            expectedScanId: scanId,
            expectedGeneration: completedKey.presentationGeneration
        ))
        #expect(viewModel.state.showBottomBarTools)
    }

    @Test func successfulProcessingCompletionUsesSingleResultHapticSource() throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let engine = InferenceEngine()
        var completionFeedbackCount = 0
        let viewModel = InsightSheetViewModel(
            inferenceEngine: engine,
            dependencies: InsightShellDependencies(
                completionFeedback: {
                    completionFeedbackCount += 1
                }
            )
        )
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

        #expect(completionFeedbackCount == 1)
    }

    @Test func delayedExploreOnboardingTaskIsIdentityBoundAndCancelledByReset() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "onboarding_task_species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        context.insert(record)
        try context.save()

        let settings = AppSettings.preview
        settings.hasSeenExploreOnboarding = false
        let engine = InsightSheetTestSupport.biologicalEngine(scanId: record.id)
        let viewModel = InsightSheetViewModel(
            inferenceEngine: engine,
            appSettings: settings
        )
        #expect(viewModel.fetchLocalRecord(for: record.id, modelContext: context))

        viewModel.evaluateProcessingCompletion(
            isStillProcessing: false,
            inferenceEngine: engine,
            modelContext: context
        )
        let scheduledTaskID = try #require(viewModel.exploreOnboardingPresentationTaskID)
        #expect(viewModel.exploreOnboardingPresentationTask != nil)

        viewModel.evaluateProcessingCompletion(
            isStillProcessing: false,
            inferenceEngine: engine,
            modelContext: context
        )
        #expect(viewModel.exploreOnboardingPresentationTaskID == scheduledTaskID)

        viewModel.reset()
        #expect(viewModel.exploreOnboardingPresentationTask == nil)
        #expect(viewModel.exploreOnboardingPresentationTaskID == nil)
        #expect(viewModel.exploreOnboardingPresentationScanID == nil)
        #expect(viewModel.exploreOnboardingPresentationGeneration == nil)
    }

    @Test func inferenceErrorCompletionDoesNotEmitResultHaptic() throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let engine = InferenceEngine()
        var completionFeedbackCount = 0
        let viewModel = InsightSheetViewModel(
            inferenceEngine: engine,
            dependencies: InsightShellDependencies(
                completionFeedback: {
                    completionFeedbackCount += 1
                }
            )
        )
        engine.speciesData = SpeciesData(
            scanId: nil,
            presentationRole: .inferenceError,
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

        #expect(completionFeedbackCount == 0)
    }

}
