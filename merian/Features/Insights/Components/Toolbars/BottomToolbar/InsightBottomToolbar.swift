import SwiftUI

struct InsightBottomToolbar: ToolbarContent {
    @Environment(InferenceEngine.self) var inferenceEngine
    
    let showBottomBarTools: Bool
    let collections: [ScanCollection]
    let activeLocalRecord: LocalScanRecord?
    let toggleScanInCollection: (ScanCollection) -> Void
    @Binding var showNewCollectionAlert: Bool
    let shareExternally: () -> Void
    let onShareToExplore: ((Bool) -> Void)?
    let isSharingToExplore: Bool
    var fieldNotesPreview: String?
    var sharedExplorePostId: String?
    var onViewInExplore: (() -> Void)?
    
    var body: some ToolbarContent {
        if showBottomBarTools, let speciesData = inferenceEngine.speciesData, speciesData.isBiological && speciesData.commonName.lowercased() != "not applicable" {
            ToolbarItemGroup(placement: .bottomBar) {
                ShareButton(
                    shareExternally: shareExternally,
                    onShareToExplore: onShareToExplore,
                    isSharingToExplore: isSharingToExplore,
                    fieldNotesPreview: fieldNotesPreview,
                    sharedExplorePostId: sharedExplorePostId,
                    onViewInExplore: onViewInExplore
                )

                Spacer()

                 AddCollectionButton(
                    collections: collections,
                    activeLocalRecord: activeLocalRecord,
                    toggleScanInCollection: toggleScanInCollection,
                    showNewCollectionAlert: $showNewCollectionAlert,
                    hasScanId: speciesData.scanId != nil
                )
            }
        }
    }
}
