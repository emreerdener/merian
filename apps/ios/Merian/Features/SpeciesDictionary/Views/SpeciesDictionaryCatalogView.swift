import SwiftUI

enum SpeciesDictionaryCategoryRoute: Hashable {
    case catalog(title: String, category: SpeciesDictionaryCatalogCategory, region: String?)
    case taxonomy
    case regions
}

struct SpeciesDictionaryCatalogView: View {
    let isSearchEnabled: Bool
    let showsNavigationTitle: Bool
    let navigationTitle: String
    let category: SpeciesDictionaryCatalogCategory
    let region: String?
    private let externalSearchText: Binding<String>?
    @State private var localSearchText = ""
    @State private var items: [SpeciesDictionaryCatalogItem] = []
    @State private var nextCursor: SpeciesDictionaryCatalogCursor?
    @State private var isLoadingInitial = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    private let pageLimit = 40

    init(
        isSearchEnabled: Bool = true,
        showsNavigationTitle: Bool = true,
        navigationTitle: String = "Dictionary",
        category: SpeciesDictionaryCatalogCategory = .all,
        region: String? = nil,
        searchText: Binding<String>? = nil
    ) {
        self.isSearchEnabled = isSearchEnabled
        self.showsNavigationTitle = showsNavigationTitle
        self.navigationTitle = navigationTitle
        self.category = category
        self.region = region
        self.externalSearchText = searchText
    }

    var body: some View {
        Group {
            if isLoadingInitial && items.isEmpty {
                loadingState
            } else if let errorMessage, items.isEmpty {
                errorState(message: errorMessage)
            } else if items.isEmpty {
                emptyState
            } else {
                catalogList
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .modifier(SpeciesDictionaryCatalogTitleModifier(title: navigationTitle, isEnabled: showsNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SpeciesDictionaryCatalogSearchModifier(
            searchText: searchTextBinding,
            isEnabled: isSearchEnabled && externalSearchText == nil
        ))
        .task {
            await loadInitialCatalog()
        }
        .task(id: activeSearchText) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadInitialCatalog()
        }
    }

    private var catalogList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    NavigationLink(value: item.dictionaryRoute) {
                        SpeciesDictionaryCatalogRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        guard item.id == items.last?.id else { return }
                        Task { await loadMoreIfNeeded() }
                    }
                }

                if isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable {
            await loadInitialCatalog()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading species")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No species found",
            systemImage: "book.closed",
            description: Text("Try a different scientific name.")
        )
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label("Dictionary unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await loadInitialCatalog() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @MainActor
    private func loadInitialCatalog() async {
        isLoadingInitial = true
        errorMessage = nil
        do {
            let response = try await MerianNetworkClient.shared.getSpeciesDictionaryCatalog(
                category: category,
                region: region,
                query: normalizedQuery,
                limit: pageLimit
            )
            items = response.data
            nextCursor = response.nextCursor
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
        isLoadingInitial = false
    }

    @MainActor
    private func loadMoreIfNeeded() async {
        guard !isLoadingInitial, !isLoadingMore, let nextCursor else { return }
        isLoadingMore = true
        do {
            let response = try await MerianNetworkClient.shared.getSpeciesDictionaryCatalog(
                category: category,
                region: region,
                query: normalizedQuery,
                limit: pageLimit,
                cursor: nextCursor
            )
            items.append(contentsOf: response.data)
            self.nextCursor = response.nextCursor
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
        isLoadingMore = false
    }

    private var normalizedQuery: String? {
        activeSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private var activeSearchText: String {
        searchTextBinding.wrappedValue
    }

    private var searchTextBinding: Binding<String> {
        externalSearchText ?? $localSearchText
    }
}

struct SpeciesDictionaryOverviewView: View {
    let userRegion: String?

    @State private var overview: SpeciesDictionaryOverview?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && overview == nil {
                loadingState
            } else if let errorMessage, overview == nil {
                errorState(message: errorMessage)
            } else if let overview {
                overviewContent(overview)
            } else {
                loadingState
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: userRegion ?? "") {
            await loadOverview()
        }
    }

    private func overviewContent(_ overview: SpeciesDictionaryOverview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(overview.categories) { category in
                        NavigationLink(value: route(for: category)) {
                            SpeciesDictionaryCategoryCard(category: category)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Regions")
                        .font(.headline)
                        .padding(.horizontal, 2)

                    NavigationLink(value: SpeciesDictionaryCategoryRoute.regions) {
                        SpeciesDictionaryRegionRow(
                            title: "Browse all regions",
                            count: overview.regions.count,
                            referenceImageUrl: overview.regions.first?.referenceImageUrl,
                            systemImage: "globe.americas"
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(overview.regions) { region in
                        NavigationLink(
                            value: SpeciesDictionaryCategoryRoute.catalog(
                                title: region.title,
                                category: .region,
                                region: region.title
                            )
                        ) {
                            SpeciesDictionaryRegionRow(
                                title: region.title,
                                count: region.count,
                                referenceImageUrl: region.referenceImageUrl,
                                systemImage: "mappin.and.ellipse"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable {
            await loadOverview()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading dictionary")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label("Dictionary unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await loadOverview() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @MainActor
    private func loadOverview() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await MerianNetworkClient.shared.getSpeciesDictionaryOverview(
                userRegion: userRegion
            )
            overview = response.data
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
        isLoading = false
    }

    private func route(for category: SpeciesDictionaryCategorySummary) -> SpeciesDictionaryCategoryRoute {
        switch category.id {
        case .all:
            return .catalog(title: "All", category: .all, region: nil)
        case .yourRegion:
            let region = category.region?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let region, !region.isEmpty else {
                return .regions
            }
            return .catalog(title: "Your Region", category: .region, region: region)
        case .taxonomy:
            return .taxonomy
        case .recentlyAdded:
            return .catalog(title: "Recently Added", category: .recentlyAdded, region: nil)
        }
    }
}

private struct SpeciesDictionaryCategoryCard: View {
    let category: SpeciesDictionaryCategorySummary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cardImage

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(countLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cardImage: some View {
        if let referenceImageUrl = category.referenceImageUrl,
           let url = URL(string: referenceImageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        Rectangle()
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .offset(y: -20)
            }
    }

    private var iconName: String {
        switch category.id {
        case .all: "book.closed"
        case .yourRegion: "location"
        case .taxonomy: "point.3.connected.trianglepath.dotted"
        case .recentlyAdded: "sparkles"
        }
    }

    private var countLabel: String {
        "\(category.count) Species"
    }
}

private struct SpeciesDictionaryRegionRow: View {
    let title: String
    let count: Int
    let referenceImageUrl: String?
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let referenceImageUrl, let url = URL(string: referenceImageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholderThumbnail
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholderThumbnail
                .frame(width: 48, height: 48)
        }
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .overlay {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
    }
}

struct SpeciesDictionaryRegionsView: View {
    let userRegion: String?

    @State private var overview: SpeciesDictionaryOverview?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && overview == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, overview == nil {
                ContentUnavailableView {
                    Label("Regions unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await loadOverview() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if let overview {
                regionList(overview)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Regions")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: userRegion ?? "") {
            await loadOverview()
        }
    }

    private func regionList(_ overview: SpeciesDictionaryOverview) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(overview.regions) { region in
                    NavigationLink(
                        value: SpeciesDictionaryCategoryRoute.catalog(
                            title: region.title,
                            category: .region,
                            region: region.title
                        )
                    ) {
                        SpeciesDictionaryRegionRow(
                            title: region.title,
                            count: region.count,
                            referenceImageUrl: region.referenceImageUrl,
                            systemImage: "mappin.and.ellipse"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .refreshable {
            await loadOverview()
        }
    }

    @MainActor
    private func loadOverview() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await MerianNetworkClient.shared.getSpeciesDictionaryOverview(
                userRegion: userRegion
            )
            overview = response.data
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
        isLoading = false
    }
}

// Species record row used by the Explore Dictionary tab and standalone catalog.
private struct SpeciesDictionaryCatalogRow: View {
    let item: SpeciesDictionaryCatalogItem
    private let thumbnailSize: CGFloat = 88

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 5) {
                Text(item.commonName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(item.scientificName)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let taxonomySummary {
                    Text(taxonomySummary)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let referenceImageUrl = item.referenceImageUrl,
           let url = URL(string: referenceImageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholderThumbnail
                }
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholderThumbnail
                .frame(width: thumbnailSize, height: thumbnailSize)
        }
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .overlay {
                Image(systemName: "leaf")
                    .foregroundStyle(.secondary)
            }
    }

    private var taxonomySummary: String? {
        [
            item.taxonomy?.kingdom,
            item.taxonomy?.className,
            item.taxonomy?.family
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        .joined(separator: " - ")
        .nilIfEmpty
    }
}

private struct SpeciesDictionaryCatalogSearchModifier: ViewModifier {
    @Binding var searchText: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search species"
            )
        } else {
            content
        }
    }
}

private struct SpeciesDictionaryCatalogTitleModifier: ViewModifier {
    let title: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationTitle(title)
        } else {
            content
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
