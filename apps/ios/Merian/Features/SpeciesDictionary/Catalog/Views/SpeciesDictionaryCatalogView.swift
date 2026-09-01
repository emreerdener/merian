import SwiftUI

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
    @State private var viewModel = SpeciesDictionaryCatalogViewModel()

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
                if viewModel.isLoadingInitial && viewModel.items.isEmpty {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage,
                          viewModel.items.isEmpty {
                    errorState(message: errorMessage)
                } else if viewModel.items.isEmpty {
                    emptyState
                } else {
                    catalogList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .modifier(
            SpeciesDictionaryCatalogTitleModifier(
                title: navigationTitle,
                isEnabled: showsNavigationTitle
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .modifier(
            SpeciesDictionaryCatalogSearchModifier(
                searchText: searchTextBinding,
                isEnabled: isSearchEnabled && externalSearchText == nil
            )
        )
        .modifier(
            SpeciesDictionaryBottomSearchModifier(
                searchText: searchTextBinding,
                isEnabled: isBottomSearchEnabled && externalSearchText == nil
            )
        )
        .task {
            await viewModel.loadIfNeeded(for: catalogSelection)
        }
        .task(id: catalogSelection) {
            let selection = catalogSelection
            viewModel.updateSelection(selection)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await viewModel.loadIfNeeded(for: selection)
        }
    }

    private var catalogList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.items) { item in
                    NavigationLink(value: item.dictionaryRoute) {
                        SpeciesDictionaryCatalogRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        guard item.id == viewModel.items.last?.id else { return }
                        Task { await viewModel.loadMore() }
                    }
                }

                if viewModel.isLoadingMore {
                    SpeciesDictionaryCatalogRowSkeleton()
                    SpeciesDictionaryCatalogRowSkeleton()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable {
            await reload()
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
            Label(
                "Dictionary unavailable",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await reload() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func reload() async {
        await viewModel.reload(for: catalogSelection)
    }

    private var catalogSelection: SpeciesDictionaryCatalogSelection {
        SpeciesDictionaryCatalogSelection(
            category: category,
            region: region,
            group: group,
            query: activeSearchText
        )
    }

    private var activeSearchText: String {
        searchTextBinding.wrappedValue
    }

    private var searchTextBinding: Binding<String> {
        externalSearchText ?? $localSearchText
    }
}
