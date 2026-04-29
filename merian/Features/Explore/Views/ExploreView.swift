import SwiftUI
import UIKit

enum ExploreTab: Hashable {
    case feed
    case map
}

struct ExploreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreFeedViewModel()
    @State private var mapViewModel = ExploreMapViewModel()
    @State private var selectedPostRoute: ExplorePostRoute?
    @State private var activeTab: ExploreTab = .feed

    private var tabSelectionBinding: Binding<ExploreTab?> {
        Binding(
            get: { activeTab },
            set: { if let value = $0 { activeTab = value } }
        )
    }

    init(initialPostId: String? = nil) {
        if let postId = initialPostId {
            _selectedPostRoute = State(initialValue: ExplorePostRoute(postId: postId, shouldFocusCommentComposer: false))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ExploreFeedTabContent(
                        viewModel: viewModel,
                        onOpenPostDetail: { openPostDetail(for: $0) }
                    )
                    .id(ExploreTab.feed)

                    ExploreMapView(
                        viewModel: mapViewModel,
                        feedViewModel: viewModel,
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
            .background(Color(uiColor: .systemBackground))
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
                        shouldFocusCommentComposer: selectedPostRoute.shouldFocusCommentComposer
                    )
                }
            }
            .toolbar { exploreToolbar }
        }
        .task {
            await viewModel.loadInitialFeed()
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

    private func openPostDetail(for post: ExplorePost, focusCommentComposer: Bool = false) {
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: focusCommentComposer
        )
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
                    .offset(x: 4, y: -4)
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
    let onOpenPostDetail: (ExplorePost) -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
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
        .containerRelativeFrame(.horizontal)
    }

    private var feedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(viewModel.posts) { post in
                    ExplorePostCard(
                        post: post,
                        mediaReloadGeneration: viewModel.mediaReloadGeneration,
                        onLike: { Task { await viewModel.toggleLike(for: post) } },
                        onComments: { Task { await viewModel.openCommentsSheet(for: post) } },
                        onShare: { viewModel.share(post) },
                        onOpenDetail: { onOpenPostDetail(post) },
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
        .refreshable {
            await viewModel.loadInitialFeed(force: true)
        }
    }

    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(0..<3, id: \.self) { _ in
                    ExplorePostCard.Skeleton()
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            imageName: "explore-base",
            imageHeight: 300,
            title: "Nothing shared yet",
            message: "Shared discoveries will show up here once people publish scans to Explore."
        )
    }

    private func errorState(message: String) -> some View {
        EmptyStateView(
            iconName: "exclamationmark.triangle",
            title: "Couldn’t load posts",
            message: message
        ) {
            Button {
                Task { await viewModel.loadInitialFeed(force: true) }
            } label: {
                Text("Try again")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct ExplorePostRoute: Equatable {
    let postId: String
    let shouldFocusCommentComposer: Bool
}
