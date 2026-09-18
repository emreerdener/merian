import SwiftUI

struct ExploreNotificationReplyThreadSheet: View {
    let route: ExploreNotificationReplyThreadRoute

    @Environment(\.dismiss) private var dismiss
    @State private var replyViewModel: ExploreNotificationReplyThreadViewModel

    init(
        viewModel: ExploreFeedViewModel,
        route: ExploreNotificationReplyThreadRoute
    ) {
        self.route = route
        _replyViewModel = State(initialValue: ExploreNotificationReplyThreadViewModel(
            onToggleReaction: { comment, emoji, selected in
                try await viewModel.performCommentReaction(for: comment, emoji: emoji, selected: selected)
            },
            loadReactions: { try await viewModel.loadMoreCommentReactions(for: $0) }
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if replyViewModel.isLoading {
                    loadingState
                } else if let errorMessage = replyViewModel.errorMessage {
                    errorState(message: errorMessage)
                } else if replyViewModel.parentComment != nil ||
                            !replyViewModel.replies.isEmpty {
                    ExploreNotificationReplyThreadContent(
                        viewModel: replyViewModel,
                        route: route
                    )
                } else {
                    errorState(message: "This reply is no longer available.")
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Comment replies")
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
        .alert("Reactions", isPresented: Binding(get: { replyViewModel.reactionError != nil }, set: { if !$0 { replyViewModel.reactionError = nil } })) {
            Button("OK") { replyViewModel.reactionError = nil }
        } message: { Text(replyViewModel.reactionError ?? "") }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .task(id: route.id) {
            await replyViewModel.load(route: route)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading reply...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Reply unavailable",
            message: message
        ) {
            Task { await replyViewModel.load(route: route) }
        }
    }
}
