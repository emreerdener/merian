import SwiftData
import SwiftUI
import UIKit

struct ExploreFeedTabContent: View {
    @Bindable var viewModel: ExploreFeedViewModel
    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(ExploreVideoPlaybackCoordinator.self) private var playbackCoordinator: ExploreVideoPlaybackCoordinator?
    @Environment(SupabaseManager.self) private var supabase
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var isLocationSettingsAlertPresented = false
    @State private var isResolvingNearbyLocation = false
    @State private var isShowingFilterSheet = false
    @State private var editingPost: ExplorePost?
    @State private var postEditorViewModel: ExplorePostDetailViewModel?
    @State private var editingPostLocalFieldNotes: String?
    let onOpenPostDetail: (ExplorePost) -> Void
    let onOpenFieldTrip: (FieldTripRecentPublication) -> Void
    let onOpenAuthorProfile: (ExplorePost) -> Void
    let onOpenFieldTripAuthorProfile: (FieldTripRecentPublication) -> Void
    let onOpenHashtag: (String) -> Void
    let onOpenInsight: ((ExplorePost) -> Void)?

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            feedScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .alert("Turn On Location", isPresented: $isLocationSettingsAlertPresented) {
            Button("Not Now", role: .cancel) {}
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    openURL(settingsURL)
                }
            }
        } message: {
            Text("Nearby uses your current location to show discoveries shared within \(viewModel.advancedFilters.nearbyRadius.rawValue) miles.")
        }
        .sheet(isPresented: $isShowingFilterSheet) {
            feedFilterSheet
                .exploreVideoPresentedOverlayLifecycle(reason: "explore-feed-filter-sheet")
        }
        .sheet(item: $editingPost, onDismiss: {
            clearPostEditor()
        }) { post in
            ExplorePostComposerView(
                mode: .edit,
                speciesName: postSnapshotCommonName(for: post),
                scientificName: post.speciesScientificName,
                heroImageUrl: post.heroImageUrl,
                publicLocationLabel: post.publicDisplayLocationLabel,
                commonNameOptions: commonNameOptions(for: post, detail: postEditorViewModel?.detail),
                initialSelectedCommonName: postSnapshotCommonName(for: post),
                initialFieldNotes: postEditorViewModel?.detail?.trimmedFieldNotes ?? editingPostLocalFieldNotes,
                initialFieldNotesArePublic: postEditorViewModel?.detail?.trimmedFieldNotes != nil,
                initialHashtags: postEditorViewModel?.detail?.hashtags ?? post.hashtags ?? [],
                initialLocationSharing: postEditorViewModel?.detail?.locationSharing ?? post.locationSharing ?? .obscured,
                mediaItems: postEditorViewModel?.postComposerMediaItems ?? [],
                isSaving: postEditorViewModel?.isSavingPostContent == true,
                onSubmit: { draft in
                    Task { await saveEditedPost(draft, for: post) }
                }
            )
            .exploreVideoPresentedOverlayLifecycle(reason: "explore-feed-edit-post-sheet")
        }
    }

    private var feedScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar

                if viewModel.isLoadingInitialFeed && viewModel.feedItems.isEmpty {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage, viewModel.feedItems.isEmpty {
                    errorState(message: errorMessage)
                } else if viewModel.feedItems.isEmpty {
                    emptyState
                } else {
                    feedItems
                }
            }
        }
        .refreshable {
            await refreshFeed()
        }
        .onAppear {
            ExploreVideoMutePreference.resetToMuted()
        }
    }

    private var feedItems: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.feedItems) { item in
                switch item {
                case .observation(let post):
                    ExplorePostCard(
                        post: post,
                        speciesDisplayName: viewModel.resolvedSpeciesCommonName(for: post),
                        mediaReloadGeneration: viewModel.mediaReloadGeneration,
                        authorPresentation: postCardAuthorPresentation(for: post),
                        onLike: { Task { await viewModel.toggleLike(for: post) } },
                        onComments: {
                            Task { await viewModel.openCommentsSheet(for: post) }
                        },
                        onShare: { viewModel.share(post, playbackCoordinator: playbackCoordinator) },
                        onOpenDetail: { onOpenPostDetail(post) },
                        onOpenAuthorProfile: { onOpenAuthorProfile(post) },
                        onOpenHashtag: onOpenHashtag,
                        onOpenInsight: onOpenInsight.map { callback in
                            { callback(post) }
                        },
                        onEditPost: { Task { await openPostEditor(for: post) } },
                        onUnshare: { Task { await viewModel.unshare(post) } },
                        onBlock: { Task { await viewModel.blockAuthor(of: post) } },
                        onReport: { Task { await viewModel.report(post) } }
                    )
                    .onAppear {
                        Task { await viewModel.loadMoreIfNeeded(currentPost: post) }
                    }
                case .fieldTrip(let publication):
                    FieldTripCommunityPublicationCard(
                        publication: publication,
                        onOpenPublication: { _ in onOpenFieldTrip(publication) },
                        onOpenAuthorProfile: onOpenFieldTripAuthorProfile
                    )
                    .padding(.horizontal, 16)
                }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func postCardAuthorPresentation(
        for post: ExplorePost
    ) -> ExplorePostCardAuthorPresentation {
        ExplorePostCardAuthorPresentation.resolve(
            authorAvatarURL: post.authorAvatarUrl,
            authorUserID: post.authorUserId,
            authorIsPro: post.authorIsPro,
            isOwnedByViewer: post.isOwnedByViewer,
            viewer: ExplorePostCardViewerContext(
                userID: supabase.currentUser?.id.uuidString,
                avatarURL: supabase.currentUserAvatarUrl,
                isSubscribed: revenueCatManager.isSubscribed
            )
        )
    }

    private var loadingState: some View {
        LazyVStack(spacing: 24) {
            ForEach(0..<3, id: \.self) { _ in
                ExplorePostCard.Skeleton()
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var emptyState: some View {
        EmptyStateView(
            imageName: "nature-scene",
            imageHeight: 300,
            title: emptyStateTitle,
            message: emptyStateMessage
        )
        .padding(.top, 60)
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Explore unavailable",
            message: message
        ) {
            Task { await refreshFeed() }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 520)
    }

    private var emptyStateTitle: String {
        if viewModel.hasActiveAdvancedFilters {
            return "No matching discoveries"
        }

        switch viewModel.activeFilter {
        case .recent:
            return "Nothing shared yet"
        case .following:
            return "No followed discoveries yet"
        case .trending:
            return "Nothing trending yet"
        case .nearby:
            return "Nothing nearby yet"
        }
    }

    private var emptyStateMessage: String {
        if viewModel.hasActiveAdvancedFilters {
            return "Try removing one or more filters to broaden the feed."
        }

        switch viewModel.activeFilter {
        case .recent:
            return "Shared discoveries will show up here once people publish scans to Explore."
        case .following:
            return "Follow authors from their public profiles to build this feed."
        case .trending:
            return "Freshly liked discoveries will appear here as the community reacts."
        case .nearby:
            return "We couldn’t find shared discoveries within \(viewModel.advancedFilters.nearbyRadius.rawValue) miles of your current location."
        }
    }

    private func selectFilter(_ filter: ExploreFeedFilter) async {
        guard filter.requiresLocation else {
            await viewModel.selectFilter(filter)
            return
        }

        await activateNearbyFeedSelection()
    }

    private func refreshFeed() async {
        guard viewModel.activeFilter == .nearby else {
            await viewModel.refreshFeed()
            return
        }

        await activateNearbyFeedSelection(isRefresh: true)
    }

    @MainActor
    private func openPostEditor(for post: ExplorePost) async {
        guard post.isOwnedByViewer else { return }

        editingPostLocalFieldNotes = FieldNotesRepository.fieldNotes(
            for: post.scanId,
            modelContext: modelContext
        )

        let editorViewModel = ExplorePostDetailViewModel(postId: post.id)
        do {
            try await editorViewModel.prepareEditor(
                existingMediaItems: post.mediaItems ?? []
            )
        } catch {
            postEditorViewModel = nil
            viewModel.toastMessage = .error(ExploreErrorFormatter.message(for: error))
            return
        }

        postEditorViewModel = editorViewModel
        HapticManager.shared.triggerSelectionPulse()
        editingPost = post
    }

    @MainActor
    private func saveEditedPost(_ draft: ExplorePostComposerDraft, for post: ExplorePost) async {
        guard post.isOwnedByViewer,
              let postEditorViewModel,
              postEditorViewModel.postId == post.id,
              !postEditorViewModel.isSavingPostContent else { return }

        do {
            persistPreferredCommonName(draft.selectedCommonName, scientificName: post.speciesScientificName)
            _ = try await postEditorViewModel.updateContent(draft)
            updateLocalFieldNotes(draft.fieldNotes ?? "", for: post)
            editingPost = nil
            await viewModel.refreshPost(postId: post.id)
            viewModel.refreshPreferredSpeciesNames(for: [post.speciesScientificName], modelContext: modelContext)
            HapticManager.shared.triggerSuccessPulse()
            viewModel.toastMessage = .success("Explore post updated")
        } catch {
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = .error(ExploreErrorFormatter.message(for: error))
        }
    }

    @MainActor
    private func updateLocalFieldNotes(_ notes: String, for post: ExplorePost) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = FieldNotesRepository.setFieldNotes(
            notes,
            for: post.scanId,
            modelContext: modelContext
        )
        editingPostLocalFieldNotes = trimmed.isEmpty ? nil : notes
    }

    private func clearPostEditor() {
        postEditorViewModel = nil
        editingPostLocalFieldNotes = nil
    }

    private func postSnapshotCommonName(for post: ExplorePost) -> String {
        let trimmed = post.speciesCommonName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? viewModel.resolvedSpeciesCommonName(
                scientificName: post.speciesScientificName,
                fallbackCommonName: post.speciesCommonName
            )
            : trimmed
    }

    private func commonNameOptions(for post: ExplorePost, detail: ExplorePostDetail?) -> [String] {
        ([postSnapshotCommonName(for: post)] + (detail?.alternativeCommonNames ?? []))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removingFuzzyDuplicateNames()
    }

    private func persistPreferredCommonName(_ name: String, scientificName: String) {
        guard let ownerUserID = supabase.currentUser?.id else { return }
        _ = SpeciesPreferredNameRepository.setPreferredName(
            name,
            for: scientificName,
            ownerUserID: ownerUserID,
            modelContext: modelContext
        )
    }

    private func activateNearbyFeedSelection(isRefresh: Bool = false) async {
        guard !isResolvingNearbyLocation else { return }

        isResolvingNearbyLocation = true
        defer { isResolvingNearbyLocation = false }

        guard let location = await environmentContextManager.requestCurrentLocation() else {
            handleNearbyLocationFailure()
            return
        }

        if isRefresh {
            await viewModel.refreshFeed(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        } else {
            await viewModel.selectFilter(
                .nearby,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
    }

    private func handleNearbyLocationFailure() {
        switch environmentContextManager.locationAuthorizationStatus {
        case .denied:
            isLocationSettingsAlertPresented = true
        case .restricted:
            viewModel.toastMessage = .warning("Location access is restricted on this device.")
        default:
            viewModel.toastMessage = .error(
                "We couldn’t determine your location right now. Try again in a moment."
            )
        }
    }

    private var filterBar: some View {
        CategoryFilterBar(
            items: ExploreFeedFilter.allCases,
            activeItem: viewModel.activeFilter,
            title: { $0.title },
            leadingTitle: viewModel.hasActiveAdvancedFilters
                ? "Filters \(viewModel.activeAdvancedFilterCount.formatted())"
                : "Filters",
            leadingSystemImage: "line.3.horizontal.decrease",
            isLeadingSelected: viewModel.hasActiveAdvancedFilters,
            loadingItem: isResolvingNearbyLocation ? .nearby : nil,
            onSelection: { filter in
                Task {
                    await selectFilter(filter)
                }
            },
            onLeadingSelection: {
                HapticManager.shared.triggerSelectionPulse()
                isShowingFilterSheet = true
            }
        )
        .disabled(isResolvingNearbyLocation)
    }

    private var feedFilterSheet: some View {
        ExploreFeedFilterSheet(
            viewModel: viewModel,
            isPresented: $isShowingFilterSheet,
            isResolvingNearbyLocation: isResolvingNearbyLocation,
            onSelectFilter: { filter in
                Task { await selectFilter(filter) }
            }
        )
    }
}
