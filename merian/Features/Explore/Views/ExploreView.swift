import SwiftUI

struct ExploreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreFeedViewModel()

    var body: some View {
        NavigationStack {
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
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.showNotificationsPlaceholder() }) {
                        Image(systemName: "bell")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .accessibilityLabel("Notifications")
                }
            }
        }
        .task {
            await viewModel.loadInitialFeed()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.activeCommentsPostId != nil },
                set: { if !$0 { viewModel.dismissComments() } }
            )
        ) {
            if let post = viewModel.activeCommentsPost {
                ExploreCommentsSheet(viewModel: viewModel, post: post)
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

    private var feedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(viewModel.posts) { post in
                    ExplorePostCard(
                        post: post,
                        onLike: { Task { await viewModel.toggleLike(for: post) } },
                        onComments: { Task { await viewModel.openComments(for: post) } },
                        onShare: { viewModel.share(post) },
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
