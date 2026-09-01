import Observation

@MainActor
@Observable
final class SpeciesDictionaryCatalogViewModel {
    struct Dependencies {
        let loadPage: @MainActor (
            SpeciesDictionaryCatalogPageRequest
        ) async throws -> SpeciesDictionaryCatalogResponse
        let errorMessage: @MainActor (any Error) -> String
    }

    private(set) var items: [SpeciesDictionaryCatalogItem] = []
    private(set) var nextCursor: SpeciesDictionaryCatalogCursor?
    private(set) var isLoadingInitial = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let pageLimit: Int
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var requestedSelection:
        SpeciesDictionaryCatalogSelection?
    @ObservationIgnored private var loadedSelection:
        SpeciesDictionaryCatalogSelection?
    @ObservationIgnored private var activeInitialSelection:
        SpeciesDictionaryCatalogSelection?

    init(
        pageLimit: Int = 40,
        dependencies: Dependencies = .live
    ) {
        self.pageLimit = pageLimit
        self.dependencies = dependencies
    }

    func loadIfNeeded(
        category: SpeciesDictionaryCatalogCategory,
        region: String?,
        group: String?,
        query: String?
    ) async {
        await loadIfNeeded(
            for: SpeciesDictionaryCatalogSelection(
                category: category,
                region: region,
                group: group,
                query: query
            )
        )
    }

    func loadIfNeeded(
        for selection: SpeciesDictionaryCatalogSelection
    ) async {
        updateSelection(selection)
        guard loadedSelection != selection,
              activeInitialSelection != selection
        else {
            return
        }

        await loadInitial(
            request: firstPageRequest(for: selection),
            selection: selection
        )
    }

    func reload(
        category: SpeciesDictionaryCatalogCategory,
        region: String?,
        group: String?,
        query: String?
    ) async {
        await reload(
            for: SpeciesDictionaryCatalogSelection(
                category: category,
                region: region,
                group: group,
                query: query
            )
        )
    }

    func reload(for selection: SpeciesDictionaryCatalogSelection) async {
        updateSelection(selection)
        await loadInitial(
            request: firstPageRequest(for: selection),
            selection: selection
        )
    }

    func updateSelection(
        _ selection: SpeciesDictionaryCatalogSelection
    ) {
        guard requestedSelection != selection else { return }

        requestedSelection = selection
        requestGeneration += 1
        activeInitialSelection = nil
        isLoadingInitial = loadedSelection != selection && items.isEmpty
        isLoadingMore = false
        errorMessage = nil
    }

    func loadMore() async {
        guard !isLoadingInitial,
              !isLoadingMore,
              let selection = loadedSelection,
              requestedSelection == selection,
              let nextCursor
        else {
            return
        }

        let generation = requestGeneration
        isLoadingMore = true
        errorMessage = nil
        defer {
            if requestGeneration == generation {
                isLoadingMore = false
            }
        }

        do {
            let response = try await dependencies.loadPage(
                SpeciesDictionaryCatalogPageRequest(
                    selection: selection,
                    limit: pageLimit,
                    cursor: nextCursor
                )
            )
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  loadedSelection == selection,
                  requestedSelection == selection
            else {
                return
            }

            items.append(contentsOf: response.data)
            self.nextCursor = response.nextCursor
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  loadedSelection == selection,
                  requestedSelection == selection
            else {
                return
            }
            errorMessage = dependencies.errorMessage(error)
        }
    }

    private func loadInitial(
        request: SpeciesDictionaryCatalogPageRequest,
        selection: SpeciesDictionaryCatalogSelection
    ) async {
        requestGeneration += 1
        let generation = requestGeneration
        activeInitialSelection = selection
        isLoadingInitial = true
        isLoadingMore = false
        errorMessage = nil

        defer {
            if requestGeneration == generation {
                isLoadingInitial = false
                activeInitialSelection = nil
            }
        }

        do {
            let response = try await dependencies.loadPage(request)
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  requestedSelection == selection,
                  activeInitialSelection == selection
            else {
                return
            }

            items = response.data
            nextCursor = response.nextCursor
            loadedSelection = selection
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  requestedSelection == selection,
                  activeInitialSelection == selection
            else {
                return
            }
            errorMessage = dependencies.errorMessage(error)
        }
    }

    private func firstPageRequest(
        for selection: SpeciesDictionaryCatalogSelection
    ) -> SpeciesDictionaryCatalogPageRequest {
        SpeciesDictionaryCatalogPageRequest(
            selection: selection,
            limit: pageLimit
        )
    }
}
