import SwiftUI

struct SpeciesDictionaryCatalogView: View {
    let isSearchEnabled: Bool
    let showsNavigationTitle: Bool
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
        searchText: Binding<String>? = nil
    ) {
        self.isSearchEnabled = isSearchEnabled
        self.showsNavigationTitle = showsNavigationTitle
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
        .modifier(SpeciesDictionaryCatalogTitleModifier(isEnabled: showsNavigationTitle))
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

private struct SpeciesDictionaryCatalogRow: View {
    let item: SpeciesDictionaryCatalogItem

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
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholderThumbnail
                .frame(width: 58, height: 58)
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
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationTitle("Dictionary")
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
