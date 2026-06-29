import SwiftUI

struct InsightBottomToolbar: ToolbarContent {
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(ProfileViewModel.self) private var profileViewModel
    
    let showBottomBarTools: Bool
    let recordSnapshot: InsightToolbarRecordSnapshot?
    let canShowInsightChat: Bool
    let onInsightChat: () -> Void
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
                let isHuman = speciesData.isHumanSubject || (recordSnapshot?.isHumanSubject ?? false)

                if !isHuman {
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
                }

                Spacer()

                if canShowInsightChat {
                    InsightChatToolbarButton(action: onInsightChat)
                }
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

private struct InsightChatToolbarButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let action: () -> Void

    var body: some View {
        ZStack {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Field chat")
                }
                .padding(.horizontal, 8)
                .background {
                    FieldChatGlowAccent(reduceMotion: reduceMotion)
                }
            }
            .accessibilityLabel("Open Field chat")
        }
    }
}

private struct FieldChatGlowAccent: View {
    let reduceMotion: Bool

    @State private var isPulsing = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(
                AngularGradient(
                    colors: [
                        Color(red: 0.20, green: 0.55, blue: 1.00),
                        Color(red: 0.30, green: 0.95, blue: 0.65),
                        Color(red: 1.00, green: 0.88, blue: 0.30),
                        Color(red: 1.00, green: 0.38, blue: 0.58),
                        Color(red: 0.62, green: 0.40, blue: 1.00),
                        Color(red: 0.20, green: 0.55, blue: 1.00)
                    ],
                    center: .center
                )
            )
            .padding(.horizontal, -12)
            .padding(.vertical, -8)
            .blur(radius: 10)
            .opacity(reduceMotion ? 0.20 : (isPulsing ? 0.34 : 0.18))
            .scaleEffect(reduceMotion ? 1.0 : (isPulsing ? 1.08 : 0.98))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
