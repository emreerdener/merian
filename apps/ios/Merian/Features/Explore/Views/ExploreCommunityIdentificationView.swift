import SwiftUI

struct ExploreCommunityRequestRoute: Hashable {
    let requestId: String
}

struct ExploreCommunityIdentificationView: View {
    @Environment(EnvironmentContextManager.self) private var environmentContextManager

    let onOpenRequest: (ExploreCommunityRequestRoute) -> Void

    @State private var items: [CommunityIdentificationFeedItem] = []
    @State private var cursor = CommunityIdentificationCursor.empty
    @State private var isLoadingInitialPage = true
    @State private var isLoadingMore = false
    @State private var hasReachedEnd = false
    @State private var errorMessage: String?

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
                if isLoadingInitialPage && items.isEmpty {
                    loadingState
                } else if let errorMessage, items.isEmpty {
                    errorState(message: errorMessage)
                } else if items.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
        }
        .navigationTitle("Ask the Community")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInitialPage()
        }
        .refreshable {
            await refresh()
        }
    }

    private var grid: some View {
        ScrollView {
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
            .padding(12)
            .padding(.bottom, 18)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading community requests")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Requests Yet",
            systemImage: "person.2",
            description: Text("Community identification requests will appear here when explorers ask for help.")
        )
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label("Community Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
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
        isLoadingInitialPage = true
        defer { isLoadingInitialPage = false }

        do {
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: pageSize,
                latitude: communitySortLatitude,
                longitude: communitySortLongitude,
                cursor: .empty
            )
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
            let page = try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: pageSize,
                latitude: communitySortLatitude,
                longitude: communitySortLongitude,
                cursor: cursor
            )
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

    private var communitySortLatitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.latitude
    }

    private var communitySortLongitude: Double? {
        environmentContextManager.lastKnownLocation?.coordinate.longitude
    }
}

private struct CommunityIdentificationGridCard: View {
    let item: CommunityIdentificationFeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            image
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Text(item.displayRank)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .padding(8)
                }

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

struct ExploreCommunityIdentificationDetailView: View {
    let requestId: String

    @State private var detail: CommunityIdentificationDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSearchPresented = false
    @State private var pendingResolver: CommunityDisagreementResolverContext?
    @State private var isSubmitting = false

    var body: some View {
        Group {
            if isLoading && detail == nil {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
            } else if let errorMessage, detail == nil {
                ContentUnavailableView {
                    Label("Request Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") {
                        Task { await loadDetail() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if let detail {
                detailContent(detail)
            }
        }
        .navigationTitle(detail?.displayName ?? "Community ID")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
        }
        .sheet(isPresented: $isSearchPresented) {
            if let detail {
                CommunityTaxonomySearchSheet(
                    currentPath: detail.currentPath,
                    taxonomyVersionId: detail.taxonomyVersionId,
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
        VStack(alignment: .leading, spacing: 0) {
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
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipped()
            } else {
                placeholder
                    .aspectRatio(4 / 3, contentMode: .fit)
            }
        }
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
        if let role = identification.displayRole {
            return "\(identification.displayRank) - \(role) by \(identification.authorName)"
        }

        return "\(identification.displayRank) by \(identification.authorName)"
    }
}

private struct CommunityTaxonomySearchSheet: View {
    let currentPath: String?
    let taxonomyVersionId: String?
    let onSelect: (CommunityTaxonSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CommunityTaxonSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                ForEach(results) { result in
                    Button {
                        onSelect(result)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("\(result.displayRank) - \(result.scientificName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Button("Cancel") { dismiss() }
                }
            }
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
                    TextEditor(text: $reasoning)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .navigationTitle("Confirm Intent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
