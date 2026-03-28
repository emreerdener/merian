import SwiftUI

struct InsightBottomToolbar: ToolbarContent {
    @Environment(InferenceEngine.self) var inferenceEngine
    
    let showBottomBarTools: Bool
    let collections: [ScanCollection]
    let activeLocalRecord: LocalScanRecord?
    let toggleScanInCollection: (ScanCollection) -> Void
    @Binding var showNewCollectionAlert: Bool
    let shareDiscovery: () -> Void
    
    var body: some ToolbarContent {
        if showBottomBarTools, let speciesData = inferenceEngine.speciesData, speciesData.isBiological && speciesData.commonName.lowercased() != "not applicable" {
            ToolbarItemGroup(placement: .bottomBar) {
                ShareButton(shareDiscovery: shareDiscovery)

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
