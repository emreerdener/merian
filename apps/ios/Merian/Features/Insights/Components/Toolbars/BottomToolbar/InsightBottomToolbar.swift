import SwiftUI

struct InsightBottomToolbar: ToolbarContent {
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(ProfileViewModel.self) private var profileViewModel
    
    let showBottomBarTools: Bool
    let collections: [ScanCollection]
    let recordSnapshot: InsightToolbarRecordSnapshot?
    let toggleScanInCollection: (ScanCollection) -> Void
    @Binding var showNewCollectionAlert: Bool
    let shareExternally: () -> Void
    let onShareToExplore: ((ExplorePostComposerDraft) -> Void)?
    let onEditExplorePost: ((ExplorePostComposerDraft) -> Void)?
    let onAskCommunity: (() -> Void)?
    let onEditCommunityRequest: (() -> Void)?
    let isSharingToExplore: Bool
    let isUpdatingExplorePostContent: Bool
    let isUpdatingExploreFieldNotes: Bool
    var displaySpeciesName: String
    var commonNameOptions: [String]
    var fieldNotesPreview: String?
    var sharedExploreHashtags: [String]
    var sharedExplorePostId: String?
    var shareRecommendation: InsightShareRecommendation
    var sharedExploreLocationSharing: ExplorePostLocationSharing?
    var fieldNotesArePublicOnExplore: Bool
    var onViewInExplore: (() -> Void)?
    var onViewCommunityRequest: (() -> Void)?
    var onUpdateFieldNotesVisibility: ((Bool) async -> FieldNotesVisibilityUpdateFeedback)?
    
    var body: some ToolbarContent {
        if showBottomBarTools, let speciesData = inferenceEngine.speciesData, speciesData.isBiological && speciesData.commonName.lowercased() != "not applicable" {
            ToolbarItemGroup(placement: .bottomBar) {
                let publicLocationLabel = visiblePublicLocationLabel(from: speciesData.locationName)

                InsightShareButton(
                    shareExternally: shareExternally,
                    onShareToExplore: onShareToExplore,
                    onEditExplorePost: onEditExplorePost,
                    onAskCommunity: onAskCommunity,
                    onEditCommunityRequest: onEditCommunityRequest,
                    isSharingToExplore: isSharingToExplore,
                    isUpdatingExplorePostContent: isUpdatingExplorePostContent,
                    isUpdatingExploreFieldNotes: isUpdatingExploreFieldNotes,
                    speciesName: displaySpeciesName,
                    scientificName: speciesData.scientificName,
                    commonNameOptions: commonNameOptions,
                    initialSelectedCommonName: displaySpeciesName,
                    heroImageUrl: recordSnapshot?.coverImagePath ?? inferenceEngine.activeMedia.imagePathsForUpload.first,
                    publicLocationLabel: publicLocationLabel,
                    fieldNotesPreview: fieldNotesPreview,
                    hashtagSuggestionContext: ExploreHashtagSuggestionContext(
                        speciesName: displaySpeciesName,
                        scientificName: speciesData.scientificName,
                        publicLocationLabel: publicLocationLabel,
                        fieldNotes: fieldNotesPreview,
                        ecologyType: speciesData.ecologyType,
                        taxonomyKingdom: speciesData.taxonomy?.kingdom ?? recordSnapshot?.taxonomyKingdom,
                        taxonomyClass: speciesData.taxonomy?.className ?? recordSnapshot?.taxonomyClass,
                        taxonomyOrder: speciesData.taxonomy?.order ?? recordSnapshot?.taxonomyOrder,
                        taxonomyFamily: speciesData.taxonomy?.family ?? recordSnapshot?.taxonomyFamily,
                        habitatDescription: speciesData.habitatDescription ?? recordSnapshot?.habitatDescription,
                        weatherCondition: speciesData.weatherCondition ?? recordSnapshot?.weatherCondition,
                        colors: speciesData.colors ?? [],
                        groupTags: speciesData.groupTags ?? [],
                        semanticTags: recordSnapshot?.semanticTags ?? [],
                        isInvasive: speciesData.isInvasive,
                        imageQualityScore: speciesData.imageQualityScore ?? recordSnapshot?.imageQualityScore,
                        lifeStage: speciesData.lifeStage,
                        reproductiveCondition: speciesData.reproductiveCondition,
                        ecologicalInteractions: speciesData.ecologicalInteractions ?? []
                    ),
                    sharedExploreHashtags: sharedExploreHashtags,
                    sharedExplorePostId: sharedExplorePostId,
                    shareRecommendation: shareRecommendation,
                    initialLocationSharing: sharedExploreLocationSharing ?? defaultLocationSharing,
                    fieldNotesArePublicOnExplore: fieldNotesArePublicOnExplore,
                    onViewInExplore: onViewInExplore,
                    onViewCommunityRequest: onViewCommunityRequest,
                    onUpdateFieldNotesVisibility: onUpdateFieldNotesVisibility
                )

                Spacer()

                 AddCollectionButton(
                    collections: collections,
                    selectedCollectionIds: recordSnapshot?.collectionIds ?? [],
                    toggleScanInCollection: toggleScanInCollection,
                    showNewCollectionAlert: $showNewCollectionAlert,
                    hasScanId: recordSnapshot != nil || speciesData.scanId != nil
                )
            }
        }
    }

    private func visiblePublicLocationLabel(from locationName: String?) -> String? {
        return ExploreLocationPrivacy.displayLabel(from: locationName)
    }

    private var defaultLocationSharing: ExplorePostLocationSharing {
        switch profileViewModel.defaultGeoprivacy {
        case "open":
            return .open
        case "private":
            return .privateLocation
        default:
            return .obscured
        }
    }
}
