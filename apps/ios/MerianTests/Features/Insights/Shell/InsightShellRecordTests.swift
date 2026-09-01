import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightShellRecordTests {
    @Test func testFetchLocalRecord() async throws {
        // Validation that the viewmodel gracefully pulls state and assigns local memory
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()

        // Assert initial unassigned state
        #expect(viewModel.activeLocalRecord == nil)

        let record = LocalScanRecord(speciesId: "fetch_test_1", scientificName: "Equus caballus", commonName: "Horse")
        // Overriding default initializer value manually to test the read receipt flip logic isolated.
        record.hasBeenViewed = false

        let recordId = record.id
        ctx.insert(record)
        try ctx.save()
        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: recordId)

        viewModel.fetchLocalRecord(for: recordId, modelContext: ctx)

        #expect(viewModel.activeLocalRecord?.id == recordId)
        #expect(viewModel.activeLocalRecord?.hasBeenViewed == true, "fetchLocalRecord must actively flag the read-receipt to false the unread states across the app ecosystem")
    }

    @Test func testFetchLocalRecordHydratesSharedExplorePostIdFromCache() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
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
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let staleScan = LocalScanRecord(
            speciesId: "stale_identity_species",
            scientificName: "Quercus alba",
            commonName: "White Oak",
            fieldNotes: "Old observation"
        )
        ctx.insert(staleScan)
        try ctx.save()

        let viewModel = InsightSheetViewModel()
        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: staleScan.id)
        #expect(viewModel.fetchLocalRecord(for: staleScan.id, modelContext: ctx))
        viewModel.state.sharedExplorePostId = UUID().uuidString.lowercased()
        viewModel.state.sharedCommunityIdentificationRequestId = UUID().uuidString.lowercased()
        viewModel.state.sharedCommunityIdentificationStatus = .needsId
        viewModel.state.isExploreFeedVisible = true
        viewModel.state.sharedExploreHashtags = ["stale"]
        viewModel.state.fieldNotesText = "Old observation"
        viewModel.state.toastMessage = .information(
            "Shared to Explore",
            action: .viewExplorePost
        )
        viewModel.toastAction = {}

        let newScanId = UUID().uuidString.lowercased()
        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: newScanId)

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
        #expect(viewModel.state.toastMessage?.action == nil)
        #expect(viewModel.toastAction == nil)
        #expect(viewModel.presentedSpeciesScanId == newScanId)
    }

    @Test func testRecordSwitchInvalidatesPriorActionGeneration() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
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
        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: firstScan.id)
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

        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: secondScan.id)
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

    @Test func completedDeletionIsIdentityBoundAndPresentationNeutral() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "deletion_ownership_species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        context.insert(record)
        try context.save()

        var eradicatedScanIDs: [String] = []
        let dependencies = InsightShellDependencies(
            eradicateScan: { record, _ in
                eradicatedScanIDs.append(record.id)
            }
        )
        let engine = InsightSheetTestSupport.biologicalEngine(
            scanId: record.id
        )
        let viewModel = InsightSheetViewModel(
            inferenceEngine: engine,
            dependencies: dependencies
        )
        #expect(viewModel.fetchLocalRecord(
            for: record.id,
            modelContext: context
        ))
        let generation = viewModel.scanBoundActionGeneration

        #expect(!viewModel.eradicateCurrentScan(
            expectedScanId: record.id,
            expectedGeneration: generation &+ 1,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(eradicatedScanIDs.isEmpty)
        #expect(viewModel.activeLocalRecordId == record.id)

        #expect(viewModel.eradicateCurrentScan(
            expectedScanId: record.id,
            expectedGeneration: generation,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(eradicatedScanIDs == [record.id])
        #expect(viewModel.activeLocalRecord == nil)
        #expect(viewModel.activeLocalRecordId == nil)
    }

}
