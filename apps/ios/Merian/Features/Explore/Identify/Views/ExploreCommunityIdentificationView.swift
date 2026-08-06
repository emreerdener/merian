import SwiftUI

struct ExploreCommunityRequestRoute: Hashable {
    let requestId: String
}

struct ExploreCommunityRequestsFeedRoute: Hashable {
    let filter: CommunityIdentificationRequestFilter
}

struct ExploreCommunityActivityFeedRoute: Hashable {
    let filter: CommunityIdentificationRequestFilter
}

enum ExploreIdentifyMode: Hashable, CaseIterable {
    case requests
    case index

    var title: String {
        switch self {
        case .requests:
            "Requests"
        case .index:
            "Index"
        }
    }
}

enum CommunityIdentificationRequestFilter: Hashable, CaseIterable {
    case all
    case mine
    case plants
    case birds
    case insects
    case fungi
    case mammals
    case reptilesAmphibians

    var title: String {
        switch self {
        case .all:
            "All"
        case .mine:
            "Yours"
        case .plants:
            CommunityIdentificationRequestGroup.plants.title
        case .birds:
            CommunityIdentificationRequestGroup.birds.title
        case .insects:
            CommunityIdentificationRequestGroup.insects.title
        case .fungi:
            CommunityIdentificationRequestGroup.fungi.title
        case .mammals:
            CommunityIdentificationRequestGroup.mammals.title
        case .reptilesAmphibians:
            CommunityIdentificationRequestGroup.reptilesAmphibians.title
        }
    }

    var scope: CommunityIdentificationFeedScope {
        switch self {
        case .mine:
            .mine
        default:
            .all
        }
    }

    var group: CommunityIdentificationRequestGroup {
        switch self {
        case .all, .mine:
            .all
        case .plants:
            .plants
        case .birds:
            .birds
        case .insects:
            .insects
        case .fungi:
            .fungi
        case .mammals:
            .mammals
        case .reptilesAmphibians:
            .reptilesAmphibians
        }
    }

    var emptyRequestTitle: String {
        switch self {
        case .all:
            "No requests yet"
        case .mine:
            "No requests from you yet"
        case .plants:
            "No plant requests yet"
        case .birds:
            "No bird requests yet"
        case .insects:
            "No insect requests yet"
        case .fungi:
            "No fungus requests yet"
        case .mammals:
            "No mammal requests yet"
        case .reptilesAmphibians:
            "No herp requests yet"
        }
    }
}

enum CommunityIdentificationDashboardPolicy {
    static let requestPreviewLimit = 12
    static let activityPreviewLimit = 10
    static let fullPageSize = 30
}

enum CommunityIdentificationDashboardSection {
    case requests
    case activity
}

struct IdentifyDashboardLoadState: Equatable {
    private(set) var isLoadingRequests = true
    private(set) var isLoadingActivity = true
    private(set) var requestErrorMessage: String?
    private(set) var activityErrorMessage: String?

    mutating func begin(_ section: CommunityIdentificationDashboardSection) {
        switch section {
        case .requests:
            isLoadingRequests = true
            requestErrorMessage = nil
        case .activity:
            isLoadingActivity = true
            activityErrorMessage = nil
        }
    }

    mutating func beginBoth() {
        begin(.requests)
        begin(.activity)
    }

    mutating func succeed(_ section: CommunityIdentificationDashboardSection) {
        switch section {
        case .requests:
            isLoadingRequests = false
            requestErrorMessage = nil
        case .activity:
            isLoadingActivity = false
            activityErrorMessage = nil
        }
    }

    mutating func fail(
        _ section: CommunityIdentificationDashboardSection,
        message: String
    ) {
        switch section {
        case .requests:
            isLoadingRequests = false
            requestErrorMessage = message
        case .activity:
            isLoadingActivity = false
            activityErrorMessage = message
        }
    }
}

struct ExploreCommunityIdentificationView: View {
    @Environment(EnvironmentContextManager.self) private var environmentContextManager

    let onOpenRequest: (ExploreCommunityRequestRoute) -> Void
    let onOpenRequestsFeed: (ExploreCommunityRequestsFeedRoute) -> Void
    let onOpenActivityFeed: (ExploreCommunityActivityFeedRoute) -> Void

    @State private var requestFilter: CommunityIdentificationRequestFilter = .all
    @State private var requestItems: [CommunityIdentificationFeedItem] = []
    @State private var activityItems: [CommunityIdentificationActivityItem] = []
    @State private var loadState = IdentifyDashboardLoadState()
    @State private var loadGeneration = 0
    @AppStorage(UserDefaultsKeys.hasDismissedIdentifyRequestsBanner) private var hasDismissedRequestsBanner = false
    @State private var isFeedbackPresented = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    requestFilterBar
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
            guard requestItems.isEmpty, activityItems.isEmpty else { return }
            await reloadDashboard(clearExisting: false)
        }
        .onChange(of: requestFilter) { _, _ in
            Task { await reloadDashboard(clearExisting: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .communityIdentificationRequestDidChange)) { notification in
            guard let requestId = notification.object as? String else {
                Task { await reloadDashboard(clearExisting: false) }
                return
            }
            let isVisible = requestItems.contains { $0.requestId == requestId }
                || activityItems.contains { $0.requestId == requestId }
            guard isVisible else { return }
            Task { await reloadDashboard(clearExisting: false) }
        }
        .sheet(isPresented: $isFeedbackPresented) {
            CommunityFeedbackSheet()
        }
    }

    private var requestFilterBar: some View {
        CommunityIdentificationFilterBar(filter: $requestFilter)
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
                isLoading: loadState.isLoadingRequests && !requestItems.isEmpty,
                actionTitle: "See all requests"
            ) {
                onOpenRequestsFeed(ExploreCommunityRequestsFeedRoute(filter: requestFilter))
            }

            communityBanner

            Group {
                if loadState.isLoadingRequests, requestItems.isEmpty {
                    requestLoadingState
                } else if let requestErrorMessage = loadState.requestErrorMessage,
                          requestItems.isEmpty {
                    sectionErrorState(message: requestErrorMessage) {
                        Task { await reloadRequestsOnly() }
                    }
                } else if requestItems.isEmpty {
                    requestEmptyState
                } else {
                    requestGrid
                }
            }

            if let requestErrorMessage = loadState.requestErrorMessage,
               !requestItems.isEmpty {
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
                isLoading: loadState.isLoadingActivity && !activityItems.isEmpty,
                actionTitle: "See all activity"
            ) {
                onOpenActivityFeed(ExploreCommunityActivityFeedRoute(filter: requestFilter))
            }

            Group {
                if loadState.isLoadingActivity, activityItems.isEmpty {
                    CommunityActivityLoadingState(count: 4)
                } else if let activityErrorMessage = loadState.activityErrorMessage,
                          activityItems.isEmpty {
                    sectionErrorState(message: activityErrorMessage) {
                        Task { await reloadActivityOnly() }
                    }
                } else if activityItems.isEmpty {
                    activityEmptyState
                } else {
                    activityList
                }
            }

            if let activityErrorMessage = loadState.activityErrorMessage,
               !activityItems.isEmpty {
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
            ForEach(requestItems) { item in
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onOpenRequest(ExploreCommunityRequestRoute(requestId: item.requestId))
                } label: {
                    CommunityIdentificationGridCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }

    private var requestLoadingState: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in
                CommunityIdentificationGridCardSkeleton()
            }
        }
        .padding(.horizontal, 12)
        .accessibilityLabel("Loading community requests")
    }

    private var requestEmptyState: some View {
        CommunityIdentificationCompactEmptyState(
            title: requestEmptyStateTitle,
            message: requestEmptyStateDescription,
            systemImage: "person.2"
        )
    }

    private var requestEmptyStateTitle: String {
        requestFilter.emptyRequestTitle
    }

    private var requestEmptyStateDescription: String {
        switch requestFilter {
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
            ForEach(Array(activityItems.enumerated()), id: \.element.id) { index, item in
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onOpenRequest(ExploreCommunityRequestRoute(requestId: item.requestId))
                } label: {
                    CommunityIdentificationActivityRow(item: item)
                }
                .buttonStyle(.plain)

                if index < activityItems.count - 1 {
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
                    .background(Color.accentColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private func reloadDashboard(clearExisting: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        let filter = requestFilter

        if clearExisting {
            requestItems = []
            activityItems = []
        }
        loadState.beginBoth()

        async let requestLoad: Void = loadRequestPreview(
            filter: filter,
            generation: generation
        )
        async let activityLoad: Void = loadActivityPreview(
            filter: filter,
            generation: generation
        )
        await requestLoad
        await activityLoad
    }

    private func reloadRequestsOnly() async {
        loadState.begin(.requests)
        await loadRequestPreview(filter: requestFilter, generation: loadGeneration)
    }

    private func reloadActivityOnly() async {
        loadState.begin(.activity)
        await loadActivityPreview(filter: requestFilter, generation: loadGeneration)
    }

    private func loadRequestPreview(
        filter: CommunityIdentificationRequestFilter,
        generation: Int
    ) async {
        do {
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: CommunityIdentificationDashboardPolicy.requestPreviewLimit,
                scope: filter.scope,
                group: filter.group,
                latitude: communitySortLatitude,
                longitude: communitySortLongitude,
                cursor: .empty
            )
            guard generation == loadGeneration, filter == requestFilter else { return }
            requestItems = page
            loadState.succeed(.requests)
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, filter == requestFilter else { return }
            loadState.fail(
                .requests,
                message: ExploreErrorFormatter.message(for: error)
            )
        }
    }

    private func loadActivityPreview(
        filter: CommunityIdentificationRequestFilter,
        generation: Int
    ) async {
        do {
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationActivity(
                limit: CommunityIdentificationDashboardPolicy.activityPreviewLimit,
                scope: filter.scope,
                group: filter.group,
                cursor: .empty
            )
            guard generation == loadGeneration, filter == requestFilter else { return }
            activityItems = page
            loadState.succeed(.activity)
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, filter == requestFilter else { return }
            loadState.fail(
                .activity,
                message: ExploreErrorFormatter.recentActivityMessage(for: error)
            )
        }
    }

    private var communitySortLatitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.latitude
    }

    private var communitySortLongitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.longitude
    }
}

struct ExploreCommunityRequestsFeedView: View {
    @Environment(EnvironmentContextManager.self) private var environmentContextManager

    let onOpenRequest: (ExploreCommunityRequestRoute) -> Void

    @State private var requestFilter: CommunityIdentificationRequestFilter
    @State private var items: [CommunityIdentificationFeedItem] = []
    @State private var cursor = CommunityIdentificationCursor.empty
    @State private var isLoadingInitialPage = true
    @State private var isLoadingMore = false
    @State private var hasReachedEnd = false
    @State private var errorMessage: String?
    @State private var loadGeneration = 0

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(
        initialFilter: CommunityIdentificationRequestFilter,
        onOpenRequest: @escaping (ExploreCommunityRequestRoute) -> Void
    ) {
        _requestFilter = State(initialValue: initialFilter)
        self.onOpenRequest = onOpenRequest
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    CommunityIdentificationFilterBar(filter: $requestFilter)

                    Group {
                        if isLoadingInitialPage, items.isEmpty {
                            loadingState
                        } else if let errorMessage, items.isEmpty {
                            errorState(message: errorMessage)
                        } else if items.isEmpty {
                            emptyState
                        } else {
                            requestGrid
                        }
                    }

                    if let errorMessage, !items.isEmpty {
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
            guard items.isEmpty else { return }
            await reload()
        }
        .onChange(of: requestFilter) { _, _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .communityIdentificationRequestDidChange)) { notification in
            guard let requestId = notification.object as? String else {
                Task { await reload() }
                return
            }
            guard items.contains(where: { $0.requestId == requestId }) else { return }
            Task { await reload() }
        }
    }

    private var requestGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onOpenRequest(ExploreCommunityRequestRoute(requestId: item.requestId))
                } label: {
                    CommunityIdentificationGridCard(item: item)
                }
                .buttonStyle(.plain)
                .onAppear {
                    guard shouldLoadMore(after: item) else { return }
                    Task { await loadMore() }
                }
            }

            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .gridCellColumns(2)
                    .padding(.vertical, 18)
            }
        }
        .padding(.horizontal, 12)
    }

    private var loadingState: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                CommunityIdentificationGridCardSkeleton()
            }
        }
        .padding(.horizontal, 12)
        .accessibilityLabel("Loading community requests")
    }

    private var emptyState: some View {
        CommunityIdentificationCompactEmptyState(
            title: emptyStateTitle,
            message: emptyStateDescription,
            systemImage: "person.2"
        )
    }

    private var emptyStateTitle: String {
        requestFilter.emptyRequestTitle
    }

    private var emptyStateDescription: String {
        requestFilter == .mine
            ? "Ask the community from an insight when you want help identifying an observation."
            : "Matching identification requests will appear here."
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
        loadGeneration += 1
        let generation = loadGeneration
        let filter = requestFilter

        items = []
        cursor = .empty
        hasReachedEnd = false
        errorMessage = nil
        isLoadingInitialPage = true
        isLoadingMore = false

        do {
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: CommunityIdentificationDashboardPolicy.fullPageSize,
                scope: filter.scope,
                group: filter.group,
                latitude: communitySortLatitude,
                longitude: communitySortLongitude,
                cursor: .empty
            )
            guard generation == loadGeneration, filter == requestFilter else { return }
            items = page
            updateCursor(using: page)
            hasReachedEnd = page.count < CommunityIdentificationDashboardPolicy.fullPageSize
            isLoadingInitialPage = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, filter == requestFilter else { return }
            errorMessage = ExploreErrorFormatter.message(for: error)
            isLoadingInitialPage = false
        }
    }

    private func shouldLoadMore(after item: CommunityIdentificationFeedItem) -> Bool {
        guard !isLoadingInitialPage, !isLoadingMore, !hasReachedEnd else { return false }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        return index >= max(items.count - 6, 0)
    }

    private func loadMore() async {
        guard !isLoadingInitialPage, !isLoadingMore, !hasReachedEnd else { return }
        let generation = loadGeneration
        let filter = requestFilter
        let currentCursor = cursor
        isLoadingMore = true
        errorMessage = nil

        do {
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: CommunityIdentificationDashboardPolicy.fullPageSize,
                scope: filter.scope,
                group: filter.group,
                latitude: communitySortLatitude,
                longitude: communitySortLongitude,
                cursor: currentCursor
            )
            guard generation == loadGeneration, filter == requestFilter else { return }
            let existingIds = Set(items.map(\.id))
            items.append(contentsOf: page.filter { !existingIds.contains($0.id) })
            updateCursor(using: page)
            hasReachedEnd = page.count < CommunityIdentificationDashboardPolicy.fullPageSize
            isLoadingMore = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, filter == requestFilter else { return }
            errorMessage = ExploreErrorFormatter.message(for: error)
            isLoadingMore = false
        }
    }

    private func updateCursor(using page: [CommunityIdentificationFeedItem]) {
        guard let lastItem = page.last else { return }
        cursor = CommunityIdentificationCursor(
            beforeRequestedAt: lastItem.requestedAt,
            beforeRequestId: lastItem.requestId
        )
    }

    private var communitySortLatitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.latitude
    }

    private var communitySortLongitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.longitude
    }
}

struct ExploreCommunityActivityFeedView: View {
    let onOpenRequest: (ExploreCommunityRequestRoute) -> Void

    @State private var requestFilter: CommunityIdentificationRequestFilter
    @State private var items: [CommunityIdentificationActivityItem] = []
    @State private var cursor = CommunityIdentificationActivityCursor.empty
    @State private var isLoadingInitialPage = true
    @State private var isLoadingMore = false
    @State private var hasReachedEnd = false
    @State private var errorMessage: String?
    @State private var loadGeneration = 0

    init(
        initialFilter: CommunityIdentificationRequestFilter,
        onOpenRequest: @escaping (ExploreCommunityRequestRoute) -> Void
    ) {
        _requestFilter = State(initialValue: initialFilter)
        self.onOpenRequest = onOpenRequest
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    CommunityIdentificationFilterBar(filter: $requestFilter)

                    Group {
                        if isLoadingInitialPage, items.isEmpty {
                            CommunityActivityLoadingState(count: 8)
                        } else if let errorMessage, items.isEmpty {
                            errorState(message: errorMessage)
                        } else if items.isEmpty {
                            emptyState
                        } else {
                            activityList
                        }
                    }

                    if isLoadingMore {
                        ProgressView()
                            .padding(.vertical, 18)
                    } else if let errorMessage, !items.isEmpty {
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
        .navigationTitle("Identify activity")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard items.isEmpty else { return }
            await reload()
        }
        .onChange(of: requestFilter) { _, _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .communityIdentificationRequestDidChange)) { _ in
            Task { await reload() }
        }
    }

    private var activityList: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onOpenRequest(ExploreCommunityRequestRoute(requestId: item.requestId))
                } label: {
                    CommunityIdentificationActivityRow(item: item)
                }
                .buttonStyle(.plain)
                .onAppear {
                    guard shouldLoadMore(after: item) else { return }
                    Task { await loadMore() }
                }

                if index < items.count - 1 {
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
            Task { await reload() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 36)
    }

    private func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        let filter = requestFilter

        items = []
        cursor = .empty
        hasReachedEnd = false
        errorMessage = nil
        isLoadingInitialPage = true
        isLoadingMore = false

        do {
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationActivity(
                limit: CommunityIdentificationDashboardPolicy.fullPageSize,
                scope: filter.scope,
                group: filter.group,
                cursor: .empty
            )
            guard generation == loadGeneration, filter == requestFilter else { return }
            items = page
            updateCursor(using: page)
            hasReachedEnd = page.count < CommunityIdentificationDashboardPolicy.fullPageSize
            isLoadingInitialPage = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, filter == requestFilter else { return }
            errorMessage = ExploreErrorFormatter.recentActivityMessage(for: error)
            isLoadingInitialPage = false
        }
    }

    private func shouldLoadMore(after item: CommunityIdentificationActivityItem) -> Bool {
        guard !isLoadingInitialPage, !isLoadingMore, !hasReachedEnd else { return false }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        return index >= max(items.count - 6, 0)
    }

    private func loadMore() async {
        guard !isLoadingInitialPage, !isLoadingMore, !hasReachedEnd else { return }
        let generation = loadGeneration
        let filter = requestFilter
        let currentCursor = cursor
        isLoadingMore = true
        errorMessage = nil

        do {
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationActivity(
                limit: CommunityIdentificationDashboardPolicy.fullPageSize,
                scope: filter.scope,
                group: filter.group,
                cursor: currentCursor
            )
            guard generation == loadGeneration, filter == requestFilter else { return }
            let existingIds = Set(items.map(\.id))
            items.append(contentsOf: page.filter { !existingIds.contains($0.id) })
            updateCursor(using: page)
            hasReachedEnd = page.count < CommunityIdentificationDashboardPolicy.fullPageSize
            isLoadingMore = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, filter == requestFilter else { return }
            errorMessage = ExploreErrorFormatter.recentActivityMessage(for: error)
            isLoadingMore = false
        }
    }

    private func updateCursor(using page: [CommunityIdentificationActivityItem]) {
        guard let lastItem = page.last else { return }
        cursor = CommunityIdentificationActivityCursor(
            beforeActivityAt: lastItem.activityAt,
            beforeActivityId: lastItem.activityId
        )
    }
}

private struct CommunityIdentificationFilterBar: View {
    @Binding var filter: CommunityIdentificationRequestFilter

    var body: some View {
        CategoryFilterBar(
            items: CommunityIdentificationRequestFilter.allCases,
            activeItem: filter,
            title: { $0.title },
            onSelection: { newFilter in
                guard newFilter != filter else { return }
                filter = newFilter
            }
        )
    }
}

private struct CommunityIdentificationCompactEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
    }
}

private struct CommunityIdentificationSectionErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Retry", action: retry)
                .font(.footnote)
                .fontWeight(.semibold)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CommunityIdentificationActivityRow: View {
    let item: CommunityIdentificationActivityItem

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: activitySymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(activityColor, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2)
                        }
                        .offset(x: 4, y: 4)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(summary)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if hasTaxon {
                    Text(item.displayName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !relativeTimestamp.isEmpty {
                    Text(relativeTimestamp)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the identification request")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = SecureTransportPolicy.httpsURL(from: item.thumbnailUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        switch item.activityType {
        case .suggestionBurst:
            suggestionSummary
        case .consensusChanged:
            "Community consensus changed"
        case .resolved:
            "Community identified this request"
        }
    }

    private var suggestionSummary: String {
        let actors = item.recentActorNames
        let count = max(item.suggestionCount, 1)

        guard !actors.isEmpty else {
            return count == 1 ? "Someone suggested an ID" : "\(count) new ID suggestions"
        }
        if count == 1 {
            return "\(actors[0]) suggested an ID"
        }
        if actors.count == 1 {
            return "\(actors[0]) added \(count) ID suggestions"
        }
        if actors.count == 2 {
            return "\(actors[0]) and \(actors[1]) added \(count) ID suggestions"
        }
        return "\(actors[0]), \(actors[1]), and others added \(count) ID suggestions"
    }

    private var hasTaxon: Bool {
        item.taxonCommonName != nil || item.taxonScientificName != nil
    }

    private var activitySymbol: String {
        switch item.activityType {
        case .suggestionBurst:
            "checkmark.bubble.fill"
        case .consensusChanged:
            "arrow.triangle.2.circlepath"
        case .resolved:
            "checkmark.seal.fill"
        }
    }

    private var activityColor: Color {
        switch item.activityType {
        case .suggestionBurst:
            .blue
        case .consensusChanged:
            .orange
        case .resolved:
            .green
        }
    }

    private var relativeTimestamp: String {
        guard let date = item.activityDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CommunityActivityLoadingState: View {
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 12) {
                    GlowPulsingSkeletonView(cornerRadius: 12, style: .raisedGrid)
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 8) {
                        GlowPulsingSkeletonView(cornerRadius: 5, style: .raisedGrid)
                            .frame(height: 14)
                        GlowPulsingSkeletonView(cornerRadius: 5, style: .raisedGrid)
                            .frame(width: 140, height: 11)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if index < count - 1 {
                    Divider()
                        .padding(.leading, 92)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .accessibilityLabel("Loading identification activity")
    }
}

private struct CommunityIdentificationBanner: View {
    let title: String
    let description: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Image("bird-magnifier")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 0)
            .padding(.trailing, 56)
            .padding(.vertical, 8)

            dismissButton
                .padding(.top, 16)
                .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .circularMaterialControl(size: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss \(title) banner")
    }
}

private struct CommunityIdentificationGridCard: View {
    let item: CommunityIdentificationFeedItem

    var body: some View {
        image
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if item.hasVideoMedia {
                    ExploreMediaPlayIndicator()
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                identificationCountBadge
                    .padding(8)
            }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Community identification request")
        .accessibilityValue(identificationCountAccessibilityText)
        .accessibilityHint("Opens request details")
    }

    @ViewBuilder
    private var image: some View {
        if let url = SecureTransportPolicy.httpsURL(from: item.heroImageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    placeholder
                }
            }
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var identificationCountBadge: some View {
        Label {
            Text(item.identificationCount.formatted(.number.notation(.compactName)))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
        } icon: {
            Image(systemName: "checkmark.bubble.fill")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(.black.opacity(0.24), in: Capsule())
        .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 3)
        .accessibilityHidden(true)
    }

    private var identificationCountAccessibilityText: String {
        if item.identificationCount == 1 {
            return "1 submitted identification"
        }
        return "\(item.identificationCount) submitted identifications"
    }
}

private struct CommunityIdentificationGridCardSkeleton: View {
    var body: some View {
        GlowPulsingSkeletonView(cornerRadius: 0, style: .raisedGrid)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                submittedIdentificationBadgeSkeleton
                    .padding(8)
            }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    private var submittedIdentificationBadgeSkeleton: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: 12, height: 12)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: 14, height: 10)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .background(.black.opacity(0.18), in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
    }
}

struct ExploreCommunityIdentificationDetailView: View {
    let requestId: String
    @Environment(\.colorScheme) private var colorScheme

    @State private var detail: CommunityIdentificationDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSearchPresented = false
    @State private var isEditPresented = false
    @State private var pendingResolver: CommunityDisagreementResolverContext?
    @State private var isSubmitting = false
    @State private var isUpdatingRequest = false
    @State private var isReporting = false
    @State private var toastMessage: String?

    var body: some View {
        Group {
            if isLoading && detail == nil {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
            } else if let errorMessage, detail == nil {
                ExploreUnavailableStateView(
                    title: "Request unavailable",
                    message: errorMessage
                ) {
                    Task { await loadDetail() }
                }
            } else if let detail {
                detailContent(detail)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let detail {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if isOwnedByCurrentUser(detail) {
                            Button {
                                isEditPresented = true
                            } label: {
                                Label("Edit request", systemImage: "square.and.pencil")
                            }
                        } else {
                            Button(role: .destructive) {
                                Task { await report(detail) }
                            } label: {
                                Label("Report post", systemImage: "flag")
                            }
                            .disabled(isReporting)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .imageOverlayToolbarIconChrome(
                                isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground,
                                foregroundColor: .primary
                            )
                    }
                    .accessibilityLabel("Post options")
                    .imageOverlayToolbarButtonChrome(isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground)
                }
            }
        }
        .merianSystemFeedback(
            toastMessage: $toastMessage,
            toastAlignment: .top
        )
        .task {
            await loadDetail()
        }
        .sheet(isPresented: $isEditPresented) {
            if let detail {
                CommunityIdentificationRequestSheet(
                    speciesName: detail.displayName,
                    scientificName: requestSheetScientificName(for: detail),
                    existingRequestId: detail.requestId,
                    initialNote: detail.note,
                    initialLocationSharing: detail.locationSharing,
                    shouldLoadExistingRequestDetail: false,
                    isSubmitting: isUpdatingRequest,
                    onLoadFailed: { message in
                        toastMessage = message
                    },
                    onSubmit: { note, locationSharing in
                        Task {
                            await saveRequestEditsFromSheet(
                                note: note,
                                locationSharing: locationSharing
                            )
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $isSearchPresented) {
            if let detail {
                CommunityTaxonomySearchSheet(
                    currentPath: detail.currentPath,
                    taxonomyVersionId: detail.taxonomyVersionId,
                    initialSuggestions: detail.suggestedTaxa ?? [],
                    onSelect: handleTaxonSelection
                )
            }
        }
        .sheet(item: $pendingResolver) { context in
            CommunityDisagreementResolverSheet(
                context: context,
                isSubmitting: isSubmitting,
                onSubmit: { mode, reasoning, isGenusBestPossible in
                    Task {
                        await submit(
                            taxon: context.taxon,
                            disagreementMode: mode,
                            reasoning: reasoning,
                            isGenusBestPossible: isGenusBestPossible
                        )
                    }
                }
            )
        }
    }

    private func detailContent(_ detail: CommunityIdentificationDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CommunityDetailHero(detail: detail)

                CommunityAIIdentificationCard(detail: detail)
                    .padding(.horizontal, 16)

                if let note = detail.note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Requester note")
                            .font(.headline)
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        colorScheme == .light
                            ? Color(red: 0.95, green: 0.96, blue: 0.98)
                            : Color(uiColor: .secondarySystemGroupedBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .padding(.horizontal, 16)
                }

                CommunityIdentificationTimeline(
                    identificationCount: detail.activeIdentificationCount,
                    isConsensusUpdating: detail.isConsensusUpdating,
                    identifications: detail.identifications,
                    onWithdraw: { id in
                        Task { await withdraw(identificationId: id) }
                    },
                    onRestore: { id in
                        Task { await restore(identificationId: id) }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 88)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .contentMargins(.top, 0, for: .scrollContent)
        .refreshable {
            await loadDetail()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isSearchPresented = true
            } label: {
                Label("Suggest ID", systemImage: "magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSubmitting || detail.status != .needsId)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            detail = try await MerianNetworkClient.shared.getCommunityIdentificationDetail(requestId: requestId)
            errorMessage = nil
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func saveRequestEdits(
        note: String?,
        locationSharing: ExplorePostLocationSharing
    ) async throws {
        _ = try await MerianNetworkClient.shared.updateCommunityIdentificationRequest(
            requestId: requestId,
            note: note,
            locationSharing: locationSharing
        )
        await loadDetail()
    }

    private func saveRequestEditsFromSheet(
        note: String?,
        locationSharing: ExplorePostLocationSharing
    ) async {
        guard !isUpdatingRequest else { return }
        isUpdatingRequest = true
        defer { isUpdatingRequest = false }

        do {
            try await saveRequestEdits(note: note, locationSharing: locationSharing)
            isEditPresented = false
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Request updated"
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func requestSheetScientificName(for detail: CommunityIdentificationDetail) -> String {
        detail.currentScientificName ?? detail.initialScientificName ?? detail.displayRank
    }

    private func isOwnedByCurrentUser(_ detail: CommunityIdentificationDetail) -> Bool {
        guard let currentUserId = SupabaseManager.shared.currentUser?.id.uuidString else {
            return false
        }
        return currentUserId.lowercased() == detail.authorUserId.lowercased()
    }

    private func report(_ detail: CommunityIdentificationDetail) async {
        guard !isReporting else { return }
        isReporting = true
        defer { isReporting = false }

        let userId = SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId

        do {
            try await MerianNetworkClient.shared.submitFlagIssue(
                scanId: detail.scanId,
                flagReason: "Inappropriate content",
                userSuggestion: "Reported from Community request",
                userId: userId
            )
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Report submitted. Thanks!"
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func handleTaxonSelection(_ taxon: CommunityTaxonSearchResult) {
        guard let detail else { return }
        isSearchPresented = false

        switch taxon.relationship(to: detail.currentPath) {
        case .exact, .descendant:
            if taxon.rank == "genus" {
                pendingResolver = CommunityDisagreementResolverContext(
                    taxon: taxon,
                    currentName: detail.displayName,
                    relationship: taxon.relationship(to: detail.currentPath)
                )
                return
            }

            Task {
                await submit(
                    taxon: taxon,
                    disagreementMode: .implicitSupport,
                    reasoning: nil,
                    isGenusBestPossible: false
                )
            }
        case .ancestor, .conflict:
            pendingResolver = CommunityDisagreementResolverContext(
                taxon: taxon,
                currentName: detail.displayName,
                relationship: taxon.relationship(to: detail.currentPath)
            )
        }
    }

    private func submit(
        taxon: CommunityTaxonSearchResult,
        disagreementMode: CommunityIdentificationDisagreementMode,
        reasoning: String?,
        isGenusBestPossible: Bool
    ) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            _ = try await MerianNetworkClient.shared.submitCommunityIdentification(
                requestId: requestId,
                taxonId: taxon.taxonId,
                disagreementMode: disagreementMode,
                reasoning: reasoning,
                isGenusBestPossible: isGenusBestPossible
            )
            pendingResolver = nil
            HapticManager.shared.triggerSuccessPulse()
            await loadDetail()
            notifyCommunityIdentificationRequestChanged()
        } catch {
            HapticManager.shared.triggerErrorThump()
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func withdraw(identificationId: String) async {
        do {
            _ = try await MerianNetworkClient.shared.withdrawCommunityIdentification(identificationId: identificationId)
            HapticManager.shared.triggerSelectionPulse()
            await loadDetail()
            notifyCommunityIdentificationRequestChanged()
        } catch {
            HapticManager.shared.triggerErrorThump()
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func restore(identificationId: String) async {
        do {
            _ = try await MerianNetworkClient.shared.restoreCommunityIdentification(identificationId: identificationId)
            HapticManager.shared.triggerSelectionPulse()
            await loadDetail()
            notifyCommunityIdentificationRequestChanged()
        } catch {
            HapticManager.shared.triggerErrorThump()
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func notifyCommunityIdentificationRequestChanged() {
        NotificationCenter.default.post(
            name: .communityIdentificationRequestDidChange,
            object: requestId
        )
    }
}

private extension Notification.Name {
    static let communityIdentificationRequestDidChange = Notification.Name("MerianCommunityIdentificationRequestDidChange")
}

private struct CommunityDetailHero: View {
    let detail: CommunityIdentificationDetail

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = max(width, 320)
            let bleedBuffer: CGFloat = 48

            ExplorePublicMediaView(
                mediaItem: detail.resolvedMediaItems.first ?? .legacyImage(url: detail.heroImageUrl),
                fallbackImageUrl: detail.heroImageUrl,
                reloadGeneration: 0,
                preloadedImage: nil,
                surface: .communityIdentification,
                autoplay: true,
                showsVideoControls: true
            )
            .frame(width: width, height: height + bleedBuffer)
            .offset(y: -bleedBuffer)
            .clipped()
        }
        .frame(height: max(UIScreen.main.bounds.width, 320))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.black.opacity(0.36), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 132)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(.all, edges: .top)
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CommunityAIIdentificationCard: View {
    let detail: CommunityIdentificationDetail

    @Environment(\.colorScheme) private var colorScheme
    @State private var isReasoningExpanded = false

    private var aiSuggestion: CommunityTaxonSearchResult? {
        detail.suggestedTaxa?.first { $0.suggestionSource == .aiInitial }
    }

    private var aiDisplayName: String {
        aiSuggestion?.displayName
            ?? CommunityTaxonDisplay.name(
                commonName: detail.initialCommonName,
                scientificName: detail.initialScientificName
            )
    }

    private var aiScientificName: String? {
        let value = aiSuggestion?.scientificName ?? detail.initialScientificName
        guard let scientificName = trimmed(value) else { return nil }
        guard scientificName.localizedCaseInsensitiveCompare(aiDisplayName) != .orderedSame else {
            return nil
        }
        return scientificName
    }

    private var aiConfidenceScore: Double? {
        aiSuggestion?.confidenceScore
    }

    private var confidenceLabel: String? {
        guard let aiConfidenceScore else { return nil }
        let clampedScore = min(max(aiConfidenceScore, 0), 1)
        return "\(Int((clampedScore * 100).rounded()))% confident"
    }

    private var aiReasoning: String? {
        trimmed(aiSuggestion?.distinguishingFeature)
    }

    private var modelLabel: String {
        switch detail.inferenceTier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pro":
            "Naturebook Pro"
        default:
            "Naturebook Flash"
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let result = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else {
            return nil
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Label(modelLabel, systemImage: "sparkle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)

                Spacer(minLength: 12)

                if let confidenceLabel {
                    Text(confidenceLabel)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(aiDisplayName)
                    .font(.title3)
                    .fontWeight(.bold)

                if let aiScientificName {
                    Text(aiScientificName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let aiReasoning {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        isReasoningExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("AI reasoning")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(isReasoningExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isReasoningExpanded ? "Hide AI reasoning" : "Show AI reasoning")

                if isReasoningExpanded {
                    Text(aiReasoning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(16)
        .background(
            colorScheme == .light
                ? Color(red: 0.95, green: 0.96, blue: 0.98)
                : Color(uiColor: .secondarySystemGroupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct CommunityIdentificationTimeline: View {
    let identificationCount: Int
    let isConsensusUpdating: Bool
    let identifications: [CommunityIdentification]
    let onWithdraw: (String) -> Void
    let onRestore: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Identifications")
                    .font(.headline)
                Spacer()
                Text(identificationCountLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            if isConsensusUpdating {
                Label("Consensus updating", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if identifications.isEmpty {
                Text("No one has suggested an ID yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(identifications) { identification in
                        CommunityIdentificationRow(
                            identification: identification,
                            onWithdraw: onWithdraw,
                            onRestore: onRestore
                        )
                    }
                }
            }
        }
    }

    private var identificationCountLabel: String {
        identificationCount == 1 ? "1 ID" : "\(identificationCount) IDs"
    }
}

private struct CommunityIdentificationRow: View {
    let identification: CommunityIdentification
    let onWithdraw: (String) -> Void
    let onRestore: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: identification.withdrawnAt == nil ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                    .foregroundStyle(identification.withdrawnAt == nil ? .green : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(identification.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(identificationSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if identification.isViewer {
                    Button(identification.withdrawnAt == nil ? "Withdraw" : "Restore") {
                        if identification.withdrawnAt == nil {
                            onWithdraw(identification.id)
                        } else {
                            onRestore(identification.id)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            if let reasoning = identification.reasoning, !reasoning.isEmpty {
                Text(reasoning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(identification.withdrawnAt == nil ? 1 : 0.64)
    }

    private var identificationSubtitle: String {
        "\(identification.displayRank) by \(identification.authorName)"
    }
}

private struct CommunityTaxonomySearchSheet: View {
    let currentPath: String?
    let taxonomyVersionId: String?
    let initialSuggestions: [CommunityTaxonSearchResult]
    let onSelect: (CommunityTaxonSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CommunityTaxonSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var activeSearchId: UUID?

    var body: some View {
        NavigationStack {
            List {
                if isShowingInitialSuggestions {
                    Section("Suggested from AI analysis") {
                        if initialSuggestions.isEmpty {
                            Text("No AI suggestions are available for this request.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(initialSuggestions) { suggestion in
                                taxonButton(for: suggestion)
                            }
                        }
                    }
                } else {
                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }

                    ForEach(results) { result in
                        taxonButton(for: result)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Suggest ID")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .task(id: query) {
                await search()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .imageOverlayToolbarIconChrome(
                                isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground,
                                foregroundColor: .primary
                            )
                    }
                    .accessibilityLabel("Close")
                    .imageOverlayToolbarButtonChrome(isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground)
                }
            }
        }
    }

    private var isShowingInitialSuggestions: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
    }

    private func taxonButton(for result: CommunityTaxonSearchResult) -> some View {
        Button {
            onSelect(result)
            dismiss()
        } label: {
            CommunityTaxonSearchRow(result: result)
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func search() async {
        let searchId = UUID()
        activeSearchId = searchId

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil
        defer {
            if activeSearchId == searchId {
                isSearching = false
            }
        }

        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            let searchResults = try await MerianNetworkClient.shared.searchCommunityTaxa(
                query: trimmed,
                taxonomyVersionId: taxonomyVersionId
            )
            try Task.checkCancellation()
            guard activeSearchId == searchId else { return }

            results = searchResults
            errorMessage = searchResults.isEmpty ? "No matching taxa found." : nil
        } catch {
            guard activeSearchId == searchId,
                  !ExploreErrorFormatter.isCancellation(error),
                  !Task.isCancelled else {
                return
            }
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }
}

private struct CommunityTaxonSearchRow: View {
    let result: CommunityTaxonSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.displayName)
                .font(.body)
                .foregroundStyle(.primary)
            Text("\(result.displayRank) - \(result.scientificName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let label = result.suggestionSource?.displayLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CommunityDisagreementResolverContext: Identifiable {
    let id = UUID()
    let taxon: CommunityTaxonSearchResult
    let currentName: String
    let relationship: CommunityTaxonPathRelationship
}

private struct CommunityDisagreementResolverSheet: View {
    let context: CommunityDisagreementResolverContext
    let isSubmitting: Bool
    let onSubmit: (CommunityIdentificationDisagreementMode, String?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reasoning = ""
    @State private var isGenusBestPossible = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)

                if context.relationship == .conflict {
                    reasonField
                }

                if context.taxon.rank == "genus" {
                    Toggle("This genus is as specific as it can get", isOn: $isGenusBestPossible)
                }

                Spacer()

                VStack(spacing: 10) {
                    Button {
                        onSubmit(primaryMode, submittedReasoning, isGenusBestPossible)
                        dismiss()
                    } label: {
                        Text(primaryTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSubmitting)

                    if context.relationship == .ancestor {
                        Button {
                            onSubmit(.explicitDisagreement, submittedReasoning, isGenusBestPossible)
                            dismiss()
                        } label: {
                            Text("I don't think it's \(context.currentName)")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isSubmitting)
                    }
                }
            }
            .padding(20)
            .navigationTitle("Confirm intent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .imageOverlayToolbarIconChrome(
                                isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground,
                                foregroundColor: .primary
                            )
                    }
                    .accessibilityLabel("Close")
                    .imageOverlayToolbarButtonChrome(isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Optional reason", text: $reasoning, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(4...7)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var title: String {
        switch context.relationship {
        case .ancestor:
            return "You selected \(context.taxon.displayName)"
        case .conflict:
            return "This disagrees with \(context.currentName)"
        case .exact, .descendant:
            return "Confirm identification"
        }
    }

    private var message: String {
        switch context.relationship {
        case .ancestor:
            return "The community is currently more specific. Choose whether you are only less certain, or actively disagree with the current ID."
        case .conflict:
            return "Add a short reason if it helps others understand what you are seeing."
        case .exact, .descendant:
            return "Submit this identification to the community timeline."
        }
    }

    private var primaryTitle: String {
        switch context.relationship {
        case .ancestor:
            return "I'm only sure it's \(context.taxon.displayName)"
        case .conflict:
            return "Submit as \(context.taxon.displayName)"
        case .exact, .descendant:
            return "Submit"
        }
    }

    private var primaryMode: CommunityIdentificationDisagreementMode {
        context.relationship == .conflict ? .maverick : .implicitSupport
    }

    private var submittedReasoning: String? {
        let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
