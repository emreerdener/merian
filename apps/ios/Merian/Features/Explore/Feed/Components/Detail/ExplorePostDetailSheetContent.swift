import SwiftUI

struct ExplorePostDetailSheetContent: View {
    @Bindable var feedViewModel: ExploreFeedViewModel
    @Bindable var detailViewModel: ExplorePostDetailViewModel
    @Bindable var chatViewModel: InsightChatViewModel
    @Binding var presentedSheet: ExplorePostDetailPresentation?

    let presentation: ExplorePostDetailPresentation
    let currentPost: ExplorePost?
    let localFieldNotes: String?
    let onUpdateLocalFieldNotes: @MainActor (String) -> Void
    let onSaveFieldNotes: @MainActor (
        _ text: String,
        _ isPublic: Bool,
        _ post: ExplorePost
    ) async -> FieldNotesVisibilityUpdateFeedback
    let onSavePost: @MainActor (
        _ draft: ExplorePostComposerDraft,
        _ post: ExplorePost
    ) async -> Void
    let onOpenCommunityIdentificationRequest: @MainActor (String) -> Void

    @Environment(InferenceEngine.self) private var inferenceEngine

    var body: some View {
        switch presentation {
        case .insight(let route):
            LocalScanInsightLoader(scanId: route.scanId) {
                InsightSheetView(
                    isPresented: isPresentedBinding,
                    initialScanId: route.scanId,
                    inferenceEngine: inferenceEngine,
                    allowsExplorePresentation: false,
                    onOpenCommunityIdentificationRequest: onOpenCommunityIdentificationRequest
                )
            }
            .exploreVideoPresentedOverlayLifecycle(
                reason: "explore-post-detail-insight-sheet"
            )

        case .author(let route):
            ExploreAuthorProfileSheet(viewModel: feedViewModel, route: route)
                .exploreVideoPresentedOverlayLifecycle(
                    reason: "explore-post-detail-author-profile-sheet"
                )

        case .notificationReply(let route):
            ExploreNotificationReplyThreadSheet(viewModel: feedViewModel, route: route)
                .exploreVideoPresentedOverlayLifecycle(
                    reason: "explore-post-detail-reply-thread-sheet"
                )

        case .fieldNotes:
            Group {
                if let post = matchingPost {
                    FieldNotesSheet(
                        text: Binding(
                            get: {
                                localFieldNotes
                                    ?? detailViewModel.detail?.trimmedFieldNotes
                                    ?? ""
                            },
                            set: onUpdateLocalFieldNotes
                        ),
                        promptContext: .resolved(subjectId: nil),
                        visibilityConfiguration: FieldNotesVisibilityConfiguration(
                            initialIsPublic: detailViewModel.detail?.trimmedFieldNotes != nil,
                            onSave: { text, isPublic in
                                await onSaveFieldNotes(text, isPublic, post)
                            }
                        )
                    )
                }
            }
            .exploreVideoPresentedOverlayLifecycle(
                reason: "explore-post-detail-field-notes-sheet"
            )

        case .postComposer:
            Group {
                if let post = matchingPost {
                    ExplorePostComposerView(
                        mode: .edit,
                        speciesName: postSnapshotCommonName(for: post),
                        scientificName: post.speciesScientificName,
                        heroImageUrl: post.heroImageUrl,
                        publicLocationLabel: post.publicDisplayLocationLabel,
                        commonNameOptions: commonNameOptions(for: post),
                        initialSelectedCommonName: postSnapshotCommonName(for: post),
                        initialFieldNotes: detailViewModel.detail?.trimmedFieldNotes ?? localFieldNotes,
                        initialFieldNotesArePublic: detailViewModel.detail?.trimmedFieldNotes != nil,
                        initialHashtags: detailViewModel.detail?.hashtags ?? post.hashtags ?? [],
                        initialLocationSharing: detailViewModel.detail?.locationSharing
                            ?? post.locationSharing
                            ?? .obscured,
                        mediaItems: detailViewModel.postComposerMediaItems,
                        isSaving: detailViewModel.isSavingPostContent,
                        onSubmit: { draft in
                            Task { await onSavePost(draft, post) }
                        }
                    )
                }
            }
            .exploreVideoPresentedOverlayLifecycle(
                reason: "explore-post-detail-edit-post-sheet"
            )

        case .fieldChat:
            Group {
                if let post = matchingPost {
                    InsightChatSheet(
                        viewModel: chatViewModel,
                        scanId: post.id,
                        speciesData: nil,
                        displayName: feedViewModel.resolvedSpeciesCommonName(for: post),
                        timestamp: post.sharedAtDate,
                        publicScientificName: post.speciesScientificName,
                        publicAlternativeNames: detailViewModel.detail?.similarSpecies?.map(\.scientificName) ?? [],
                        allowsOwnerActions: false,
                        prepareForInitialLoad: nil,
                        onToast: { feedViewModel.toastMessage = $0 },
                        onAppendToFieldNotes: { _, _ in },
                        onReviewAlternatives: nil,
                        onReanalyzeSpecies: nil,
                        onClose: dismiss
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                }
            }
            .exploreVideoPresentedOverlayLifecycle(
                reason: "explore-post-detail-field-chat-sheet"
            )

        case .paywall:
            PaywallView()
                .exploreVideoPresentedOverlayLifecycle(
                    reason: "explore-post-detail-paywall-sheet"
                )
        }
    }

    private var matchingPost: ExplorePost? {
        guard let expectedPostID, let currentPost,
              currentPost.id.caseInsensitiveCompare(expectedPostID) == .orderedSame else {
            return nil
        }
        return currentPost
    }

    private var expectedPostID: String? {
        switch presentation {
        case .fieldNotes(let postID), .postComposer(let postID), .fieldChat(let postID):
            postID
        case .insight, .author, .notificationReply, .paywall:
            nil
        }
    }

    private var isPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedSheet?.id == presentation.id },
            set: { isPresented in
                guard !isPresented else { return }
                dismiss()
            }
        )
    }

    private func dismiss() {
        guard presentedSheet?.id == presentation.id else { return }
        presentedSheet = nil
    }

    private func postSnapshotCommonName(for post: ExplorePost) -> String {
        let trimmed = post.speciesCommonName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? feedViewModel.resolvedSpeciesCommonName(
                scientificName: post.speciesScientificName,
                fallbackCommonName: post.speciesCommonName
            )
            : trimmed
    }

    private func commonNameOptions(for post: ExplorePost) -> [String] {
        ([postSnapshotCommonName(for: post)] + (detailViewModel.detail?.alternativeCommonNames ?? []))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removingFuzzyDuplicateNames()
    }
}
