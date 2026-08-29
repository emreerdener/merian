import SwiftData
import SwiftUI

@MainActor
struct ProfilePublishedScansLibraryView: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let authorUserID: String

    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse)
    private var localScans: [LocalScanRecord]

    @State private var publications: ProfilePublishedScansViewModel
    @State private var selectedPostRoute: ExplorePostRoute?
    @State private var selectedInsightRoute: ScanInsightRoute?

    private let columns = PublishedScanGridStyle.columns

    init(
        viewModel: ExploreFeedViewModel,
        authorUserID: String,
        dependencies: ProfilePublicationsDependencies? = nil
    ) {
        self.viewModel = viewModel
        self.authorUserID = authorUserID
        _publications = State(
            initialValue: ProfilePublishedScansViewModel(
                dependencies: dependencies ?? .live
            )
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                    .padding(.horizontal, 16)

                if let recoverySummary {
                    ProfilePublicationRecoverySummaryView(
                        summary: recoverySummary,
                        ownerUserID: authorUserID,
                        onReview: reviewRecovery,
                        onDismissFeedback: publications.selectionFeedback
                    )
                    .padding(.horizontal, 16)
                }

                if publications.posts.isEmpty && publications.isLoading {
                    loadingGrid(count: 12)
                } else if publications.didFail && publications.posts.isEmpty {
                    Text("Published scans unavailable right now.")
                        .profileExploreStateStyle()
                        .padding(.horizontal, 16)
                } else if publications.posts.isEmpty {
                    Text(
                        recoverySummary?.userFacingEmptyMessage ??
                            "No published scans yet."
                    )
                    .profileExploreStateStyle()
                    .padding(.horizontal, 16)
                } else {
                    libraryGrid
                }

                if publications.isLoading && !publications.posts.isEmpty {
                    loadingGrid(count: 6)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Your published scans")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: authorUserID) {
            registerPosts(await publications.reload(authorUserID: authorUserID))
        }
        .onReceive(publications.appEvents) { event in
            guard case .publicAuthorIdentityChanged(
                let previousUserID,
                let currentUserID
            ) = event,
            publications.identityChangeAffects(
                authorUserID: authorUserID,
                previousUserID: previousUserID,
                currentUserID: currentUserID
            ) else { return }

            Task {
                registerPosts(
                    await publications.reload(authorUserID: authorUserID)
                )
                await profileViewModel.fetchSocialStats()
            }
        }
        .onChange(of: profileViewModel.socialStats) { _, stats in
            clearRecoveryDismissalIfResolved(stats: stats)
        }
        .refreshable {
            registerPosts(await publications.reload(authorUserID: authorUserID))
        }
        .navigationDestination(isPresented: postRouteBinding) {
            if let selectedPostRoute {
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: selectedPostRoute.postId,
                    shouldFocusCommentComposer: selectedPostRoute
                        .shouldFocusCommentComposer,
                    shouldOpenInsight: selectedPostRoute.shouldOpenInsight,
                    targetCommentId: selectedPostRoute.targetCommentId,
                    targetReplyParentCommentId: selectedPostRoute
                        .targetReplyParentCommentId,
                    allowsInsightPresentation: false,
                    onOpenOwnedPostInsight: openInsight
                )
            }
        }
        .sheet(item: $selectedInsightRoute) { route in
            LocalScanInsightLoader(scanId: route.scanId) {
                InsightSheetView(
                    isPresented: Binding(
                        get: { selectedInsightRoute != nil },
                        set: { if !$0 { selectedInsightRoute = nil } }
                    ),
                    initialScanId: route.scanId,
                    inferenceEngine: inferenceEngine,
                    allowsExplorePresentation: false
                )
            }
        }
    }

    private var postRouteBinding: Binding<Bool> {
        Binding(
            get: { selectedPostRoute != nil },
            set: { if !$0 { selectedPostRoute = nil } }
        )
    }

    private var recoverySummary: ProfilePublicationRecoverySummary? {
        profileViewModel.socialStats.flatMap(
            ProfilePublicationRecoverySummary.publishedOnly
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProfileAuthorAvatar(url: profileViewModel.userAvatarURL, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(
                        profileViewModel.userName ??
                            profileViewModel.publicAuthorName ?? "Explorer"
                    )
                    .font(.headline)
                    .lineLimit(1)

                    if revenueCatManager.isSubscribed {
                        MerianProBadge()
                    }
                }

                if let username = profileViewModel.publicUsernameDisplayName {
                    Text(username)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let count = profileViewModel.socialStats?
                    .visiblePublishedPostCount {
                    let noun = count == 1 ? "scan" : "scans"
                    Text("\(count.formatted(.number)) visible published \(noun)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var libraryGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(publications.posts) { post in
                let localReferenceURL = localScans.first {
                    $0.id == post.scanId
                }?.referenceImageUrl
                Button {
                    openPost(post)
                } label: {
                    ProfilePublicScanImageView(
                        imagePath: nil,
                        fallbackURL: post.gridThumbnailUrl(
                            localReferenceUrl: localReferenceURL
                        ),
                        reloadGeneration: viewModel.mediaReloadGeneration
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .bottomTrailing) {
                        if post.hasVideoMedia || post.hasAudioMedia {
                            ExploreMediaTypeIndicator(
                                kind: post.hasVideoMedia ? .video : .audio
                            )
                            .padding(8)
                        }
                    }
                    .clipped()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(viewModel.resolvedSpeciesCommonName(for: post)), published scan"
                )
                .task {
                    guard post.id == publications.posts.last?.id else { return }
                    registerPosts(
                        await publications.loadMore(
                            authorUserID: authorUserID
                        )
                    )
                }
            }
        }
    }

    private func loadingGrid(count: Int) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in
                GlowPulsingSkeletonView(cornerRadius: 3, style: .raisedGrid)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }

    private func registerPosts(_ posts: [ExplorePost]) {
        guard !posts.isEmpty else { return }
        posts.forEach { viewModel.upsertPost($0) }
        viewModel.refreshPreferredSpeciesNames(
            for: posts.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }

    private func openPost(_ post: ExplorePost) {
        registerPosts([post])
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil
        )
    }

    private func openInsight(scanId: String) -> Bool {
        guard let route = publications.insightRoute(
            scanID: scanId,
            modelContext: modelContext
        ) else { return false }
        selectedInsightRoute = route
        return true
    }

    private func reviewRecovery() {
        guard recoverySummary != nil else { return }
        publications.reviewRecovery(ownerUserID: authorUserID)
    }

    private func clearRecoveryDismissalIfResolved(
        stats: ProfileSocialStats?
    ) {
        guard let stats,
              ProfilePublicationRecoverySummary.publishedOnly(from: stats) == nil
        else { return }
        ProfileRecoveryNoticePreferences.clear(ownerUserID: authorUserID)
    }
}
