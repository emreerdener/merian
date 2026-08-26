import SwiftUI

struct ExploreCommunityRequestsFeedView: View {
    @Environment(EnvironmentContextManager.self) private var environmentContextManager

    let onOpenRequest: (ExploreCommunityRequestRoute) -> Void

    @State private var viewModel: IdentifyRequestsFeedViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(
        initialFilter: CommunityIdentificationRequestFilter,
        onOpenRequest: @escaping (ExploreCommunityRequestRoute) -> Void
    ) {
        _viewModel = State(
            initialValue: IdentifyRequestsFeedViewModel(
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
                            loadingState
                        } else if let errorMessage = viewModel.errorMessage,
                                  viewModel.items.isEmpty {
                            errorState(message: errorMessage)
                        } else if viewModel.items.isEmpty {
                            emptyState
                        } else {
                            requestGrid
                        }
                    }

                    if let errorMessage = viewModel.errorMessage,
                       !viewModel.items.isEmpty {
                        CommunityIdentificationSectionErrorView(
                            message: errorMessage,
                            retry: { Task { await loadMore() } }
                        )
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable {
                await reload()
            }
        }
        .navigationTitle("Identify requests")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel.items.isEmpty else { return }
            await reload()
        }
        .onChange(of: viewModel.filter) { _, _ in
            Task { await reload() }
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            guard case let .communityIdentificationRequestChanged(requestId) = event else { return }
            guard viewModel.items.contains(where: { $0.requestId == requestId }) else { return }
            Task { await reload() }
        }
    }

    private var requestGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(viewModel.items) { item in
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onOpenRequest(ExploreCommunityRequestRoute(requestId: item.requestId))
                } label: {
                    CommunityIdentificationGridCard(item: item)
                }
                .buttonStyle(.plain)
                .onAppear {
                    guard viewModel.shouldLoadMore(after: item) else { return }
                    Task { await loadMore() }
                }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .gridCellColumns(2)
                    .padding(.vertical, 18)
            }
        }
        .padding(.horizontal, 16)
    }

    private var loadingState: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                CommunityIdentificationGridCardSkeleton()
            }
        }
        .padding(.horizontal, 16)
        .accessibilityLabel("Loading community requests")
    }

    private var emptyState: some View {
        CommunityIdentificationCompactEmptyState(
            title: viewModel.filter.emptyRequestTitle,
            message: viewModel.filter == .mine
                ? "Ask the community from an insight when you want help identifying an observation."
                : "Matching identification requests will appear here.",
            systemImage: "person.2"
        )
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Requests unavailable",
            message: message
        ) {
            Task { await reload() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 36)
    }

    private func reload() async {
        await viewModel.reload(
            latitude: communitySortLatitude,
            longitude: communitySortLongitude
        )
    }

    private func loadMore() async {
        await viewModel.loadMore(
            latitude: communitySortLatitude,
            longitude: communitySortLongitude
        )
    }

    private var communitySortLatitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.latitude
    }

    private var communitySortLongitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.longitude
    }
}
