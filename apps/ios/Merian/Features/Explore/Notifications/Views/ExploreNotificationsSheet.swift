import SwiftUI

struct ExploreNotificationsSheet: View {
    let onUnreadNotificationsCleared: () -> Void
    let onOpenNotification: (ExploreNotification) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreNotificationsViewModel()
    @State private var selectedNotificationId: String?
    @State private var isNotificationSettingsPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage,
                          viewModel.notifications.isEmpty {
                    errorState(message: errorMessage)
                } else if viewModel.notifications.isEmpty {
                    emptyState
                } else {
                    notificationsScrollView
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isNotificationSettingsPresented) {
                NotificationSettingsView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    notificationsMenu
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemBackground))
        .task {
            await fetchNotifications()
        }
    }

    private var notificationsMenu: some View {
        Menu {
            if !viewModel.notifications.isEmpty {
                Button {
                    Task { await viewModel.markAllAsRead() }
                } label: {
                    Label("Mark all as read", systemImage: "checkmark.circle")
                }

                Divider()
            }

            Button {
                isNotificationSettingsPresented = true
            } label: {
                Label("Notification settings", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
        }
        .tint(.primary)
    }

    private var notificationsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(viewModel.notifications) { notification in
                    NotificationRowView(
                        notification: notification,
                        isRecentlyRead: viewModel.recentlyReadNotificationIds.contains(notification.id),
                        isLoading: selectedNotificationId == notification.id,
                        action: {
                            Task { await openNotification(notification) }
                        }
                    )
                    .onAppear {
                        Task { await viewModel.loadMoreIfNeeded(currentNotification: notification) }
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .refreshable {
            await fetchNotifications(force: true)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading notifications...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            imageName: "bell",
            imageHeight: 200,
            title: "Nothing new yet",
            message: "Follows, likes on your posts, comments on your posts, and reactions to your comments will show up here."
        )
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Notifications unavailable",
            message: message
        ) {
            Task { await fetchNotifications(force: true) }
        }
    }

    private func fetchNotifications(force: Bool = false) async {
        let didClearUnread = await viewModel.fetchNotifications(force: force)
        if didClearUnread {
            onUnreadNotificationsCleared()
        }
    }

    private func openNotification(_ notification: ExploreNotification) async {
        guard notification.postId != nil ||
            notification.communityRequestId != nil ||
            notification.fieldTripPublicationId != nil else {
            return
        }
        guard selectedNotificationId == nil else { return }

        selectedNotificationId = notification.id
        defer { selectedNotificationId = nil }
        await onOpenNotification(notification)
    }
}
