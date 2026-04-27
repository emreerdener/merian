import SwiftUI

struct ExploreNotificationsSheet: View {
    let onUnreadNotificationsCleared: () -> Void
    let onOpenNotification: (ExploreNotification) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreNotificationsViewModel()
    @State private var selectedNotificationId: String?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage, viewModel.notifications.isEmpty {
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .refreshable {
            await fetchNotifications()
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
            iconName: "bell.slash",
            title: "Nothing new yet",
            message: "Likes and comments on your Explore posts will show up here."
        )
    }

    private func errorState(message: String) -> some View {
        EmptyStateView(
            iconName: "exclamationmark.triangle",
            title: "Couldn’t load notifications",
            message: message
        ) {
            Button {
                Task { await fetchNotifications() }
            } label: {
                Text("Try again")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func fetchNotifications() async {
        let didClearUnread = await viewModel.fetchNotifications()
        if didClearUnread {
            onUnreadNotificationsCleared()
        }
    }

    private func openNotification(_ notification: ExploreNotification) async {
        guard selectedNotificationId == nil else { return }

        selectedNotificationId = notification.id
        defer { selectedNotificationId = nil }
        await onOpenNotification(notification)
    }
}
