import SwiftUI

struct InsightBottomToolbar: ToolbarContent {
    @Environment(InferenceEngine.self) var inferenceEngine
    
    let showBottomBarTools: Bool
    let collections: [ScanCollection]
    let activeLocalRecord: LocalScanRecord?
    let toggleScanInCollection: (ScanCollection) -> Void
    @Binding var showNewCollectionAlert: Bool
    let shareExternally: () -> Void
    let onShareToExplore: ((ExplorePostComposerDraft) -> Void)?
    let onEditExplorePost: ((ExplorePostComposerDraft) -> Void)?
    let isSharingToExplore: Bool
    let isUpdatingExplorePostContent: Bool
    let isUpdatingExploreFieldNotes: Bool
    var fieldNotesPreview: String?
    var sharedExploreHashtags: [String]
    var sharedExplorePostId: String?
    var fieldNotesArePublicOnExplore: Bool
    var onViewInExplore: (() -> Void)?
    var onUpdateFieldNotesVisibility: ((Bool) async -> FieldNotesVisibilityUpdateFeedback)?
    
    var body: some ToolbarContent {
        if showBottomBarTools, let speciesData = inferenceEngine.speciesData, speciesData.isBiological && speciesData.commonName.lowercased() != "not applicable" {
            ToolbarItemGroup(placement: .bottomBar) {
                ShareButton(
                    shareExternally: shareExternally,
                    onShareToExplore: onShareToExplore,
                    onEditExplorePost: onEditExplorePost,
                    isSharingToExplore: isSharingToExplore,
                    isUpdatingExplorePostContent: isUpdatingExplorePostContent,
                    isUpdatingExploreFieldNotes: isUpdatingExploreFieldNotes,
                    speciesName: speciesData.commonName,
                    scientificName: speciesData.scientificName,
                    heroImageUrl: activeLocalRecord?.coverImagePath ?? inferenceEngine.activeMedia.imagePathsForUpload.first,
                    publicLocationLabel: ExploreLocationPrivacy.displayLabel(from: speciesData.locationName),
                    fieldNotesPreview: fieldNotesPreview,
                    sharedExploreHashtags: sharedExploreHashtags,
                    sharedExplorePostId: sharedExplorePostId,
                    fieldNotesArePublicOnExplore: fieldNotesArePublicOnExplore,
                    onViewInExplore: onViewInExplore,
                    onUpdateFieldNotesVisibility: onUpdateFieldNotesVisibility
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
