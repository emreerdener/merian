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

struct ExploreCommunityIdentificationView: View {
    @Environment(EnvironmentContextManager.self) private var environmentContextManager

    @Binding var activeMode: CommunityIdentificationMode
    let onOpenRequest: (ExploreCommunityRequestRoute) -> Void

    @State private var requestScope: CommunityIdentificationFeedScope = .all
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
        .onChange(of: requestScope) { _, _ in
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
                requestScopeFilter

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

    private var requestScopeFilter: some View {
        CategoryFilterBar(
            items: CommunityIdentificationFeedScope.allCases,
            activeItem: requestScope,
            title: { $0.title },
            onSelection: { scope in
                guard scope != requestScope else { return }
                requestScope = scope
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
            requestScope == .mine ? "No Requests From You Yet" : "No Requests Yet",
            systemImage: "person.2",
            description: Text(requestScope == .mine ? "Ask the Community from an insight when you want help identifying one of your observations." : "Identification requests will appear here when explorers ask for help.")
        )
        .padding(.horizontal, 16)
        .padding(.top, 42)
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
        let scope = requestScope
        isLoadingInitialPage = true
        defer { isLoadingInitialPage = false }

        do {
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: pageSize,
                scope: scope,
                latitude: communitySortLatitude,
                longitude: communitySortLongitude,
                cursor: .empty
            )
            guard scope == requestScope else { return }
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
            let scope = requestScope
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: pageSize,
                scope: scope,
                latitude: communitySortLatitude,
                longitude: communitySortLongitude,
                cursor: cursor
            )
            guard scope == requestScope else { return }
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

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(title) banner")
        }
        .padding(.leading, 0)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CommunityIdentificationGridCard: View {
    let item: CommunityIdentificationFeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            image
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Label("\(item.identificationCount)", systemImage: "checkmark.bubble")
                    if let location = item.publicDisplayLocationLabel {
                        Text(location)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
}

private struct CommunityIdentificationGridCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlowPulsingSkeletonView(cornerRadius: 0, style: .raisedGrid)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 7) {
                GlowPulsingSkeletonView(cornerRadius: 5)
                    .frame(width: 112, height: 16)

                GlowPulsingSkeletonView(cornerRadius: 4)
                    .frame(width: 54, height: 12)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 7)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
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
        .navigationTitle(detail?.displayName ?? "Community ID")
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
                                Label("Report request", systemImage: "flag")
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
                    .accessibilityLabel("Request options")
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

                CommunityConsensusPanel(detail: detail)
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

private struct CommunityConsensusPanel: View {
    let detail: CommunityIdentificationDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.displayName)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(detail.displayRank)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(detail.identificationCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("IDs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let score = detail.consensusScore {
                ProgressView(value: min(max(score, 0), 1))
                    .progressViewStyle(.linear)
                Text("\(Int((score * 100).rounded()))% consensus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if detail.isConsensusUpdating {
                Label("Consensus updating", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let location = detail.publicDisplayLocationLabel {
                Label(location, systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CommunityIdentificationTimeline: View {
    let identifications: [CommunityIdentification]
    let onWithdraw: (String) -> Void
    let onRestore: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Identifications")
                .font(.headline)

            if identifications.isEmpty {
                Text("No one has suggested an ID yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
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
