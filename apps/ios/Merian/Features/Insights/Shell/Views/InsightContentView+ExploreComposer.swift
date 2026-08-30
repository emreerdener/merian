import SwiftUI

extension InsightContentView {
    @ViewBuilder
    var explorePostComposerSheet: some View {
        if let scanId = viewModel.state.explorePostComposerPresentationScanId,
           let composerGeneration =
            viewModel.state.explorePostComposerPresentationGeneration,
           let postId =
            viewModel.state.explorePostComposerPresentationPostId,
           viewModel.isPresentingLocalRecord(
               scanId: scanId,
               generation: composerGeneration
           ),
           viewModel.state.sharedExplorePostId?
            .caseInsensitiveCompare(postId) == .orderedSame,
           let speciesData = inferenceEngine.speciesData,
           speciesData.scanId?.caseInsensitiveCompare(scanId) == .orderedSame {
            ExplorePostComposerView(
                mode: .edit,
                speciesName: viewModel.resolvedHeaderTitle,
                scientificName: speciesData.scientificName,
                heroImageUrl: viewModel.toolbarRecordSnapshot?.coverImagePath ??
                    inferenceEngine.activeMedia.imagePathsForUpload.first,
                publicLocationLabel: visiblePublicLocationLabel(from: speciesData.locationName),
                commonNameOptions: viewModel.allNamesForPicker,
                initialSelectedCommonName: viewModel.resolvedHeaderTitle,
                initialFieldNotes: viewModel.shareableFieldNotes,
                initialFieldNotesArePublic: viewModel.state.exploreFieldNotesArePublic,
                initialHashtags: viewModel.state.sharedExploreHashtags,
                initialLocationSharing: viewModel.state.sharedExploreLocationSharing ?? defaultLocationSharing,
                mediaItems: viewModel.toolbarRecordSnapshot?.exploreMediaItems ?? [],
                hashtagSuggestionContext: exploreHashtagSuggestionContext(for: speciesData),
                isSaving: viewModel.state.isUpdatingExplorePostContent,
                onSubmit: { draft in
                    guard viewModel.isPresentingLocalRecord(
                        scanId: scanId,
                        generation: composerGeneration
                    ),
                          viewModel.state
                            .explorePostComposerPresentationScanId?
                            .caseInsensitiveCompare(scanId) == .orderedSame,
                          viewModel.state
                            .explorePostComposerPresentationGeneration ==
                            composerGeneration,
                          viewModel.state
                            .explorePostComposerPresentationPostId?
                            .caseInsensitiveCompare(postId) == .orderedSame,
                          viewModel.state.sharedExplorePostId?
                            .caseInsensitiveCompare(postId) == .orderedSame else {
                        return
                    }
                    Task {
                        await viewModel.updateExplorePostContent(
                            draft,
                            expectedScanId: scanId,
                            expectedGeneration: composerGeneration,
                            modelContext: modelContext
                        )
                    }
                    viewModel.state.isExplorePostComposerPresented = false
                    viewModel.state.explorePostComposerPresentationScanId = nil
                    viewModel.state.explorePostComposerPresentationGeneration = nil
                    viewModel.state.explorePostComposerPresentationPostId = nil
                }
            )
        }
    }

    func isCommunityRequestPresentationCurrent(
        scanId: String,
        generation: UInt64,
        requestId: String?
    ) -> Bool {
        viewModel.isPresentingLocalRecord(
            scanId: scanId,
            generation: generation
        ) &&
            viewModel.state.communityRequestPresentationScanId?
                .caseInsensitiveCompare(scanId) == .orderedSame &&
            viewModel.state.communityRequestPresentationGeneration ==
                generation &&
            optionalIdentifiersMatch(
                viewModel.state.communityRequestPresentationRequestId,
                requestId
            ) &&
            optionalIdentifiersMatch(
                viewModel.state.sharedCommunityIdentificationRequestId,
                requestId
            )
    }

    private func exploreHashtagSuggestionContext(for speciesData: SpeciesData) -> ExploreHashtagSuggestionContext {
        ExploreHashtagSuggestionContext(
            speciesName: viewModel.resolvedHeaderTitle,
            scientificName: speciesData.scientificName,
            publicLocationLabel: visiblePublicLocationLabel(from: speciesData.locationName),
            fieldNotes: viewModel.shareableFieldNotes,
            ecologyType: speciesData.ecologyType,
            taxonomyKingdom: speciesData.taxonomy?.kingdom ?? viewModel.toolbarRecordSnapshot?.taxonomyKingdom,
            taxonomyClass: speciesData.taxonomy?.className ?? viewModel.toolbarRecordSnapshot?.taxonomyClass,
            taxonomyOrder: speciesData.taxonomy?.order ?? viewModel.toolbarRecordSnapshot?.taxonomyOrder,
            taxonomyFamily: speciesData.taxonomy?.family ?? viewModel.toolbarRecordSnapshot?.taxonomyFamily,
            habitatDescription: speciesData.habitatDescription ?? viewModel.toolbarRecordSnapshot?.habitatDescription,
            weatherCondition: speciesData.weatherCondition ?? viewModel.toolbarRecordSnapshot?.weatherCondition,
            colors: speciesData.colors ?? [],
            groupTags: speciesData.groupTags ?? [],
            semanticTags: viewModel.toolbarRecordSnapshot?.semanticTags ?? [],
            isInvasive: speciesData.isInvasive,
            imageQualityScore: speciesData.imageQualityScore ?? viewModel.toolbarRecordSnapshot?.imageQualityScore,
            lifeStage: speciesData.lifeStage,
            reproductiveCondition: speciesData.reproductiveCondition,
            ecologicalInteractions: speciesData.ecologicalInteractions ?? []
        )
        .updating(fieldNotes: viewModel.shareableFieldNotes)
    }

    private func visiblePublicLocationLabel(from locationName: String?) -> String? {
        ExploreLocationPrivacy.displayLabel(from: locationName)
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
