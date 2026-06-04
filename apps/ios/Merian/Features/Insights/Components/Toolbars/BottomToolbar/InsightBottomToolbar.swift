import SwiftUI

struct InsightToolbarRecordSnapshot: Equatable {
    let scanId: String
    let coverImagePath: String?
    let taxonomyKingdom: String?
    let taxonomyClass: String?
    let taxonomyOrder: String?
    let taxonomyFamily: String?
    let habitatDescription: String?
    let weatherCondition: String?
    let semanticTags: [String]
    let imageQualityScore: Int?
    let collectionIds: Set<String>
    let captureDate: Date?
    let timestamp: Date
    let confirmedSpeciesId: String?
    let imageCount: Int

    init(record: LocalScanRecord) {
        self.scanId = record.id
        self.coverImagePath = record.coverImagePath
        self.taxonomyKingdom = record.taxonomyKingdom
        self.taxonomyClass = record.taxonomyClass
        self.taxonomyOrder = record.taxonomyOrder
        self.taxonomyFamily = record.taxonomyFamily
        self.habitatDescription = record.habitatDescription
        self.weatherCondition = record.weatherCondition
        self.semanticTags = record.semanticTags
        self.imageQualityScore = record.imageQualityScore
        self.collectionIds = Set(record.collections?.map(\.id) ?? [])
        self.captureDate = record.captureDate
        self.timestamp = record.timestamp
        self.confirmedSpeciesId = record.confirmedSpeciesId
        self.imageCount = record.capturedMediaSnapshot.imagePaths.count
    }
}

struct InsightBottomToolbar: ToolbarContent {
    @Environment(InferenceEngine.self) var inferenceEngine
    
    let showBottomBarTools: Bool
    let collections: [ScanCollection]
    let recordSnapshot: InsightToolbarRecordSnapshot?
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
                let publicLocationLabel = ExploreLocationPrivacy.displayLabel(from: speciesData.locationName)

                ShareButton(
                    shareExternally: shareExternally,
                    onShareToExplore: onShareToExplore,
                    onEditExplorePost: onEditExplorePost,
                    isSharingToExplore: isSharingToExplore,
                    isUpdatingExplorePostContent: isUpdatingExplorePostContent,
                    isUpdatingExploreFieldNotes: isUpdatingExploreFieldNotes,
                    speciesName: speciesData.commonName,
                    scientificName: speciesData.scientificName,
                    heroImageUrl: recordSnapshot?.coverImagePath ?? inferenceEngine.activeMedia.imagePathsForUpload.first,
                    publicLocationLabel: publicLocationLabel,
                    fieldNotesPreview: fieldNotesPreview,
                    hashtagSuggestionContext: ExploreHashtagSuggestionContext(
                        speciesName: speciesData.commonName,
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
                    fieldNotesArePublicOnExplore: fieldNotesArePublicOnExplore,
                    onViewInExplore: onViewInExplore,
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
}
