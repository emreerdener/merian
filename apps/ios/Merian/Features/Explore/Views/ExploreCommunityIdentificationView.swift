import SwiftUI

struct ExploreCommunityRequestRoute: Hashable {
    let requestId: String
}

enum CommunityIdentificationMode: Hashable, CaseIterable {
    case requests
    case activity

    var title: String {
        switch self {
        case .requests:
            "Requests"
        case .activity:
            "Activity"
        }
    }

    var description: String {
        switch self {
        case .requests:
            "Help identify open requests from Merian explorers."
        case .activity:
            "See recent consensus decisions from Merian explorers."
        }
    }

    var bannerTitle: String {
        switch self {
        case .requests:
            "Ask the community"
        case .activity:
            "Community activity"
        }
    }
}

private enum CommunityIdentificationRequestFilter: Hashable, CaseIterable {
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
}

struct ExploreCommunityIdentificationView: View {
    @Environment(EnvironmentContextManager.self) private var environmentContextManager

    @Binding var activeMode: CommunityIdentificationMode
    let onOpenRequest: (ExploreCommunityRequestRoute) -> Void

    @State private var requestFilter: CommunityIdentificationRequestFilter = .all
    @State private var items: [CommunityIdentificationFeedItem] = []
    @State private var cursor = CommunityIdentificationCursor.empty
    @State private var isLoadingInitialPage = true
    @State private var isLoadingMore = false
    @State private var hasReachedEnd = false
    @State private var errorMessage: String?
    @AppStorage(UserDefaultsKeys.hasDismissedIdentifyRequestsBanner) private var hasDismissedRequestsBanner = false
    @AppStorage(UserDefaultsKeys.hasDismissedIdentifyActivityBanner) private var hasDismissedActivityBanner = false

    private let pageSize = 30
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            Group {
                switch activeMode {
                case .requests:
                    requestsContent
                case .activity:
                    activityContent
                }
            }
        }
        .navigationTitle("Identify")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard activeMode == .requests else { return }
            await loadInitialPage()
        }
        .onChange(of: requestFilter) { _, _ in
            Task { await reloadForScopeChange() }
        }
        .onChange(of: activeMode) { _, newValue in
            guard newValue == .requests, items.isEmpty else { return }
            Task { await loadInitialPage() }
        }
    }

    private var requestsContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                requestFilterBar

                communityBanner

                Group {
                    if isLoadingInitialPage && items.isEmpty {
                        loadingState
                    } else if let errorMessage, items.isEmpty {
                        errorState(message: errorMessage)
                    } else if items.isEmpty {
                        emptyState
                    } else {
                        requestGrid
                    }
                }
                .padding(.top, 18)
            }
            .padding(.bottom, 18)
        }
        .refreshable {
            await refresh()
        }
    }

    private var activityContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                communityBanner

                ContentUnavailableView(
                    "Activity",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Consensus updates, resolved requests, and identification progress will appear here once activity tracking is ready.")
                )
                .padding(.horizontal, 16)
                .padding(.top, 72)
            }
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var communityBanner: some View {
        if isCommunityBannerVisible {
            CommunityIdentificationBanner(
                title: activeMode.bannerTitle,
                description: activeMode.description,
                onDismiss: dismissActiveBanner
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var requestFilterBar: some View {
        CategoryFilterBar(
            items: CommunityIdentificationRequestFilter.allCases,
            activeItem: requestFilter,
            title: { $0.title },
            onSelection: { filter in
                guard filter != requestFilter else { return }
                requestFilter = filter
            }
        )
    }

    private var isCommunityBannerVisible: Bool {
        switch activeMode {
        case .requests:
            !hasDismissedRequestsBanner
        case .activity:
            !hasDismissedActivityBanner
        }
    }

    private func dismissActiveBanner() {
        withAnimation(.snappy(duration: 0.2)) {
            switch activeMode {
            case .requests:
                hasDismissedRequestsBanner = true
            case .activity:
                hasDismissedActivityBanner = true
            }
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
                    Task { await loadMoreIfNeeded(currentItem: item) }
                }
            }

            if isLoadingMore {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity)
                    .gridCellColumns(2)
                    .padding(.vertical, 18)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 18)
    }

    private var loadingState: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in
                CommunityIdentificationGridCardSkeleton()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 18)
        .accessibilityLabel("Loading community requests")
    }

    private var emptyState: some View {
        ContentUnavailableView(
            emptyStateTitle,
            systemImage: "person.2",
            description: Text(emptyStateDescription)
        )
        .padding(.horizontal, 16)
        .padding(.top, 42)
    }

    private var emptyStateTitle: String {
        switch requestFilter {
        case .mine:
            "No Requests From You Yet"
        case .all:
            "No Requests Yet"
        default:
            "No \(requestFilter.title) Requests Yet"
        }
    }

    private var emptyStateDescription: String {
        switch requestFilter {
        case .mine:
            "Ask the Community from an insight when you want help identifying one of your observations."
        case .all:
            "Identification requests will appear here when explorers ask for help."
        default:
            "Matching identification requests will appear here when explorers ask for help."
        }
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Identify unavailable",
            message: message
        ) {
            Task { await refresh() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 42)
    }

    private func loadInitialPage() async {
        guard items.isEmpty else { return }
        await fetchFirstPage()
    }

    private func refresh() async {
        cursor = .empty
        hasReachedEnd = false
        await fetchFirstPage()
    }

    private func fetchFirstPage() async {
        let filter = requestFilter
        isLoadingInitialPage = true
        defer { isLoadingInitialPage = false }

        do {
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: pageSize,
                scope: filter.scope,
                group: filter.group,
                latitude: communitySortLatitude,
                longitude: communitySortLongitude,
                cursor: .empty
            )
            guard filter == requestFilter else { return }
            items = page
            updateCursor(using: page)
            hasReachedEnd = page.count < pageSize
            errorMessage = nil
        } catch {
            if items.isEmpty {
                errorMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

    private func loadMoreIfNeeded(currentItem: CommunityIdentificationFeedItem) async {
        guard !isLoadingInitialPage, !isLoadingMore, !hasReachedEnd else { return }
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= max(items.count - 6, 0) else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let filter = requestFilter
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: pageSize,
                scope: filter.scope,
                group: filter.group,
                latitude: communitySortLatitude,
                longitude: communitySortLongitude,
                cursor: cursor
            )
            guard filter == requestFilter else { return }
            let existing = Set(items.map(\.id))
            items.append(contentsOf: page.filter { !existing.contains($0.id) })
            updateCursor(using: page)
            hasReachedEnd = page.count < pageSize
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func updateCursor(using page: [CommunityIdentificationFeedItem]) {
        cursor = CommunityIdentificationCursor(
            beforeRequestedAt: page.last?.requestedAt,
            beforeRequestId: page.last?.requestId
        )
    }

    private func reloadForScopeChange() async {
        items = []
        cursor = .empty
        hasReachedEnd = false
        errorMessage = nil
        await fetchFirstPage()
    }

    private var communitySortLatitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.latitude
    }

    private var communitySortLongitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.longitude
    }
}

private struct CommunityIdentificationBanner: View {
    let title: String
    let description: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Image("identify")
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
        if let url = URL(string: item.heroImageUrl) {
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

    @State private var detail: CommunityIdentificationDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSearchPresented = false
    @State private var isEditPresented = false
    @State private var pendingResolver: CommunityDisagreementResolverContext?
    @State private var isSubmitting = false
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
                                Label("Edit post", systemImage: "square.and.pencil")
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
                CommunityIdentificationRequestEditSheet(
                    detail: detail,
                    onSave: { note, locationSharing in
                        try await saveRequestEdits(note: note, locationSharing: locationSharing)
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
                    .padding(.horizontal, 16)
                }

                CommunityIdentificationTimeline(
                    identificationCount: detail.identificationCount,
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
        } catch {
            HapticManager.shared.triggerErrorThump()
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }
}

private struct CommunityDetailHero: View {
    let detail: CommunityIdentificationDetail

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = max(width, 320)
            let bleedBuffer: CGFloat = 48

            if let url = URL(string: detail.heroImageUrl) {
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
                .frame(width: width, height: height + bleedBuffer)
                .offset(y: -bleedBuffer)
                .clipped()
            } else {
                placeholder
                    .frame(width: width, height: height + bleedBuffer)
                    .offset(y: -bleedBuffer)
            }
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
            "Merian Pro"
        default:
            "Merian Flash"
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)

                Spacer(minLength: 12)

                if let confidenceLabel {
                    Text(confidenceLabel)
                        .font(.caption.weight(.semibold))
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
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            if colorScheme == .light {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
            }
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

private struct CommunityIdentificationRequestEditSheet: View {
    let detail: CommunityIdentificationDetail
    let onSave: (String?, ExplorePostLocationSharing) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var locationSharing: ExplorePostLocationSharing
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        detail: CommunityIdentificationDetail,
        onSave: @escaping (String?, ExplorePostLocationSharing) async throws -> Void
    ) {
        self.detail = detail
        self.onSave = onSave
        _note = State(initialValue: detail.note ?? "")
        _locationSharing = State(initialValue: detail.locationSharing ?? .obscured)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.displayName)
                            .font(.headline)
                        Text(detail.displayRank)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Request") {
                    TextEditor(text: $note)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if trimmedNote == nil {
                                Text("What should identifiers know?")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section("Location") {
                    Picker("Location Sharing", selection: $locationSharing) {
                        ForEach(ExplorePostLocationSharing.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit request")
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

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await save() }
                    }
                    .tint(.blue)
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await onSave(trimmedNote, locationSharing)
            dismiss()
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
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
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            results = try await MerianNetworkClient.shared.searchCommunityTaxa(
                query: trimmed,
                taxonomyVersionId: taxonomyVersionId
            )
            errorMessage = results.isEmpty ? "No matching taxa found." : nil
        } catch is CancellationError {
        } catch {
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
                    Button(primaryTitle) {
                        onSubmit(primaryMode, submittedReasoning, isGenusBestPossible)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(isSubmitting)

                    if context.relationship == .ancestor {
                        Button("I don't think it's \(context.currentName)") {
                            onSubmit(.explicitDisagreement, submittedReasoning, isGenusBestPossible)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
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
