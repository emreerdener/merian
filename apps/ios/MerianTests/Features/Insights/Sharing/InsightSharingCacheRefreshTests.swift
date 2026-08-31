import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightSharingCacheRefreshTests {
    @Test func missingExploreCacheClearsSharedPostState() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "shared_refresh_test",
            scientificName: "Quercus",
            commonName: "Oak"
        )

        context.insert(record)
        try context.save()

        viewModel.fetchLocalRecord(for: record.id, modelContext: context)
        viewModel.state.sharedExplorePostId = "stale_post_id"

        ExploreShareStateStore.setSharedPostId(nil, for: record.id)
        viewModel.refreshSharedExploreStateFromLocalCache()

        #expect(viewModel.state.sharedExplorePostId == nil)
    }

    @Test func cacheRefreshPreservesRestoredCommunityRequestState() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "community_refresh_test",
            scientificName: "Rosa",
            commonName: "Rose"
        )

        context.insert(record)
        try context.save()

        viewModel.fetchLocalRecord(for: record.id, modelContext: context)
        viewModel.state.sharedCommunityIdentificationRequestId =
            "request_refresh_test"
        viewModel.state.sharedCommunityIdentificationStatus = .needsId

        ExploreShareStateStore.setSharedPostId(nil, for: record.id)
        viewModel.refreshSharedExploreStateFromLocalCache()

        #expect(
            viewModel.state.sharedCommunityIdentificationRequestId == "request_refresh_test"
        )
        #expect(viewModel.state.sharedCommunityIdentificationStatus == .needsId)
        #expect(viewModel.state.sharedExplorePostId == nil)
    }
}
