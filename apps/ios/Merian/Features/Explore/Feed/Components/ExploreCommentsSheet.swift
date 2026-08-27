import SwiftUI

struct ExploreCommentsSheet: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let post: ExplorePost

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @State private var reactingCommentId: String?
    @State private var navigationPath = NavigationPath()
    @State private var localReplyStateVersion: UInt64 = 0

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isCommentsLoading && viewModel.comments.isEmpty {
                    loadingState
                } else if viewModel.comments.isEmpty {
                    emptyState
                } else {
                    commentsScrollView
                }
            }
            .background(
                ExploreKeyboardDismissTapRecognizer(
                    isEnabled: isComposerFocused,
                    onTap: { isComposerFocused = false }
                )
            )
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Comments")
                            .font(.headline)
                        Text(viewModel.resolvedSpeciesCommonName(for: post))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
                    .background(
                        Color(uiColor: .systemBackground)
                            .ignoresSafeArea(edges: .bottom)
                            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
                    )
            }
            .navigationDestination(for: ExploreAuthorProfileRoute.self) { route in
                ExploreAuthorProfileContent(
                    viewModel: viewModel,
                    route: route,
                    presentation: .stack,
                    onClose: popNavigation,
                    onOpenPostRoute: { route in
                        navigationPath.append(route)
                    },
                    onOpenPublication: { publicationId in
                        navigationPath.append(
                            FieldTripPublicationRoute(publicationId: publicationId)
                        )
                    },
                    onOpenTemplate: { templateId in
                        navigationPath.append(FieldTripTemplateRoute(templateId: templateId))
                    }
                )
            }
            .navigationDestination(for: ExplorePostRoute.self) { route in
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: route.postId,
                    shouldFocusCommentComposer: route.shouldFocusCommentComposer,
                    shouldOpenInsight: route.shouldOpenInsight,
                    targetCommentId: route.targetCommentId,
                    targetReplyParentCommentId: route.targetReplyParentCommentId,
                    allowsInsightPresentation: false,
                    allowsAuthorProfilePresentation: ExploreAuthorProfileNavigationPolicy
                        .canOpenProfile(from: route.authorProfileDepth),
                    authorProfileDepth: route.authorProfileDepth,
                    onOpenAuthorProfile: { authorRoute in
                        appendAuthorProfileRoute(
                            authorRoute,
                            fromDepth: route.authorProfileDepth
                        )
                    }
                )
            }
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false,
                    exploreViewModel: viewModel
                )
            }
            .navigationDestination(for: FieldTripPublicationRoute.self) { route in
                FieldTripPublicationDetailView(publicationId: route.publicationId)
            }
            .navigationDestination(for: FieldTripTemplateRoute.self) { route in
                FieldTripTemplateDetailView(
                    reference: route.reference,
                    focusedChecklistItemId: route.focusedChecklistItemId,
                    onOpenCompletedScan: { _ in },
                    onOpenPublication: { publicationId in
                        navigationPath.append(
                            FieldTripPublicationRoute(publicationId: publicationId)
                        )
                    },
                    onOpenAuthorProfile: { _ in }
                )
            }
        }
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemBackground))
        .onChange(of: viewModel.commentDraft) { _, newValue in
            if newValue.count > 500 {
                viewModel.commentDraft = String(newValue.prefix(500))
            }
        }
        .background {
            ExploreReplyRenderInvalidationAnchor(version: localReplyStateVersion)
        }
        .onChange(of: viewModel.replyStateVersion) { _, newValue in
            localReplyStateVersion = newValue
        }
    }

    private var commentsScrollView: some View {
        ScrollView {
            ExploreCommentThreadList(
                viewModel: viewModel,
                post: post,
                layout: .sheet,
                targetCommentId: nil,
                targetReplyParentCommentId: nil,
                isComposerFocused: $isComposerFocused,
                reactingCommentId: $reactingCommentId,
                onOpenAuthorProfile: { route in
                    appendAuthorProfileRoute(route, fromDepth: 0)
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading comments...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            iconName: "bubble.left.and.bubble.right",
            title: "No comments yet",
            message: "Be the first to leave a note on this discovery."
        )
    }

    private var composer: some View {
        ExploreCommentComposer(
            viewModel: viewModel,
            post: post,
            isComposerFocused: $isComposerFocused,
            onDismissComposer: { isComposerFocused = false }
        )
    }

    private func appendAuthorProfileRoute(
        _ route: ExploreAuthorProfileRoute,
        fromDepth currentDepth: Int
    ) {
        guard ExploreAuthorProfileNavigationPolicy.canOpenProfile(from: currentDepth) else {
            return
        }

        navigationPath.append(
            route.withNavigationDepth(
                ExploreAuthorProfileNavigationPolicy.nextProfileDepth(from: currentDepth)
            )
        )
    }

    private func popNavigation() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }
}
