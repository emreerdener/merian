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

    @Test func testEvaluateScrollOffset() {
        let viewModel = InsightSheetViewModel()
        #expect(viewModel.state.isCommonNameScrolledPast == false)
        
        viewModel.evaluateScrollOffset(minY: 40.0)
        #expect(viewModel.state.isCommonNameScrolledPast == true)
        
        viewModel.evaluateScrollOffset(minY: 60.0)
        #expect(viewModel.state.isCommonNameScrolledPast == false)
    }

    @Test func testToggleScanInCollection() async throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        
        let record = LocalScanRecord(speciesId: "scan_toggle", scientificName: "Test", commonName: "Test")
        ctx.insert(record)
        
        let collection = ScanCollection(name: "Favorites")
        ctx.insert(collection)
        try ctx.save()
        
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
    }

    @Test func localNewDiscoveryDoesNotShowNewToMerianMilestone() {
        MilestoneToastPresenter.shared.resetForTesting()
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        var species = milestoneTestSpecies()
        species.isNewDiscovery = true
        species.isNewToMerianDictionary = false
        engine.speciesData = species

        viewModel.evaluateVoiceOverAndCelebration(inferenceEngine: engine)

        #expect(MilestoneToastPresenter.shared.activeItem == nil)
        #expect(viewModel.state.hasPresentedNewToMerianMilestone == false)
    }

    @Test func globalDictionaryContributionShowsNewToMerianMilestone() {
        MilestoneToastPresenter.shared.resetForTesting()
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        var species = milestoneTestSpecies()
        species.isNewDiscovery = false
        species.isNewToMerianDictionary = true
        engine.speciesData = species

        viewModel.evaluateVoiceOverAndCelebration(inferenceEngine: engine)

        guard case .dictionary(let milestone) = MilestoneToastPresenter.shared.activeItem?.payload else {
            Issue.record("Expected New to Merian milestone")
            return
        }

        #expect(milestone == .newToMerian)
        #expect(viewModel.state.hasPresentedNewToMerianMilestone == true)
    }

    @Test func invalidDictionaryContributionDoesNotShowNewToMerianMilestone() {
        MilestoneToastPresenter.shared.resetForTesting()
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        var species = milestoneTestSpecies(commonName: "Unknown Subject", isBiological: true)
        species.isNewToMerianDictionary = true
        engine.speciesData = species

        viewModel.evaluateVoiceOverAndCelebration(inferenceEngine: engine)

        #expect(MilestoneToastPresenter.shared.activeItem == nil)
        #expect(viewModel.state.hasPresentedNewToMerianMilestone == false)
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
                aiReasoning: "Merian saved this scan and will retry automatically.",
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

    @Test func testNetworkTimeoutPlaceholderDoesNotShowNonBiologicalSuccessToast() throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: nil,
            commonName: "Network timeout",
            scientificName: "Offline mode",
            insightData: InsightData(
                aiReasoning: "Merian saved this scan and will retry automatically.",
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
        viewModel.activeLocalRecordId = "strong_hidden_candidates"

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
        viewModel.activeLocalRecordId = "strong_hidden_candidates"

        #expect(viewModel.canReviewAlternatives == false)
        #expect(viewModel.canReviewIdentificationConcernCandidates == true)
        #expect(viewModel.candidateSwipeCandidates.isEmpty)

        viewModel.presentCandidateSwipe(source: .identificationConcern)

        #expect(viewModel.candidateSwipeCandidates.map(\.scientificName) == ["Pieris rapae"])
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
        viewModel.activeLocalRecordId = "strong_competitive_candidates"

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
        viewModel.inferenceEngine = InferenceEngine()
        
        // Assert initial unassigned state
        #expect(viewModel.activeLocalRecord == nil)
        
        let record = LocalScanRecord(speciesId: "fetch_test_1", scientificName: "Equus caballus", commonName: "Horse")
        // Overriding default initializer value manually to test the read receipt flip logic isolated.
        record.hasBeenViewed = false
        
        let recordId = record.id
        ctx.insert(record)
        try ctx.save()
        
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
        viewModel.activeLocalRecordId = record.id
        viewModel.toolbarRecordSnapshot = InsightToolbarRecordSnapshot(record: record)

        let engine = InferenceEngine()
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

        #expect(pages.map(\.referenceAttributionLabel) == ["Merian", "Wikipedia", "GBIF"])
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
        #expect(items.map(\.referenceAttributionLabel) == [nil, nil, "Merian", "Wikipedia", "GBIF"])
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
            selectedCarouselPageID: "video-\(videoPath)"
        )

        #expect(presentation?.items.map(\.id) == [
            "image-documents/poster.webp",
            "video-\(videoPath)",
            "reference-https://example.com/reference.jpg"
        ])
        #expect(presentation?.initialSelectedIndex == 1)
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
