import SwiftData
import SwiftUI
import UIKit

enum ExploreTab: Hashable {
    case feed
    case map
}

struct ExploreView: View {
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreFeedViewModel()
    @State private var mapViewModel = ExploreMapViewModel()
    @State private var selectedPostRoute: ExplorePostRoute?
    @State private var selectedInsightRecord: LocalScanRecord?
    @State private var activeTab: ExploreTab = .feed

    private var tabSelectionBinding: Binding<ExploreTab?> {
        Binding(
            get: { activeTab },
            set: { if let value = $0 { activeTab = value } }
        )
    }

    init(initialPostId: String? = nil) {
        if let postId = initialPostId {
            _selectedPostRoute = State(initialValue: ExplorePostRoute(postId: postId, shouldFocusCommentComposer: false, shouldOpenInsight: false))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ExploreFeedTabContent(
                        viewModel: viewModel,
                        onOpenPostDetail: { openPostDetail(for: $0) },
                        onOpenInsight: { openInsight(for: $0) }
                    )
                    .id(ExploreTab.feed)

                    ExploreMapView(
                        viewModel: mapViewModel,
                        feedViewModel: viewModel,
                        postStore: viewModel.store,
                        onOpenDetail: { post, focusCommentComposer in
                            openPostDetail(for: post, focusCommentComposer: focusCommentComposer)
                        }
                    )
                        .id(ExploreTab.map)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: tabSelectionBinding)
            .scrollDisabled(activeTab == .map)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
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
                        shouldOpenInsight: selectedPostRoute.shouldOpenInsight
                    )
                }
            }
            .toolbar { exploreToolbar }
        }
        .task {
            await viewModel.loadInitialFeed()
        }
        .onChange(of: activeTab) { _, newValue in
            if newValue == .map {
                AppTelemetry.trackExploreMapOpened()
            }
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
                },
                onOpenNotification: { notification in
                    await openNotification(notification)
                }
            )
        }
        .sheet(item: $selectedInsightRecord) { record in
            InsightSheetView(
                isPresented: Binding(
                    get: { selectedInsightRecord != nil },
                    set: { if !$0 { selectedInsightRecord = nil } }
                ),
                initialRecord: record,
                inferenceEngine: inferenceEngine,
                allowsExplorePresentation: false
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.refreshUnreadNotificationCount() }
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

        ToolbarItem(placement: .principal) {
            Picker("View", selection: $activeTab) {
                Text("Feed").tag(ExploreTab.feed)
                Text("Map").tag(ExploreTab.map)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 1)
            .background(Capsule().fill(.regularMaterial))
            .clipShape(Capsule())
            .frame(width: 180)
        }

        ToolbarItem(placement: .topBarTrailing) {
            bellButton
        }
    }

    private func openPostDetail(for post: ExplorePost, focusCommentComposer: Bool = false, openInsight: Bool = false) {
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: focusCommentComposer,
            shouldOpenInsight: openInsight
        )
    }

    private func openInsight(for post: ExplorePost) {
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
        selectedInsightRecord = record
    }

    private func isOwnedByCurrentUser(_ post: ExplorePost) -> Bool {
        let currentUserId = SupabaseManager.shared.currentUser?.id.uuidString
        return post.isOwnedByViewer || currentUserId == post.authorUserId
    }

    private var bellButton: some View {
        Button(action: { viewModel.presentNotifications() }) {
            Image(systemName: "bell")
                .font(.system(size: 16, weight: .bold))
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.unreadNotificationCount > 0 {
                Text(badgeText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, viewModel.unreadNotificationCount > 9 ? 5 : 0)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.red)
                    )
            }
        }
        .accessibilityLabel(accessibilityNotificationLabel)
    }

    private var badgeText: String {
        if viewModel.unreadNotificationCount > 99 {
            return "99+"
        }
        return "\(viewModel.unreadNotificationCount)"
    }

    private var accessibilityNotificationLabel: String {
        if viewModel.unreadNotificationCount == 0 {
            return "Notifications"
        }
        return "Notifications, \(viewModel.unreadNotificationCount) unread"
    }

    private func openNotification(_ notification: ExploreNotification) async {
        do {
            let post = try await viewModel.preparePostForNavigation(postId: notification.postId)
            viewModel.dismissNotifications()
            try? await Task.sleep(nanoseconds: 150_000_000)
            openPostDetail(for: post, focusCommentComposer: notification.type == .comment)
        } catch {
            MerianLog.network.error(
                "Failed to open Explore notification \(notification.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            AppTelemetry.trackExploreNotificationOpenFailed(type: notification.type.rawValue)
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }
}

private struct ExploreFeedTabContent: View {
    @Bindable var viewModel: ExploreFeedViewModel
    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(\.openURL) private var openURL
    @State private var isLocationSettingsAlertPresented = false
    @State private var isResolvingNearbyLocation = false
    let onOpenPostDetail: (ExplorePost) -> Void
    let onOpenInsight: (ExplorePost) -> Void

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
        .containerRelativeFrame(.horizontal)
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
    }

    private var feedScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterBar
                
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.posts) { post in
                        ExplorePostCard(
                            post: post,
                            mediaReloadGeneration: viewModel.mediaReloadGeneration,
                            onLike: { Task { await viewModel.toggleLike(for: post) } },
                            onComments: { Task { await viewModel.openCommentsSheet(for: post) } },
                            onShare: { viewModel.share(post) },
                            onOpenDetail: { onOpenPostDetail(post) },
                            onOpenInsight: { onOpenInsight(post) },
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

struct ExplorePostRoute: Equatable {
    let postId: String
    let shouldFocusCommentComposer: Bool
    let shouldOpenInsight: Bool
}
