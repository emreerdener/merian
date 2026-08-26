import SwiftUI

struct ExploreCommunityActivityFeedView: View {
    let onOpenRequest: (ExploreCommunityRequestRoute) -> Void

    @State private var viewModel: IdentifyActivityFeedViewModel

    init(
        initialFilter: CommunityIdentificationRequestFilter,
        onOpenRequest: @escaping (ExploreCommunityRequestRoute) -> Void
    ) {
        _viewModel = State(
            initialValue: IdentifyActivityFeedViewModel(
                initialFilter: initialFilter
            )
        )
        self.onOpenRequest = onOpenRequest
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    CommunityIdentificationFilterBar(filter: $viewModel.filter)

                    Group {
                        if viewModel.isLoadingInitialPage, viewModel.items.isEmpty {
                            IdentifyActivityLoadingState(count: 8)
                        } else if let errorMessage = viewModel.errorMessage,
                                  viewModel.items.isEmpty {
                            errorState(message: errorMessage)
                        } else if viewModel.items.isEmpty {
                            emptyState
                        } else {
                            activityList
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .padding(.vertical, 18)
                    } else if let errorMessage = viewModel.errorMessage,
                              !viewModel.items.isEmpty {
                        CommunityIdentificationSectionErrorView(
                            message: errorMessage,
                            retry: { Task { await viewModel.loadMore() } }
                        )
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable {
                await viewModel.reload()
            }
        }
        .navigationTitle("Identify activity")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel.items.isEmpty else { return }
            await viewModel.reload()
        }
        .onChange(of: viewModel.filter) { _, _ in
            Task { await viewModel.reload() }
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            guard case .communityIdentificationRequestChanged = event else { return }
            Task { await viewModel.reload() }
        }
    }

    private var activityList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onOpenRequest(ExploreCommunityRequestRoute(requestId: item.requestId))
                } label: {
                    CommunityIdentificationActivityRow(item: item)
                }
                .buttonStyle(.plain)
                .onAppear {
                    guard viewModel.shouldLoadMore(after: item) else { return }
                    Task { await viewModel.loadMore() }
                }

                if index < viewModel.items.count - 1 {
                    Divider()
                        .padding(.leading, 92)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var emptyState: some View {
        CommunityIdentificationCompactEmptyState(
            title: "No activity yet",
            message: "Suggestions, consensus changes, and resolved requests will appear here.",
            systemImage: "clock.badge.checkmark"
        )
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Activity unavailable",
            message: message
        ) {
            Task { await viewModel.reload() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 36)
    }
}
