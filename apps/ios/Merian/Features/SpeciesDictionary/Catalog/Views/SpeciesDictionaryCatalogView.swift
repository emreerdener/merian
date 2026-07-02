import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum SpeciesDictionaryCategoryRoute: Hashable {
    case catalog(title: String, category: SpeciesDictionaryCatalogCategory, region: String?)
    case group(title: String, group: String)
    case taxonomy
    case regions
}

private enum SpeciesDictionaryCornerRadius {
    static let card: CGFloat = 16
    static let thumbnail: CGFloat = 12
    static let skeletonText: CGFloat = 6
    static let skeletonPill: CGFloat = 10
    static let chevronSkeleton: CGFloat = 4
}

struct SpeciesDictionaryCatalogView: View {
    let isSearchEnabled: Bool
    let isBottomSearchEnabled: Bool
    let showsNavigationTitle: Bool
    let navigationTitle: String
    let category: SpeciesDictionaryCatalogCategory
    let region: String?
    let group: String?
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
        isBottomSearchEnabled: Bool = false,
        showsNavigationTitle: Bool = true,
        navigationTitle: String = "Dictionary",
        category: SpeciesDictionaryCatalogCategory = .all,
        region: String? = nil,
        group: String? = nil,
        searchText: Binding<String>? = nil
    ) {
        self.isSearchEnabled = isSearchEnabled
        self.isBottomSearchEnabled = isBottomSearchEnabled
        self.showsNavigationTitle = showsNavigationTitle
        self.navigationTitle = navigationTitle
        self.category = category
        self.region = region
        self.group = group
        self.externalSearchText = searchText
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .modifier(SpeciesDictionaryCatalogTitleModifier(title: navigationTitle, isEnabled: showsNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SpeciesDictionaryCatalogSearchModifier(
            searchText: searchTextBinding,
            isEnabled: isSearchEnabled && externalSearchText == nil
        ))
        .modifier(SpeciesDictionaryBottomSearchModifier(
            searchText: searchTextBinding,
            isEnabled: isBottomSearchEnabled && externalSearchText == nil
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
                    SpeciesDictionaryCatalogRowSkeleton()
                    SpeciesDictionaryCatalogRowSkeleton()
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
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { _ in
                    SpeciesDictionaryCatalogRowSkeleton()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .accessibilityHidden(true)
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
                group: group,
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
                group: group,
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
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: userRegion ?? "") {
            await loadOverview()
        }
    }

    private func overviewContent(_ overview: SpeciesDictionaryOverview) -> some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 16
            let gridSpacing: CGFloat = 12
            let availableWidth = max(0, geometry.size.width - horizontalPadding * 2)
            let cardSize = floor((availableWidth - gridSpacing) / 2)
            let groupCardHeight = SpeciesDictionaryGroupCard.preferredHeight(for: cardSize)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let featuredSpecies = overview.featuredSpecies {
                        NavigationLink(value: featuredSpecies.dictionaryRoute) {
                            SpeciesDictionaryFeaturedSpeciesCard(
                                species: featuredSpecies,
                                width: availableWidth
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let regionCategory = category(.yourRegion, in: overview),
                       shouldShowRegionMapCard(for: regionCategory) {
                        NavigationLink(value: route(for: regionCategory)) {
                            SpeciesDictionaryRegionMapCard(
                                category: regionCategory,
                                width: availableWidth
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !overview.groups.isEmpty {
                        VStack(spacing: gridSpacing) {
                            ForEach(groupRowIndices(for: overview.groups), id: \.self) { rowIndex in
                                HStack(spacing: gridSpacing) {
                                    ForEach(0..<2, id: \.self) { columnIndex in
                                        let groupIndex = rowIndex * 2 + columnIndex
                                        if overview.groups.indices.contains(groupIndex) {
                                            let group = overview.groups[groupIndex]
                                            NavigationLink(
                                                value: SpeciesDictionaryCategoryRoute.group(
                                                    title: group.title,
                                                    group: group.id
                                                )
                                            ) {
                                                SpeciesDictionaryGroupCard(
                                                    group: group,
                                                    width: cardSize,
                                                    height: groupCardHeight
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            Color.clear
                                                .frame(width: cardSize, height: groupCardHeight)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    let visibleRegions = visibleRegions(in: overview)
                    if !visibleRegions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Regions")
                                .font(.headline)
                                .padding(.horizontal, 2)

                            NavigationLink(value: SpeciesDictionaryCategoryRoute.regions) {
                                SpeciesDictionaryRegionRow(
                                    title: "Browse all regions",
                                    count: visibleRegions.count,
                                    referenceImageUrl: visibleRegions.first?.referenceImageUrl,
                                    systemImage: "globe.americas"
                                )
                            }
                            .buttonStyle(.plain)

                            ForEach(visibleRegions) { region in
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

                    let bottomCategories = bottomOverviewCategories(for: overview)
                    if !bottomCategories.isEmpty {
                        ForEach(bottomCategories) { category in
                            NavigationLink(value: route(for: category)) {
                                SpeciesDictionaryOverviewRow(category: category)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .refreshable {
                await loadOverview()
            }
        }
    }

    private var loadingState: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 16
            let gridSpacing: CGFloat = 12
            let availableWidth = max(0, geometry.size.width - horizontalPadding * 2)
            let cardSize = floor((availableWidth - gridSpacing) / 2)
            let groupCardHeight = SpeciesDictionaryGroupCard.preferredHeight(for: cardSize)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SpeciesDictionaryFeaturedSkeletonCard(width: availableWidth)
                    SpeciesDictionaryMapSkeletonCard(width: availableWidth)

                    VStack(spacing: gridSpacing) {
                        ForEach(0..<2, id: \.self) { _ in
                            HStack(spacing: gridSpacing) {
                                SpeciesDictionaryGroupSkeletonCard(width: cardSize, height: groupCardHeight)
                                SpeciesDictionaryGroupSkeletonCard(width: cardSize, height: groupCardHeight)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SpeciesDictionarySkeletonBlock(
                            width: 92,
                            height: 20,
                            cornerRadius: SpeciesDictionaryCornerRadius.skeletonText
                        )
                            .padding(.horizontal, 2)

                        ForEach(0..<3, id: \.self) { _ in
                            SpeciesDictionaryOverviewRowSkeleton()
                        }
                    }

                    SpeciesDictionaryOverviewRowSkeleton()
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .accessibilityHidden(true)
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

    private var recentlyAddedRoute: SpeciesDictionaryCategoryRoute {
        .catalog(title: "Recently added", category: .recentlyAdded, region: nil)
    }

    private func category(
        _ id: SpeciesDictionaryOverviewCategoryID,
        in overview: SpeciesDictionaryOverview
    ) -> SpeciesDictionaryCategorySummary? {
        overview.categories.first { $0.id == id }
    }

    private func bottomOverviewCategories(
        for overview: SpeciesDictionaryOverview
    ) -> [SpeciesDictionaryCategorySummary] {
        [.recentlyAdded, .all].compactMap { category($0, in: overview) }
    }

    private func shouldShowRegionMapCard(
        for category: SpeciesDictionaryCategorySummary
    ) -> Bool {
        category.region?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
            && category.count >= 1
    }

    private func visibleRegions(in overview: SpeciesDictionaryOverview) -> [SpeciesDictionaryRegionSummary] {
        overview.regions.filter { region in
            region.count >= 1
                && region.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
        }
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
            return .catalog(title: "Your region", category: .region, region: region)
        case .taxonomy:
            return .taxonomy
        case .recentlyAdded:
            return .catalog(title: "Recently added", category: .recentlyAdded, region: nil)
        }
    }

    private func groupRowIndices(for groups: [SpeciesDictionaryGroupSummary]) -> Range<Int> {
        0..<Int(ceil(Double(groups.count) / 2.0))
    }
}

private struct SpeciesDictionaryFeaturedSpeciesCard: View {
    let species: SpeciesDictionaryFeaturedSpecies
    let width: CGFloat

    private var imageHeight: CGFloat {
        max(300, min(430, width * 0.96))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardImage
                .frame(width: width, height: imageHeight)
                .clipped()

            bottomTextFade

            badge

            titleOverlay
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous)
                .strokeBorder(.black.opacity(0.8), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        Text("Recently added")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.42), in: Capsule(style: .continuous))
            .padding(14)
    }

    private var bottomTextFade: some View {
        LinearGradient(
            colors: [
                .clear,
                .black.opacity(0.24),
                .black.opacity(0.72)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(species.commonName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 2)

            Text(species.scientificName)
                .font(.subheadline.italic())
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.24), radius: 6, x: 0, y: 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    @ViewBuilder
    private var cardImage: some View {
        if let referenceImageUrl = species.referenceImageUrl,
           let url = URL(string: referenceImageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: imageHeight)
                        .clipped()
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
            .frame(width: width, height: imageHeight)
            .overlay {
                Image(systemName: "leaf")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

private struct SpeciesDictionaryRegionMapCard: View {
    let category: SpeciesDictionaryCategorySummary
    let width: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var snapshotImage: UIImage?
    @State private var isLoadingSnapshot = false

    private var imageHeight: CGFloat {
        max(150, min(190, width * 0.44))
    }

    private var regionTitle: String {
        category.region?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? localeRegionTitle
            ?? Self.defaultFallbackRegionTitle
    }

    private var mapQuery: String {
        category.region?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? localeRegionTitle
            ?? Self.defaultFallbackRegionTitle
    }

    private var localeRegionTitle: String? {
        guard let regionIdentifier = Locale.current.region?.identifier else { return nil }
        return Locale.current.localizedString(forRegionCode: regionIdentifier)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private var snapshotTaskID: String {
        [
            mapQuery,
            "\(Int(width.rounded()))",
            colorScheme == .dark ? "dark" : "light"
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mapImage
                .frame(width: width, height: imageHeight)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text("Your Region")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(Capsule())

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(regionTitle)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text("\(category.count) species")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                if let subtitle = category.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .frame(width: width)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .task(id: snapshotTaskID) {
            await loadSnapshot()
        }
    }

    @ViewBuilder
    private var mapImage: some View {
        if let snapshotImage {
            Image(uiImage: snapshotImage)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                .overlay {
                    if !isLoadingSnapshot {
                        Image(systemName: "map")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    @MainActor
    private func loadSnapshot() async {
        isLoadingSnapshot = true
        let image = await Self.snapshotImage(
            for: mapQuery,
            width: width,
            height: imageHeight,
            colorScheme: colorScheme
        )
        guard !Task.isCancelled else { return }
        snapshotImage = image
        isLoadingSnapshot = false
    }

    private static func snapshotImage(
        for query: String,
        width: CGFloat,
        height: CGFloat,
        colorScheme: ColorScheme
    ) async -> UIImage? {
        let geocoder = CLGeocoder()
        let placemark = (try? await geocoder.geocodeAddressString(query))?.first
        let coordinate = placemark?.location?.coordinate

        let options = MKMapSnapshotter.Options()
        if let placemark, let coordinate {
            options.region = snapshotRegion(for: placemark, coordinate: coordinate)
        } else {
            options.region = defaultFallbackRegion
        }
        options.size = CGSize(width: max(width, 240), height: max(height, 140))
        options.scale = UIScreen.main.scale
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light
        )

        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { snapshot, _ in
                continuation.resume(returning: snapshot?.image)
            }
        }
    }

    private static func snapshotRegion(
        for placemark: CLPlacemark,
        coordinate: CLLocationCoordinate2D
    ) -> MKCoordinateRegion {
        let radius = (placemark.region as? CLCircularRegion)?.radius ?? 650_000
        let clampedRadius = min(max(radius, 80_000), 4_500_000)
        let latitudeDelta = min(max((clampedRadius / 111_000) * 2.2, 0.45), 60)
        let longitudeScale = max(cos(coordinate.latitude * .pi / 180), 0.24)
        let longitudeDelta = min(max(latitudeDelta / longitudeScale, 0.45), 80)

        return MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }

    private static let defaultFallbackRegionTitle = "United States"

    private static let defaultFallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
        span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 54)
    )
}

private struct SpeciesDictionaryOverviewRow: View {
    let category: SpeciesDictionaryCategorySummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.thumbnail, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))

                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(countLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var countLabel: String {
        switch category.id {
        case .recentlyAdded:
            "Newest \(category.count) species"
        default:
            "\(category.count) species"
        }
    }

    private var iconName: String {
        switch category.id {
        case .all: "book"
        case .taxonomy: "point.3.connected.trianglepath.dotted"
        case .yourRegion: "location"
        case .recentlyAdded: "sparkles"
        }
    }
}

private struct SpeciesDictionaryGroupCard: View {
    let group: SpeciesDictionaryGroupSummary
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            groupGraphic
                .frame(width: graphicSize, height: graphicSize)
                .padding(.top, topInset)

            VStack(spacing: 3) {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text("\(group.count) species discovered")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .frame(maxWidth: .infinity)
            .frame(height: textBandHeight, alignment: .top)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, bottomInset)
        .frame(width: width, height: height)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    static func preferredHeight(for width: CGFloat) -> CGFloat {
        topInset + min(width * 0.76, 138) + 6 + max(46, width * 0.28) + bottomInset
    }

    @ViewBuilder
    private var groupGraphic: some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.thumbnail, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }

    private var graphicSize: CGFloat {
        min(width * 0.76, 138)
    }

    private var textBandHeight: CGFloat {
        max(46, width * 0.28)
    }

    private var topInset: CGFloat {
        Self.topInset
    }

    private var bottomInset: CGFloat {
        Self.bottomInset
    }

    private var assetName: String? {
        switch group.id {
        case "plants": "fern"
        case "birds": "eagle"
        case "insects": "butterfly-monarch"
        case "fungi": "mushrooms"
        case "mammals": "squirrel"
        case "reptiles_amphibians": "turtle"
        default: nil
        }
    }

    private var iconName: String {
        switch group.id {
        case "plants": "leaf"
        case "birds": "bird"
        case "insects": "ladybug"
        case "fungi": "circle.hexagongrid"
        case "mammals": "pawprint"
        case "reptiles_amphibians": "lizard"
        default: "square.grid.2x2"
        }
    }

    private static let topInset: CGFloat = 10
    private static let bottomInset: CGFloat = 12
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
            RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous)
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
            .clipShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.thumbnail, style: .continuous))
        } else {
            placeholderThumbnail
                .frame(width: 48, height: 48)
        }
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.thumbnail, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .overlay {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
    }
}

private struct SpeciesDictionaryFeaturedSkeletonCard: View {
    let width: CGFloat

    private var imageHeight: CGFloat {
        max(300, min(430, width * 0.96))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpeciesDictionarySkeletonBlock(width: width, height: imageHeight, cornerRadius: 0)

            SpeciesDictionarySkeletonBlock(
                width: 104,
                height: 24,
                cornerRadius: SpeciesDictionaryCornerRadius.skeletonPill
            )
            .padding(14)

            VStack(alignment: .leading, spacing: 8) {
                SpeciesDictionarySkeletonBlock(width: width * 0.72, height: 24)
                SpeciesDictionarySkeletonBlock(width: width * 0.46, height: 16)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
    }
}

private struct SpeciesDictionaryMapSkeletonCard: View {
    let width: CGFloat

    private var imageHeight: CGFloat {
        max(150, min(190, width * 0.44))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpeciesDictionarySkeletonBlock(width: width, height: imageHeight, cornerRadius: 0)

            VStack(alignment: .leading, spacing: 8) {
                SpeciesDictionarySkeletonBlock(
                    width: 92,
                    height: 20,
                    cornerRadius: SpeciesDictionaryCornerRadius.skeletonPill
                )
                SpeciesDictionarySkeletonBlock(width: width * 0.46, height: 20)
                SpeciesDictionarySkeletonBlock(width: width * 0.28, height: 14)
                SpeciesDictionarySkeletonBlock(width: width * 0.72, height: 12)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .frame(width: width)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
    }
}

private struct SpeciesDictionaryGroupSkeletonCard: View {
    let width: CGFloat
    let height: CGFloat

    private var graphicSize: CGFloat {
        min(width * 0.76, 138)
    }

    var body: some View {
        VStack(spacing: 8) {
            SpeciesDictionarySkeletonBlock(
                width: graphicSize,
                height: graphicSize,
                cornerRadius: SpeciesDictionaryCornerRadius.thumbnail
            )
                .padding(.top, 10)

            VStack(spacing: 6) {
                SpeciesDictionarySkeletonBlock(width: width * 0.62, height: 14)
                SpeciesDictionarySkeletonBlock(width: width * 0.48, height: 11)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: width, height: height)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
    }
}

private struct SpeciesDictionaryOverviewRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            SpeciesDictionarySkeletonBlock(
                width: 52,
                height: 52,
                cornerRadius: SpeciesDictionaryCornerRadius.thumbnail
            )

            VStack(alignment: .leading, spacing: 7) {
                SpeciesDictionarySkeletonBlock(width: 144, height: 16)
                SpeciesDictionarySkeletonBlock(width: 76, height: 13)
            }

            Spacer(minLength: 8)

            SpeciesDictionarySkeletonBlock(
                width: 8,
                height: 18,
                cornerRadius: SpeciesDictionaryCornerRadius.chevronSkeleton
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous))
    }
}

private struct SpeciesDictionaryCatalogRowSkeleton: View {
    private let thumbnailSize: CGFloat = 88

    var body: some View {
        HStack(spacing: 12) {
            SpeciesDictionarySkeletonBlock(
                width: thumbnailSize,
                height: thumbnailSize,
                cornerRadius: SpeciesDictionaryCornerRadius.thumbnail
            )

            VStack(alignment: .leading, spacing: 8) {
                SpeciesDictionarySkeletonBlock(width: 150, height: 16)
                SpeciesDictionarySkeletonBlock(width: 122, height: 12)
                SpeciesDictionarySkeletonBlock(width: 94, height: 10)
            }

            Spacer(minLength: 8)

            SpeciesDictionarySkeletonBlock(
                width: 8,
                height: 18,
                cornerRadius: SpeciesDictionaryCornerRadius.chevronSkeleton
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct SpeciesDictionarySkeletonBlock: View {
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = SpeciesDictionaryCornerRadius.skeletonText

    var body: some View {
        GlowPulsingSkeletonView(cornerRadius: cornerRadius)
            .frame(width: width, height: height)
    }
}

struct SpeciesDictionaryRegionsView: View {
    let userRegion: String?

    @State private var overview: SpeciesDictionaryOverview?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            Group {
                if isLoading && overview == nil {
                    regionLoadingState
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
                    let visibleRegions = visibleRegions(in: overview)
                    if visibleRegions.isEmpty {
                        emptyState
                    } else {
                        regionList(visibleRegions)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Regions")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: userRegion ?? "") {
            await loadOverview()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No regions found",
            systemImage: "map",
            description: Text("Region browsing will appear when dictionary records include native-region data.")
        )
    }

    private var regionLoadingState: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { _ in
                    SpeciesDictionaryOverviewRowSkeleton()
                }
            }
            .padding(16)
        }
        .accessibilityHidden(true)
    }

    private func regionList(_ regions: [SpeciesDictionaryRegionSummary]) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(regions) { region in
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

    private func visibleRegions(in overview: SpeciesDictionaryOverview) -> [SpeciesDictionaryRegionSummary] {
        overview.regions.filter { region in
            region.count >= 1
                && region.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
        }
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
            RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.card, style: .continuous)
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
            .clipShape(RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.thumbnail, style: .continuous))
        } else {
            placeholderThumbnail
                .frame(width: thumbnailSize, height: thumbnailSize)
        }
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: SpeciesDictionaryCornerRadius.thumbnail, style: .continuous)
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

private struct SpeciesDictionaryBottomSearchModifier: ViewModifier {
    @Binding var searchText: String
    let isEnabled: Bool
    @State private var isSearchPresented = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .toolbar,
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
