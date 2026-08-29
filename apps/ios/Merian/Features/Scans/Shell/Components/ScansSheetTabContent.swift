import SwiftData
import SwiftUI

struct ScansLibraryTabContent: View {
    @Bindable var searchManager: ScansManager
    let filterCategories: [String]
    let queuedScans: [QueuedScanSnapshot]
    let unavailableMediaScanCount: Int
    let isUnavailableMediaOverviewVisible: Bool
    let isExploreMediaIncidentRefreshRunning: Bool
    let onRefreshExploreMediaIncidents: () -> Void
    let onDismissUnavailableMediaOverview: () -> Void
    @Binding var isSearchFocused: Bool
    let onScanSelected: (LocalScanRecord) -> Void
    let onQueuedScanSelected: (QueuedScanContext) -> Void
    @Binding var showSelectionLimitAlert: Bool
    @Binding var scanToDelete: String?
    @Binding var showDeleteConfirmation: Bool

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        LibraryView(
            searchManager: searchManager,
            filterCategories: filterCategories,
            isSearchFocused: isSearchFocused,
            queuedScans: queuedScans,
            unavailableMediaScanCount: unavailableMediaScanCount,
            isUnavailableMediaOverviewVisible:
                isUnavailableMediaOverviewVisible,
            isExploreMediaIncidentRefreshRunning:
                isExploreMediaIncidentRefreshRunning,
            onRefreshExploreMediaIncidents:
                onRefreshExploreMediaIncidents,
            onDismissUnavailableMediaOverview:
                onDismissUnavailableMediaOverview,
            isSelectionMode: searchManager.isSelectionMode,
            isSelected: { scan in
                searchManager.selectedScans.contains(scan.id)
            },
            onSelect: handleSelection,
            onDelete: { scan in
                guard !searchManager.isDownloading else { return }
                scanToDelete = scan.id
                showDeleteConfirmation = true
            },
            onShareToExplore: { scan in
                guard !searchManager.isDownloading else { return }
                Task {
                    await searchManager.shareToExplore(
                        scanId: scan.id,
                        modelContext: modelContext
                    )
                }
            },
            onQueuedInsight: { queuedContext in
                MerianLog.data.debug(
                    "ScansSheetView: pushing queued insight scanId=\(queuedContext.id, privacy: .private) state=\(queuedContext.queueState.rawValue, privacy: .public)"
                )
                onQueuedScanSelected(queuedContext)
            }
        )
    }

    private func handleSelection(_ scan: LocalScanRecord) {
        if searchManager.isSelectionMode {
            guard !searchManager.isDownloading else { return }
            let didToggle = searchManager.toggleSelection(for: scan.id)
            if !didToggle {
                searchManager.triggerErrorFeedback()
                showSelectionLimitAlert = true
            }
        } else {
            isSearchFocused = false
            onScanSelected(scan)
        }
    }
}

struct ScansCollectionsTabContent: View {
    let searchManager: ScansManager
    let isSearchFocused: Bool
    let scans: [LocalScanRecord]
    let collections: [ScanCollection]
    let hiddenSmartCollectionIDs: Set<String>
    let onHideSmartCollection: (SmartCollectionSnapshot) -> Void
    @Binding var newlyCreatedCollection: ScanCollection?

    var body: some View {
        CollectionsView(
            searchQuery: searchManager.searchQuery,
            isSearchFocused: isSearchFocused,
            collections: collections,
            hiddenSmartCollectionIDs: hiddenSmartCollectionIDs,
            onHideSmartCollection: onHideSmartCollection,
            newlyCreatedCollection: $newlyCreatedCollection,
            scans: scans
        )
    }
}
