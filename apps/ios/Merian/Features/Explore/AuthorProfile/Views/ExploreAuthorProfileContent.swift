import SwiftData
import SwiftUI

struct ExploreAuthorProfileContent: View {
    enum Presentation: Equatable {
        case sheet
        case stack
    }

    enum Mode: Equatable {
        case profile
        case library
    }

    @Bindable var viewModel: ExploreFeedViewModel
    let route: ExploreAuthorProfileRoute
    let presentation: Presentation
    let onClose: () -> Void
    let onOpenPostRoute: (ExplorePostRoute) -> Void
    let onOpenPublication: (String) -> Void
    let onOpenTemplate: (String) -> Void

    @Environment(SupabaseManager.self) private var supabase
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var localScans: [LocalScanRecord]

    @State private var profileViewModel = ExploreAuthorProfileViewModel()
    @State private var mode = Mode.profile
    @State private var isReportUserPresented = false

    var body: some View {
        ZStack {
            switch profileViewModel.profileState {
            case .loading:
                ExploreAuthorProfileLoadingView(showsFollowButton: !isCurrentUserRoute)
                    .transition(.opacity)
            case .error(let message):
                errorState(message: message)
                    .transition(.opacity)
            case .loaded(let profile):
                loadedContent(profile)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(mode == .library)
        .navigationTitle(navigationTitle)
        .toolbar { toolbarContent }
        .task(id: route.authorUserId) {
            await loadProfile()
        }
        .sheet(isPresented: $isReportUserPresented) {
            if let profile = profileViewModel.profile {
                ExploreReportUserSheet(profile: profile) {
                    viewModel.toastMessage = .success("Report submitted for review.")
                }
            }
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            handleAppEvent(event)
        }
    }

    @ViewBuilder
    private func loadedContent(_ profile: ExploreAuthorProfile) -> some View {
        ZStack {
            if mode == .profile {
                profileContent(profile)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                libraryContent(profile)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: mode)
    }

    private var navigationTitle: String {
        guard mode == .library else { return "" }
        return ExploreAuthorProfilePresentation.libraryNavigationTitle(
            route: route,
            currentUserId: currentUserId
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if mode == .library || presentation == .sheet {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: leadingToolbarAction) {
                    Image(systemName: mode == .library ? "chevron.left" : "xmark")
                        .font(.system(size: 16, weight: .bold))
                }
                .accessibilityLabel(mode == .library ? "Back to profile" : "Close")
            }
        }

        if mode == .profile,
           let profile = profileViewModel.profile,
           profile.viewerCanReport == true {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isReportUserPresented = true
                    } label: {
                        Label("Report user", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Profile actions")
            }
        }
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Profile unavailable",
            message: message
        ) {
            Task { await loadProfile(force: true) }
        }
    }

    private func profileContent(_ profile: ExploreAuthorProfile) -> some View {
        let fieldTripsEnabled = FeatureFlags.isEnabled(.fieldTrips)
        let visibleAwards = ExploreAuthorProfilePresentation.visibleAwards(
            for: profile,
            fieldTripsEnabled: fieldTripsEnabled
        )
        let earnedPatches = ExploreAuthorProfilePresentation.earnedFieldTripPatches(
            for: profile,
            fieldTripsEnabled: fieldTripsEnabled
        )

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                ExploreAuthorProfileHeaderCard(
                    profile: profile,
                    visibleAwards: visibleAwards,
                    earnedPatches: earnedPatches,
                    showsProBadge: ExploreAuthorProfilePresentation.shouldShowProBadge(
                        profile: profile,
                        currentUserId: currentUserId,
                        currentUserIsSubscribed: revenueCatManager.isSubscribed
                    ),
                    onOpenFieldTrip: onOpenTemplate
                )

                if !isCurrentUserProfile(profile) {
                    ExploreAuthorProfileFollowButton(
                        isFollowing: profile.viewerIsFollowing,
                        isUpdating: profileViewModel.isUpdatingFollow
                    ) {
                        Task { await toggleFollow() }
                    }
                }

                UserStats(speciesCount: profile.speciesCount, streak: profile.currentStreak)
                ScansHeatmap(heatmapData: profile.profileHeatmapData)

                if fieldTripsEnabled,
                   let fieldTrips = profile.fieldTrips,
                   FieldTripProfilePresentation.hasContent(fieldTrips) {
                    FieldTripProfilePreview(
                        summaries: fieldTrips,
                        onOpenTemplate: onOpenTemplate,
                        onOpenPublication: onOpenPublication
                    )
                }

                ExploreAuthorProfilePublishedPreview(
                    profile: profile,
                    posts: Array(profile.previewPosts.prefix(ExploreAuthorProfilePresentation.previewLimit)),
                    mediaReloadGeneration: viewModel.mediaReloadGeneration,
                    localReferenceUrl: localReferenceUrl,
                    resolvedCommonName: viewModel.resolvedSpeciesCommonName,
                    onOpenPost: openPost,
                    onShowLibrary: showLibrary
                )

                if !visibleAwards.isEmpty {
                    Achievements(awards: visibleAwards, allowsDetailPresentation: false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func libraryContent(_ profile: ExploreAuthorProfile) -> some View {
        ExploreAuthorProfileLibraryView(
            profile: profile,
            posts: profileViewModel.libraryPosts,
            isLoading: profileViewModel.isLoadingLibrary,
            mediaReloadGeneration: viewModel.mediaReloadGeneration,
            localReferenceUrl: localReferenceUrl,
            resolvedCommonName: viewModel.resolvedSpeciesCommonName,
            onOpenPost: openPost,
            onLoadMore: {
                Task { await loadMoreLibraryPosts() }
            },
            onRefresh: {
                await reloadLibrary(from: profile)
            }
        )
    }

    private var currentUserId: String? {
        supabase.currentUser?.id.uuidString
    }

    private var isCurrentUserRoute: Bool {
        ExploreAuthorProfilePresentation.isCurrentUser(
            authorUserId: route.authorUserId,
            currentUserId: currentUserId
        )
    }

    private func isCurrentUserProfile(_ profile: ExploreAuthorProfile) -> Bool {
        ExploreAuthorProfilePresentation.isCurrentUser(
            authorUserId: profile.authorUserId,
            currentUserId: currentUserId
        )
    }

    private func localReferenceUrl(for post: ExplorePost) -> String? {
        guard isCurrentUserRoute else { return nil }
        return localScans.first { $0.id == post.scanId }?.referenceImageUrl
    }

    private var localReferenceUrlsByScanId: [String: String] {
        guard isCurrentUserRoute else { return [:] }
        return localScans.reduce(into: [:]) { urls, scan in
            if let referenceImageUrl = scan.referenceImageUrl {
                urls[scan.id] = referenceImageUrl
            }
        }
    }

    private func leadingToolbarAction() {
        switch mode {
        case .profile:
            onClose()
        case .library:
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                mode = .profile
            }
        }
    }

    private func showLibrary() {
        guard let profile = profileViewModel.profile else { return }
        profileViewModel.seedLibraryIfNeeded(from: profile)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            mode = .library
        }

        Task { await loadMoreLibraryPosts() }
    }

    private func handleAppEvent(_ event: AppEvent) {
        guard case .publicAuthorIdentityChanged(let previousUserId, let currentUserId) = event,
              ExploreAuthorProfilePresentation.identityChangeAffects(
                  authorUserId: route.authorUserId,
                  previousUserId: previousUserId,
                  currentUserId: currentUserId
              ) else { return }

        if previousUserId == route.authorUserId.lowercased(),
           currentUserId != route.authorUserId.lowercased() {
            onClose()
        } else {
            Task { await loadProfile(force: true) }
        }
    }

    private func loadProfile(force: Bool = false) async {
        let posts = await profileViewModel.loadProfile(
            authorUserId: route.authorUserId,
            force: force,
            localReferenceUrlsByScanId: localReferenceUrlsByScanId
        )
        registerPosts(posts)
    }

    private func toggleFollow() async {
        await profileViewModel.toggleFollow(currentUserId: currentUserId)
        presentInteractionErrorIfNeeded()
    }

    private func reloadLibrary(from profile: ExploreAuthorProfile) async {
        let posts = await profileViewModel.reloadLibrary(
            authorUserId: route.authorUserId,
            fallbackProfile: profile
        )
        registerPosts(posts)
        presentInteractionErrorIfNeeded()
    }

    private func loadMoreLibraryPosts() async {
        let posts = await profileViewModel.loadMoreLibraryPosts(authorUserId: route.authorUserId)
        registerPosts(posts)
        presentInteractionErrorIfNeeded()
    }

    private func presentInteractionErrorIfNeeded() {
        guard let message = profileViewModel.takeInteractionErrorMessage() else { return }
        viewModel.toastMessage = .error(message)
    }

    private func registerPosts(_ posts: [ExplorePost]) {
        guard !posts.isEmpty else { return }
        for post in posts {
            viewModel.upsertPost(post)
        }
        viewModel.refreshPreferredSpeciesNames(
            for: posts.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }

    private func openPost(_ post: ExplorePost) {
        viewModel.upsertPost(post)
        viewModel.refreshPreferredSpeciesNames(
            for: [post.speciesScientificName],
            modelContext: modelContext
        )
        onOpenPostRoute(ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil,
            authorProfileDepth: route.navigationDepth
        ))
    }
}
