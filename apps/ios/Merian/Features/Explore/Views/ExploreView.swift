import SwiftData
import SwiftUI
import UIKit

enum ExploreTab: Hashable {
    case feed
    case community
    case map
    case dictionary
}

private enum ExploreDictionaryMode: Hashable {
    case dictionary
    case tree
}

struct ExploreView: View {
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(AppSettings.self) private var appSettings
    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreFeedViewModel()
    @State private var mapViewModel = ExploreMapViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var selectedAuthorProfileRoute: ExploreAuthorProfileRoute?
    @State private var selectedInsightRoute: ScanInsightRoute?
    @State private var activeTab: ExploreTab = .feed
    @State private var activeDictionaryMode: ExploreDictionaryMode = .dictionary
    @State private var dictionarySearchText = ""
    @State private var dictionaryUserRegionIdentifier = Self.defaultDictionaryUserRegionIdentifier()

    private let allowsInsightPresentation: Bool

    private var activeTabBinding: Binding<ExploreTab> {
        Binding(
            get: { activeTab },
            set: { newValue in
                guard newValue != activeTab else { return }
                selectExploreTab(newValue)
            }
        )
    }

    private var isDictionarySearchActive: Bool {
        !dictionarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        initialPostId: String? = nil,
        initialTargetCommentId: String? = nil,
        initialTargetReplyParentCommentId: String? = nil,
        allowsInsightPresentation: Bool = true
    ) {
        self.allowsInsightPresentation = allowsInsightPresentation
        if let postId = initialPostId {
            var initialPath = NavigationPath()
            initialPath.append(ExplorePostRoute(
                postId: postId,
                shouldFocusCommentComposer: false,
                shouldOpenInsight: false,
                targetCommentId: initialTargetCommentId,
                targetReplyParentCommentId: initialTargetReplyParentCommentId
            ))
            _navigationPath = State(initialValue: initialPath)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TabView(selection: activeTabBinding) {
                ExploreFeedTabContent(
                    viewModel: viewModel,
                    onOpenPostDetail: { openPostDetail(for: $0) },
                    onOpenAuthorProfile: { openAuthorProfile(for: $0) },
                    onOpenHashtag: openHashtag,
                    onOpenInsight: allowsInsightPresentation ? { openInsight(for: $0) } : nil
                )
                .tag(ExploreTab.feed)
                .tabItem {
                    Label("Feed", systemImage: "photo.stack")
                }

                ExploreCommunityIdentificationView { route in
                    navigationPath.append(route)
                }
                .tag(ExploreTab.community)
                .tabItem {
                    Label("Community", systemImage: "person.2")
                }

                ExploreMapView(
                    viewModel: mapViewModel,
                    feedViewModel: viewModel,
                    postStore: viewModel.store,
                    onOpenDetail: { post, focusCommentComposer in
                        openPostDetail(for: post, focusCommentComposer: focusCommentComposer)
                    }
                )
                .tag(ExploreTab.map)
                .tabItem {
                    Label("Map", systemImage: "map")
                }

                dictionaryTabContent
                .background(Color(uiColor: .systemGroupedBackground))
                .tag(ExploreTab.dictionary)
                .tabItem {
                    Label("Dictionary", systemImage: "book.closed")
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ExplorePostRoute.self) { route in
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: route.postId,
                    shouldFocusCommentComposer: route.shouldFocusCommentComposer,
                    shouldOpenInsight: route.shouldOpenInsight,
                    targetCommentId: route.targetCommentId,
                    targetReplyParentCommentId: route.targetReplyParentCommentId,
                    notificationReplyThreadTarget: route.notificationReplyThreadTarget,
                    allowsInsightPresentation: allowsInsightPresentation
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: SpeciesDictionaryCategoryRoute.self) { route in
                switch route {
                case .catalog(let title, let category, let region):
                    SpeciesDictionaryCatalogView(
                        isSearchEnabled: false,
                        isBottomSearchEnabled: true,
                        showsNavigationTitle: true,
                        navigationTitle: title,
                        category: category,
                        region: region
                    )
                    .toolbar(.hidden, for: .tabBar)
                case .group(let title, let group):
                    SpeciesDictionaryCatalogView(
                        isSearchEnabled: false,
                        isBottomSearchEnabled: true,
                        showsNavigationTitle: true,
                        navigationTitle: title,
                        category: .group,
                        group: group
                    )
                    .toolbar(.hidden, for: .tabBar)
                case .taxonomy:
                    TaxonomyTreeCanvasView(showsNavigationTitle: true) { speciesRoute in
                        navigationPath.append(speciesRoute)
                    }
                    .toolbar(.hidden, for: .tabBar)
                case .regions:
                    SpeciesDictionaryRegionsView(userRegion: dictionaryUserRegionIdentifier)
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            .navigationDestination(for: ExploreHashtagRoute.self) { route in
                ExploreHashtagPostsView(
                    viewModel: viewModel,
                    route: route,
                    allowsInsightPresentation: allowsInsightPresentation
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: ExploreCommunityRequestRoute.self) { route in
                ExploreCommunityIdentificationDetailView(requestId: route.requestId)
                    .toolbar(.hidden, for: .tabBar)
            }
            .toolbar { exploreToolbar }
        }
        .task {
            viewModel.bindSettings(appSettings)
            await viewModel.loadInitialFeed()
            viewModel.refreshPreferredSpeciesNames(modelContext: modelContext)
        }
        .onChange(of: viewModel.store.changeVersion) { _, _ in
            viewModel.refreshPreferredSpeciesNames(modelContext: modelContext)
        }
        .onChange(of: activeTab) { _, newValue in
            if newValue == .map {
                AppTelemetry.trackExploreMapOpened()
            }
        }
        .task(id: activeTab) {
            guard activeTab == .dictionary else { return }
            await refreshDictionaryUserRegionFromAuthorizedLocation()
        }
        .task {
            await viewModel.startUnreadNotificationUpdates()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await viewModel.refreshUnreadNotificationCount()
            }
        }
        .onDisappear {
            viewModel.stopUnreadNotificationUpdates()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isCommentsSheetPresented },
                set: { if !$0 { viewModel.dismissCommentsSheet() } }
            )
        ) {
            if let post = viewModel.activeCommentsPost {
                ExploreCommentsSheet(viewModel: viewModel, post: post)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isNotificationsSheetPresented },
                set: { if !$0 { viewModel.dismissNotifications() } }
            ),
            onDismiss: {
                Task { await viewModel.refreshUnreadNotificationCount() }
            }
        ) {
            ExploreNotificationsSheet(
                onUnreadNotificationsCleared: {
                    viewModel.unreadNotificationCount = 0
                    AppIconBadgeCoordinator.clearExploreUnreadNotificationCount()
                },
                onOpenNotification: { notification in
                    await openNotification(notification)
                }
            )
        }
        .sheet(
            item: $selectedInsightRoute,
            onDismiss: {
                viewModel.refreshPreferredSpeciesNames(modelContext: modelContext)
            }
        ) { route in
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
        .sheet(item: $selectedAuthorProfileRoute) { route in
            ExploreAuthorProfileSheet(viewModel: viewModel, route: route)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.refreshUnreadNotificationCount() }
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .explorePostNeedsRefresh(let postId):
                Task { await viewModel.refreshPost(postId: postId) }
            case .publicAuthorIdentityChanged(let previousUserId, let currentUserId):
                selectedAuthorProfileRoute = selectedAuthorProfileRoute.flatMap { route in
                    authorIdentityChangeAffects(route.authorUserId, previousUserId: previousUserId, currentUserId: currentUserId)
                        ? nil
                        : route
                }
                Task {
                    await viewModel.refreshFeed()
                    mapViewModel.syncPosts(from: viewModel.store.allPosts)
                }
            default:
                break
            }
        }
        .merianSystemFeedback(
            toastMessage: Binding(
                get: { viewModel.toastMessage },
                set: { viewModel.toastMessage = $0 }
            ),
            toastAlignment: .top
        )
    }

    @ToolbarContentBuilder
    private var exploreToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
            }
        }

        if shouldShowDictionaryModePicker {
            ToolbarItem(placement: .principal) {
                Picker("Dictionary view", selection: $activeDictionaryMode) {
                    Text("Catalog").tag(ExploreDictionaryMode.dictionary)
                    Text("Tree").tag(ExploreDictionaryMode.tree)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 1)
                .background(Capsule().fill(.regularMaterial))
                .clipShape(Capsule())
                .frame(width: 220)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 0) {
                bellButton
            }
        }
    }

    @ViewBuilder
    private var dictionaryTabContent: some View {
        switch activeDictionaryMode {
        case .dictionary:
            VStack(spacing: 10) {
                if navigationPath.isEmpty {
                    ExploreDictionarySearchBar(text: $dictionarySearchText)
                        .padding(.top, 12)
                        .zIndex(1)
                }

                if isDictionarySearchActive {
                    SpeciesDictionaryCatalogView(
                        isSearchEnabled: false,
                        showsNavigationTitle: false,
                        searchText: $dictionarySearchText
                    )
                } else {
                    SpeciesDictionaryOverviewView(userRegion: dictionaryUserRegionIdentifier)
                }
            }
        case .tree:
            TaxonomyTreeCanvasView(showsNavigationTitle: false) { speciesRoute in
                navigationPath.append(speciesRoute)
            }
        }
    }

    private var shouldShowDictionaryModePicker: Bool {
        activeTab == .dictionary && navigationPath.isEmpty
    }

    private func openPostDetail(
        for post: ExplorePost,
        focusCommentComposer: Bool = false,
        openInsight: Bool = false,
        targetCommentId: String? = nil,
        targetReplyParentCommentId: String? = nil,
        notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget? = nil
    ) {
        viewModel.upsertPost(post)
        viewModel.refreshPreferredSpeciesNames(for: [post.speciesScientificName], modelContext: modelContext)
        navigationPath.append(ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: focusCommentComposer,
            shouldOpenInsight: allowsInsightPresentation && openInsight,
            targetCommentId: targetCommentId,
            targetReplyParentCommentId: targetReplyParentCommentId,
            notificationReplyThreadTarget: notificationReplyThreadTarget
        ))
    }

    private func openAuthorProfile(for post: ExplorePost) {
        HapticManager.shared.triggerSelectionPulse()
        viewModel.upsertPost(post)
        selectedAuthorProfileRoute = ExploreAuthorProfileRoute(post: post)
    }

    private func openHashtag(_ hashtag: String) {
        HapticManager.shared.triggerSelectionPulse()
        navigationPath.append(ExploreHashtagRoute(hashtag: hashtag))
    }

    private func selectExploreTab(_ tab: ExploreTab) {
        HapticManager.shared.triggerSelectionPulse()
        activeTab = tab
    }

    private func openInsight(for post: ExplorePost) {
        guard allowsInsightPresentation else { return }
        guard isOwnedByCurrentUser(post) else { return }

        let scanId = post.scanId
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )

        guard let record = try? modelContext.fetch(descriptor).first else {
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = "This scan is not available on this device."
            return
        }

        inferenceEngine.load(from: record)
        HapticManager.shared.triggerSelectionPulse()
        selectedInsightRoute = ScanInsightRoute(scanId: record.id)
    }

    private func isOwnedByCurrentUser(_ post: ExplorePost) -> Bool {
        let currentUserId = SupabaseManager.shared.currentUser?.id.uuidString
        return post.isOwnedByViewer || currentUserId == post.authorUserId
    }

    private func authorIdentityChangeAffects(
        _ authorUserId: String,
        previousUserId: String?,
        currentUserId: String
    ) -> Bool {
        let normalizedAuthorId = authorUserId.lowercased()
        return previousUserId == normalizedAuthorId || currentUserId == normalizedAuthorId
    }

    private var bellButton: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: { viewModel.presentNotifications() }) {
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            
            if viewModel.unreadNotificationCount > 0 {
                notificationUnreadDot
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(accessibilityNotificationLabel)
    }

    private var notificationUnreadDot: some View {
        Circle()
            .fill(Color(uiColor: .systemRed))
            .frame(width: 11, height: 11)
            .overlay(
                Circle()
                    .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
    }

    private var accessibilityNotificationLabel: String {
        if viewModel.unreadNotificationCount == 0 {
            return "Notifications"
        }
        return "Notifications, \(viewModel.unreadNotificationCount) unread"
    }

    private func openNotification(_ notification: ExploreNotification) async {
        guard let postId = notification.postId else { return }

        do {
            let post = try await viewModel.preparePostForNavigation(postId: postId)
            viewModel.dismissNotifications()
            let targetReplyParentCommentId = notification.parentCommentId
                ?? (notification.type == .commentReply ? notification.commentId : nil)
            let targetCommentId = targetReplyParentCommentId == notification.commentId
                ? nil
                : notification.commentId

            if notification.type == .commentReply,
               let targetReplyId = notification.commentId {
                openPostDetail(
                    for: post,
                    notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget(
                        parentCommentId: notification.parentCommentId,
                        targetReplyId: targetReplyId,
                        fallbackReply: ExploreNotificationReplyFallback(
                            commentId: targetReplyId,
                            body: notification.commentBody,
                            authorUserId: notification.triggeringUserId,
                            authorName: notification.triggeringUserName,
                            createdAt: notification.createdAt
                        )
                    )
                )
                return
            }

            if targetReplyParentCommentId != nil {
                viewModel.prepareToExpandReplyThread(parentCommentId: targetReplyParentCommentId)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            openPostDetail(
                for: post,
                focusCommentComposer: notification.type == .comment && targetCommentId == nil,
                targetCommentId: targetCommentId ?? targetReplyParentCommentId,
                targetReplyParentCommentId: targetReplyParentCommentId
            )
        } catch {
            MerianLog.network.error(
                "Failed to open Explore notification \(notification.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            AppTelemetry.trackExploreNotificationOpenFailed(type: notification.type.rawValue)
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private static func defaultDictionaryUserRegionIdentifier() -> String? {
        EnvironmentContextManager.normalizedRegionIdentifier(Locale.current.region?.identifier)
    }

    @MainActor
    private func refreshDictionaryUserRegionFromAuthorizedLocation() async {
        guard let regionIdentifier = await environmentContextManager.currentAuthorizedRegionIdentifier(),
              regionIdentifier != dictionaryUserRegionIdentifier else {
            return
        }

        dictionaryUserRegionIdentifier = regionIdentifier
    }
}

private struct ExploreFeedTabContent: View {
    @Bindable var viewModel: ExploreFeedViewModel
    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var isLocationSettingsAlertPresented = false
    @State private var isResolvingNearbyLocation = false
    @State private var editingPost: ExplorePost?
    @State private var editingPostDetail: ExplorePostDetail?
    @State private var editingPostLocalFieldNotes: String?
    @State private var isSavingEditedPost = false
    let onOpenPostDetail: (ExplorePost) -> Void
    let onOpenAuthorProfile: (ExplorePost) -> Void
    let onOpenHashtag: (String) -> Void
    let onOpenInsight: ((ExplorePost) -> Void)?

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            Group {
                if viewModel.isLoadingInitialFeed && viewModel.posts.isEmpty {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage, viewModel.posts.isEmpty {
                    errorState(message: errorMessage)
                } else if viewModel.posts.isEmpty {
                    emptyState
                } else {
                    feedScrollView
                }
            }
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
            Text("Nearby uses your current location to show discoveries shared within \(ExploreFeedFilter.nearbyRadiusMiles) miles.")
        }
        .sheet(item: $editingPost, onDismiss: clearPostEditor) { post in
            ExplorePostComposerView(
                mode: .edit,
                speciesName: postSnapshotCommonName(for: post),
                scientificName: post.speciesScientificName,
                heroImageUrl: post.heroImageUrl,
                publicLocationLabel: post.publicDisplayLocationLabel,
                commonNameOptions: commonNameOptions(for: post, detail: editingPostDetail),
                initialSelectedCommonName: postSnapshotCommonName(for: post),
                initialFieldNotes: editingPostDetail?.trimmedFieldNotes ?? editingPostLocalFieldNotes,
                initialFieldNotesArePublic: editingPostDetail?.trimmedFieldNotes != nil,
                initialHashtags: editingPostDetail?.hashtags ?? post.hashtags ?? [],
                initialLocationSharing: editingPostDetail?.locationSharing ?? post.locationSharing ?? .obscured,
                isSaving: isSavingEditedPost,
                onSubmit: { draft in
                    Task { await saveEditedPost(draft, for: post) }
                }
            )
        }
    }

    private var feedScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar
                
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.posts) { post in
                        ExplorePostCard(
                            post: post,
                            speciesDisplayName: viewModel.resolvedSpeciesCommonName(for: post),
                            mediaReloadGeneration: viewModel.mediaReloadGeneration,
                            onLike: { Task { await viewModel.toggleLike(for: post) } },
                            onComments: { Task { await viewModel.openCommentsSheet(for: post) } },
                            onShare: { viewModel.share(post) },
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
        }
        .refreshable {
            await refreshFeed()
        }
    }

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar
                
                LazyVStack(spacing: 24) {
                    ForEach(0..<3, id: \.self) { _ in
                        ExplorePostCard.Skeleton()
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar
                
                EmptyStateView(
                    imageName: "explore-base",
                    imageHeight: 300,
                    title: emptyStateTitle,
                    message: emptyStateMessage
                )
                .padding(.top, 60)
            }
        }
        .refreshable {
            await refreshFeed()
        }
    }

    private func errorState(message: String) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar
                
                EmptyStateView(
                    iconName: "exclamationmark.triangle",
                    title: "Couldn’t load posts",
                    message: message
                ) {
                    Button {
                        Task { await refreshFeed() }
                    } label: {
                        Text("Try again")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
            }
        }
        .refreshable {
            await refreshFeed()
        }
    }

    private var emptyStateTitle: String {
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
        switch viewModel.activeFilter {
        case .recent:
            return "Shared discoveries will show up here once people publish scans to Explore."
        case .following:
            return "Follow authors from their public profiles to build this feed."
        case .trending:
            return "Freshly liked discoveries will appear here as the community reacts."
        case .nearby:
            return "We couldn’t find shared discoveries within \(ExploreFeedFilter.nearbyRadiusMiles) miles of your current location."
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

        do {
            editingPostDetail = try await MerianNetworkClient.shared.getExplorePostDetail(postId: post.id)
        } catch {
            editingPostDetail = nil
            viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
            return
        }

        HapticManager.shared.triggerSelectionPulse()
        editingPost = post
    }

    @MainActor
    private func saveEditedPost(_ draft: ExplorePostComposerDraft, for post: ExplorePost) async {
        guard post.isOwnedByViewer, !isSavingEditedPost else { return }

        isSavingEditedPost = true
        defer { isSavingEditedPost = false }

        do {
            persistPreferredCommonName(draft.selectedCommonName, scientificName: post.speciesScientificName)
            let response = try await MerianNetworkClient.shared.updateExplorePostContent(
                postId: post.id,
                speciesCommonName: draft.selectedCommonName,
                fieldNotes: draft.publicFieldNotes,
                hashtags: draft.hashtags,
                locationSharing: draft.locationSharing
            )
            updateLocalFieldNotes(draft.fieldNotes ?? "", for: post)
            editingPostDetail?.fieldNotes = response.fieldNotes
            editingPostDetail?.locationSharing = response.locationSharing ?? draft.locationSharing
            editingPost = nil
            await viewModel.refreshPost(postId: post.id)
            viewModel.refreshPreferredSpeciesNames(for: [post.speciesScientificName], modelContext: modelContext)
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.toastMessage = "Explore post updated"
            }
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
            }
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
        editingPostDetail = nil
        editingPostLocalFieldNotes = nil
    }

    private func postSnapshotCommonName(for post: ExplorePost) -> String {
        let trimmed = post.speciesCommonName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? viewModel.resolvedSpeciesCommonName(for: post) : trimmed
    }

    private func commonNameOptions(for post: ExplorePost, detail: ExplorePostDetail?) -> [String] {
        ([postSnapshotCommonName(for: post)] + (detail?.alternativeCommonNames ?? []))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removingFuzzyDuplicateNames()
    }

    private func persistPreferredCommonName(_ name: String, scientificName: String) {
        _ = SpeciesPreferredNameRepository.setPreferredName(
            name,
            for: scientificName,
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
            viewModel.toastMessage = "Location access is restricted on this device."
        default:
            viewModel.toastMessage = "We couldn’t determine your location right now. Try again in a moment."
        }
    }

    private var filterBar: some View {
        CategoryFilterBar(
            items: ExploreFeedFilter.allCases,
            activeItem: viewModel.activeFilter,
            title: { $0.title },
            onSelection: { filter in
                Task {
                    await selectFilter(filter)
                }
            }
        )
        .disabled(isResolvingNearbyLocation)
        .overlay(alignment: .trailing) {
            if isResolvingNearbyLocation {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.85)
                    .padding(.trailing, 16)
            }
        }
    }
}

struct ExplorePostRoute: Hashable {
    let postId: String
    let shouldFocusCommentComposer: Bool
    let shouldOpenInsight: Bool
    let targetCommentId: String?
    let targetReplyParentCommentId: String?
    let notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget?

    init(
        postId: String,
        shouldFocusCommentComposer: Bool,
        shouldOpenInsight: Bool,
        targetCommentId: String?,
        targetReplyParentCommentId: String?,
        notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget? = nil
    ) {
        self.postId = postId
        self.shouldFocusCommentComposer = shouldFocusCommentComposer
        self.shouldOpenInsight = shouldOpenInsight
        self.targetCommentId = targetCommentId
        self.targetReplyParentCommentId = targetReplyParentCommentId
        self.notificationReplyThreadTarget = notificationReplyThreadTarget
    }
}

struct ExploreNotificationReplyThreadTarget: Hashable {
    let parentCommentId: String?
    let targetReplyId: String
    let fallbackReply: ExploreNotificationReplyFallback
}

struct ExploreHashtagRoute: Hashable {
    let hashtag: String
}

struct ExploreHashtagPostsView: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let route: ExploreHashtagRoute
    let allowsInsightPresentation: Bool
    var allowsAuthorProfilePresentation = true

    @Environment(\.modelContext) private var modelContext

    @State private var posts: [ExplorePost] = []
    @State private var cursor = ExploreHashtagPostCursor.empty
    @State private var isLoadingInitialPage = true
    @State private var isLoadingMore = false
    @State private var hasReachedEnd = false
    @State private var errorMessage: String?
    @State private var selectedPostRoute: ExplorePostRoute?

    private let pageSize = 30

    var body: some View {
        Group {
            if isLoadingInitialPage && posts.isEmpty {
                loadingState
            } else if let errorMessage, posts.isEmpty {
                errorState(message: errorMessage)
            } else if posts.isEmpty {
                emptyState
            } else {
                postsGrid
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("#\(route.hashtag)")
        .navigationDestination(
            isPresented: Binding(
                get: { selectedPostRoute != nil },
                set: { if !$0 { selectedPostRoute = nil } }
            )
        ) {
            if let selectedPostRoute {
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: selectedPostRoute.postId,
                    shouldFocusCommentComposer: selectedPostRoute.shouldFocusCommentComposer,
                    shouldOpenInsight: selectedPostRoute.shouldOpenInsight,
                    targetCommentId: selectedPostRoute.targetCommentId,
                    targetReplyParentCommentId: selectedPostRoute.targetReplyParentCommentId,
                    allowsInsightPresentation: allowsInsightPresentation,
                    allowsAuthorProfilePresentation: allowsAuthorProfilePresentation
                )
            }
        }
        .task(id: route.hashtag) {
            await reloadPosts()
        }
    }

    private var postsGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                spacing: 2
            ) {
                ForEach(posts) { post in
                    Button {
                        openPost(post)
                    } label: {
                        ExploreHeroImageView(
                            imageUrl: post.heroImageUrl,
                            reloadGeneration: viewModel.mediaReloadGeneration,
                            maxDimension: 360
                        )
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(viewModel.resolvedSpeciesCommonName(for: post)), tagged #\(route.hashtag)")
                    .onAppear {
                        guard post.id == posts.last?.id else { return }
                        Task { await loadMorePostsIfNeeded() }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)

            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
        }
        .refreshable {
            await reloadPosts()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading tagged posts...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            iconName: "number",
            title: "No tagged posts",
            message: "Visible Explore posts tagged #\(route.hashtag) will appear here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        EmptyStateView(
            iconName: "exclamationmark.triangle",
            title: "Couldn’t load hashtag",
            message: message
        ) {
            Button {
                Task { await reloadPosts() }
            } label: {
                Text("Try again")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func reloadPosts() async {
        posts = []
        cursor = .empty
        hasReachedEnd = false
        errorMessage = nil
        isLoadingInitialPage = true
        await loadMorePostsIfNeeded()
        isLoadingInitialPage = false
    }

    @MainActor
    private func loadMorePostsIfNeeded() async {
        guard !isLoadingMore, !hasReachedEnd else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await MerianNetworkClient.shared.getExploreHashtagPosts(
                hashtag: route.hashtag,
                limit: pageSize,
                cursor: cursor.isEmpty ? nil : cursor
            )
            guard !Task.isCancelled else { return }

            appendUniquePosts(page)
            registerPosts(page)

            if let lastPost = posts.last {
                cursor = ExploreHashtagPostCursor(
                    beforeSharedAt: lastPost.sharedAt,
                    beforePostId: lastPost.id
                )
            }

            hasReachedEnd = page.count < pageSize
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if posts.isEmpty {
                errorMessage = ExploreErrorFormatter.message(for: error)
            } else {
                viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

    @MainActor
    private func appendUniquePosts(_ nextPosts: [ExplorePost]) {
        let existingIds = Set(posts.map(\.id))
        posts.append(contentsOf: nextPosts.filter { !existingIds.contains($0.id) })
    }

    @MainActor
    private func registerPosts(_ page: [ExplorePost]) {
        for post in page {
            viewModel.upsertPost(post)
        }
        viewModel.refreshPreferredSpeciesNames(
            for: page.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }

    @MainActor
    private func openPost(_ post: ExplorePost) {
        viewModel.upsertPost(post)
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil
        )
    }
}
