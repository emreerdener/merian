import SwiftUI

struct ExploreCommunityIdentificationView: View {
    @Environment(EnvironmentContextManager.self) private var environmentContextManager

    let onOpenRequest: (ExploreCommunityRequestRoute) -> Void
    let onOpenRequestsFeed: (ExploreCommunityRequestsFeedRoute) -> Void
    let onOpenActivityFeed: (ExploreCommunityActivityFeedRoute) -> Void

    @State private var viewModel = IdentifyDashboardViewModel()
    @AppStorage(UserDefaultsKeys.hasDismissedIdentifyRequestsBanner) private var hasDismissedRequestsBanner = false
    @State private var isFeedbackPresented = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(
        onOpenRequest: @escaping (ExploreCommunityRequestRoute) -> Void,
        onOpenRequestsFeed: @escaping (ExploreCommunityRequestsFeedRoute) -> Void,
        onOpenActivityFeed: @escaping (ExploreCommunityActivityFeedRoute) -> Void
    ) {
        self.onOpenRequest = onOpenRequest
        self.onOpenRequestsFeed = onOpenRequestsFeed
        self.onOpenActivityFeed = onOpenActivityFeed
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    CommunityIdentificationFilterBar(filter: $viewModel.filter)
                    requestSection
                    activitySection
                    feedbackFooterSection
                }
                .padding(.bottom, 18)
            }
            .refreshable {
                await reloadDashboard(clearExisting: false)
            }
        }
        .navigationTitle("Identify")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel.requestItems.isEmpty, viewModel.activityItems.isEmpty else { return }
            await reloadDashboard(clearExisting: false)
        }
        .onChange(of: viewModel.filter) { _, _ in
            Task { await reloadDashboard(clearExisting: true) }
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            guard case let .communityIdentificationRequestChanged(requestId) = event else { return }
            guard viewModel.contains(requestId: requestId) else { return }
            Task { await reloadDashboard(clearExisting: false) }
        }
        .sheet(isPresented: $isFeedbackPresented) {
            CommunityFeedbackSheet()
        }
    }

    @ViewBuilder
    private var communityBanner: some View {
        if !hasDismissedRequestsBanner {
            CommunityIdentificationBanner(
                title: "Ask the community",
                description: "Help identify open requests from Naturebook explorers.",
                onDismiss: {
                    withAnimation(.snappy(duration: 0.2)) {
                        hasDismissedRequestsBanner = true
                    }
                }
            )
            .padding(.horizontal, 16)
        }
    }

    private var requestSection: some View {
        VStack(spacing: 12) {
            sectionHeader(
                title: "Identify requests",
                isLoading: viewModel.loadState.isLoadingRequests && !viewModel.requestItems.isEmpty,
                actionTitle: "See all requests"
            ) {
                onOpenRequestsFeed(ExploreCommunityRequestsFeedRoute(filter: viewModel.filter))
            }

            communityBanner

            Group {
                if viewModel.loadState.isLoadingRequests, viewModel.requestItems.isEmpty {
                    requestLoadingState
                } else if let requestErrorMessage = viewModel.loadState.requestErrorMessage,
                          viewModel.requestItems.isEmpty {
                    sectionErrorState(message: requestErrorMessage) {
                        Task { await reloadRequestsOnly() }
                    }
                } else if viewModel.requestItems.isEmpty {
                    requestEmptyState
                } else {
                    requestGrid
                }
            }

            if let requestErrorMessage = viewModel.loadState.requestErrorMessage,
               !viewModel.requestItems.isEmpty {
                sectionErrorState(message: requestErrorMessage) {
                    Task { await reloadRequestsOnly() }
                }
            }
        }
        .padding(.top, 18)
    }

    private var activitySection: some View {
        VStack(spacing: 12) {
            sectionHeader(
                title: "Recent activity",
                isLoading: viewModel.loadState.isLoadingActivity && !viewModel.activityItems.isEmpty,
                actionTitle: "See all activity"
            ) {
                onOpenActivityFeed(ExploreCommunityActivityFeedRoute(filter: viewModel.filter))
            }

            Group {
                if viewModel.loadState.isLoadingActivity, viewModel.activityItems.isEmpty {
                    IdentifyActivityLoadingState(count: 4)
                } else if let activityErrorMessage = viewModel.loadState.activityErrorMessage,
                          viewModel.activityItems.isEmpty {
                    sectionErrorState(message: activityErrorMessage) {
                        Task { await reloadActivityOnly() }
                    }
                } else if viewModel.activityItems.isEmpty {
                    activityEmptyState
                } else {
                    activityList
                }
            }

            if let activityErrorMessage = viewModel.loadState.activityErrorMessage,
               !viewModel.activityItems.isEmpty {
                sectionErrorState(message: activityErrorMessage) {
                    Task { await reloadActivityOnly() }
                }
            }
        }
        .padding(.top, 38)
    }

    private func sectionHeader(
        title: String,
        isLoading: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button(actionTitle, action: action)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
    }

    private var requestGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(viewModel.requestItems) { item in
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onOpenRequest(ExploreCommunityRequestRoute(requestId: item.requestId))
                } label: {
                    CommunityIdentificationGridCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var requestLoadingState: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in
                CommunityIdentificationGridCardSkeleton()
            }
        }
        .padding(.horizontal, 16)
        .accessibilityLabel("Loading community requests")
    }

    private var requestEmptyState: some View {
        CommunityIdentificationCompactEmptyState(
            title: viewModel.filter.emptyRequestTitle,
            message: requestEmptyStateDescription,
            systemImage: "person.2"
        )
    }

    private var requestEmptyStateDescription: String {
        switch viewModel.filter {
        case .mine:
            "Ask the community from an insight when you want help identifying an observation."
        case .all:
            "Identification requests will appear here when explorers ask for help."
        default:
            "Matching identification requests will appear here."
        }
    }

    private var activityEmptyState: some View {
        CommunityIdentificationCompactEmptyState(
            title: "No recent activity",
            message: "Suggestions, consensus changes, and resolved requests will appear here.",
            systemImage: "clock.badge.checkmark"
        )
    }

    private var activityList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.activityItems.enumerated()), id: \.element.id) { index, item in
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onOpenRequest(ExploreCommunityRequestRoute(requestId: item.requestId))
                } label: {
                    CommunityIdentificationActivityRow(item: item)
                }
                .buttonStyle(.plain)

                if index < viewModel.activityItems.count - 1 {
                    Divider()
                        .padding(.leading, 92)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func sectionErrorState(
        message: String,
        retry: @escaping () -> Void
    ) -> some View {
        CommunityIdentificationSectionErrorView(message: message, retry: retry)
            .padding(.horizontal, 12)
    }

    private var feedbackFooterSection: some View {
        Button {
            HapticManager.shared.triggerSelectionPulse()
            isFeedbackPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                Text("Give feedback")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 99, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.24), lineWidth: 1.5)
                    .background(
                        Color.accentColor.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private func reloadDashboard(clearExisting: Bool) async {
        await viewModel.reload(
            filter: viewModel.filter,
            latitude: communitySortLatitude,
            longitude: communitySortLongitude,
            clearExisting: clearExisting
        )
    }

    private func reloadRequestsOnly() async {
        await viewModel.reloadRequests(
            filter: viewModel.filter,
            latitude: communitySortLatitude,
            longitude: communitySortLongitude
        )
    }

    private func reloadActivityOnly() async {
        await viewModel.reloadActivity(filter: viewModel.filter)
    }

    private var communitySortLatitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.latitude
    }

    private var communitySortLongitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.longitude
    }
}
