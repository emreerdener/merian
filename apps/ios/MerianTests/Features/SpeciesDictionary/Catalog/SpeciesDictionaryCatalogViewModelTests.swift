import XCTest

@testable import Merian

@MainActor
final class SpeciesDictionaryCatalogViewModelTests: XCTestCase {
    private enum StubError: Error {
        case expected
    }

    func testInitialLoadNormalizesRequestAndPublishesPage() async throws {
        let item = Self.catalogItem(id: "monarch")
        let cursor = SpeciesDictionaryCatalogCursor(
            scientificName: item.scientificName,
            speciesId: item.id
        )
        var capturedRequest: SpeciesDictionaryCatalogPageRequest?
        let viewModel = SpeciesDictionaryCatalogViewModel(
            pageLimit: 2,
            dependencies: .init(
                loadPage: { request in
                    capturedRequest = request
                    return Self.catalogResponse(
                        items: [item],
                        nextCursor: cursor
                    )
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.loadIfNeeded(
            category: .group,
            region: "  ",
            group: " birds ",
            query: " Danaus "
        )

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.category, .group)
        XCTAssertNil(request.region)
        XCTAssertEqual(request.group, "birds")
        XCTAssertEqual(request.query, "Danaus")
        XCTAssertEqual(request.limit, 2)
        XCTAssertNil(request.cursor)
        XCTAssertEqual(viewModel.items, [item])
        XCTAssertEqual(viewModel.nextCursor, cursor)
        XCTAssertFalse(viewModel.isLoadingInitial)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testIdenticalInitialIdentityIsLoadedOnlyOnce() async {
        var loadCount = 0
        let viewModel = SpeciesDictionaryCatalogViewModel(
            dependencies: .init(
                loadPage: { _ in
                    loadCount += 1
                    return Self.catalogResponse(items: [])
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: ""
        )
        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: "  "
        )

        XCTAssertEqual(loadCount, 1)
    }

    func testInitialFailureCanRetryTheSameIdentity() async {
        let item = Self.catalogItem(id: "recovered")
        var shouldFail = true
        var loadCount = 0
        let viewModel = SpeciesDictionaryCatalogViewModel(
            dependencies: .init(
                loadPage: { _ in
                    loadCount += 1
                    if shouldFail {
                        throw StubError.expected
                    }
                    return Self.catalogResponse(items: [item])
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: nil
        )

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Expected error")

        shouldFail = false
        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: nil
        )

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(viewModel.items, [item])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoadingInitial)
    }

    func testPaginationUsesCursorAndAppendsPage() async {
        let first = Self.catalogItem(id: "first")
        let second = Self.catalogItem(id: "second")
        let cursor = SpeciesDictionaryCatalogCursor(
            scientificName: first.scientificName,
            speciesId: first.id
        )
        var requests: [SpeciesDictionaryCatalogPageRequest] = []
        let viewModel = SpeciesDictionaryCatalogViewModel(
            pageLimit: 1,
            dependencies: .init(
                loadPage: { request in
                    requests.append(request)
                    if request.cursor == nil {
                        return Self.catalogResponse(
                            items: [first],
                            nextCursor: cursor
                        )
                    }
                    return Self.catalogResponse(items: [second])
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.loadIfNeeded(
            category: .region,
            region: "US",
            group: nil,
            query: nil
        )
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.items, [first, second])
        XCTAssertNil(viewModel.nextCursor)
        XCTAssertEqual(requests.map(\.cursor), [nil, cursor])
        XCTAssertTrue(requests.allSatisfy { $0.region == "US" })
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testPaginationFailurePreservesItemsAndCursorForRetry() async {
        let item = Self.catalogItem(id: "existing")
        let recovered = Self.catalogItem(id: "recovered")
        let cursor = SpeciesDictionaryCatalogCursor(
            scientificName: item.scientificName,
            speciesId: item.id
        )
        var shouldFailPagination = true
        let viewModel = SpeciesDictionaryCatalogViewModel(
            dependencies: .init(
                loadPage: { request in
                    if request.cursor != nil {
                        if shouldFailPagination {
                            throw StubError.expected
                        }
                        return Self.catalogResponse(items: [recovered])
                    }
                    return Self.catalogResponse(
                        items: [item],
                        nextCursor: cursor
                    )
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: nil
        )
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.items, [item])
        XCTAssertEqual(viewModel.nextCursor, cursor)
        XCTAssertEqual(viewModel.errorMessage, "Expected error")
        XCTAssertFalse(viewModel.isLoadingMore)

        shouldFailPagination = false
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.items, [item, recovered])
        XCTAssertNil(viewModel.nextCursor)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testRefreshSupersedesPaginationAndDiscardsStalePage() async {
        let first = Self.catalogItem(id: "first")
        let stale = Self.catalogItem(id: "stale")
        let refreshed = Self.catalogItem(id: "refreshed")
        let cursor = SpeciesDictionaryCatalogCursor(
            scientificName: first.scientificName,
            speciesId: first.id
        )
        let paginationStarted = expectation(
            description: "Catalog pagination started"
        )
        var initialLoadCount = 0
        var pendingPagination: CheckedContinuation<
            SpeciesDictionaryCatalogResponse,
            any Error
        >?
        let viewModel = SpeciesDictionaryCatalogViewModel(
            dependencies: .init(
                loadPage: { request in
                    if request.cursor != nil {
                        return try await withCheckedThrowingContinuation {
                            pendingPagination = $0
                            paginationStarted.fulfill()
                        }
                    }

                    initialLoadCount += 1
                    return Self.catalogResponse(
                        items: initialLoadCount == 1 ? [first] : [refreshed],
                        nextCursor: initialLoadCount == 1 ? cursor : nil
                    )
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: nil
        )
        let paginationTask = Task { await viewModel.loadMore() }
        await fulfillment(of: [paginationStarted], timeout: 1)

        await viewModel.reload(
            category: .all,
            region: nil,
            group: nil,
            query: nil
        )
        pendingPagination?.resume(
            returning: Self.catalogResponse(items: [stale])
        )
        _ = await paginationTask.value

        XCTAssertEqual(initialLoadCount, 2)
        XCTAssertEqual(viewModel.items, [refreshed])
        XCTAssertFalse(viewModel.isLoadingInitial)
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testNewSearchRejectsPriorQueryCompletion() async {
        let stale = Self.catalogItem(id: "stale")
        let current = Self.catalogItem(id: "current")
        let staleLoadStarted = expectation(description: "Old search started")
        var pendingStaleLoad: CheckedContinuation<
            SpeciesDictionaryCatalogResponse,
            any Error
        >?
        let viewModel = SpeciesDictionaryCatalogViewModel(
            dependencies: .init(
                loadPage: { request in
                    if request.query == "old" {
                        return try await withCheckedThrowingContinuation {
                            pendingStaleLoad = $0
                            staleLoadStarted.fulfill()
                        }
                    }
                    return Self.catalogResponse(items: [current])
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        let staleTask = Task {
            await viewModel.loadIfNeeded(
                category: .all,
                region: nil,
                group: nil,
                query: "old"
            )
        }
        await fulfillment(of: [staleLoadStarted], timeout: 1)

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: "current"
        )
        pendingStaleLoad?.resume(
            returning: Self.catalogResponse(items: [stale])
        )
        _ = await staleTask.value

        XCTAssertEqual(viewModel.items, [current])
        XCTAssertFalse(viewModel.isLoadingInitial)
    }

    func testReturningToLoadedSelectionRejectsActiveRefreshCompletion() async {
        let loaded = Self.catalogItem(id: "loaded")
        let stale = Self.catalogItem(id: "stale")
        let refreshStarted = expectation(
            description: "Replacement refresh started"
        )
        var pendingRefresh: CheckedContinuation<
            SpeciesDictionaryCatalogResponse,
            any Error
        >?
        let viewModel = SpeciesDictionaryCatalogViewModel(
            dependencies: .init(
                loadPage: { request in
                    if request.query == "replacement" {
                        return try await withCheckedThrowingContinuation {
                            pendingRefresh = $0
                            refreshStarted.fulfill()
                        }
                    }
                    return Self.catalogResponse(items: [loaded])
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: "loaded"
        )
        let refreshTask = Task {
            await viewModel.reload(
                category: .all,
                region: nil,
                group: nil,
                query: "replacement"
            )
        }
        await fulfillment(of: [refreshStarted], timeout: 1)

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: "loaded"
        )
        pendingRefresh?.resume(
            returning: Self.catalogResponse(items: [stale])
        )
        _ = await refreshTask.value

        XCTAssertEqual(viewModel.items, [loaded])
        XCTAssertFalse(viewModel.isLoadingInitial)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFailedReplacementCannotPaginateRetainedSelection() async {
        let loaded = Self.catalogItem(id: "loaded")
        let paginated = Self.catalogItem(id: "paginated")
        let cursor = SpeciesDictionaryCatalogCursor(
            scientificName: loaded.scientificName,
            speciesId: loaded.id
        )
        var paginationCount = 0
        let viewModel = SpeciesDictionaryCatalogViewModel(
            dependencies: .init(
                loadPage: { request in
                    if request.cursor != nil {
                        paginationCount += 1
                        return Self.catalogResponse(items: [paginated])
                    }
                    if request.query == "replacement" {
                        throw StubError.expected
                    }
                    return Self.catalogResponse(
                        items: [loaded],
                        nextCursor: cursor
                    )
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: "loaded"
        )
        await viewModel.reload(
            category: .all,
            region: nil,
            group: nil,
            query: "replacement"
        )
        await viewModel.loadMore()

        XCTAssertEqual(paginationCount, 0)
        XCTAssertEqual(viewModel.items, [loaded])
        XCTAssertEqual(viewModel.nextCursor, cursor)
        XCTAssertEqual(viewModel.errorMessage, "Expected error")

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: "loaded"
        )
        await viewModel.loadMore()

        XCTAssertEqual(paginationCount, 1)
        XCTAssertEqual(viewModel.items, [loaded, paginated])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSelectionChangeFencesActivePaginationBeforeDebounce() async {
        let loaded = Self.catalogItem(id: "loaded")
        let stale = Self.catalogItem(id: "stale")
        let cursor = SpeciesDictionaryCatalogCursor(
            scientificName: loaded.scientificName,
            speciesId: loaded.id
        )
        let paginationStarted = expectation(
            description: "Catalog pagination started"
        )
        var pendingPagination: CheckedContinuation<
            SpeciesDictionaryCatalogResponse,
            any Error
        >?
        let viewModel = SpeciesDictionaryCatalogViewModel(
            dependencies: .init(
                loadPage: { request in
                    if request.cursor != nil {
                        return try await withCheckedThrowingContinuation {
                            pendingPagination = $0
                            paginationStarted.fulfill()
                        }
                    }
                    return Self.catalogResponse(
                        items: [loaded],
                        nextCursor: cursor
                    )
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: "loaded"
        )
        let paginationTask = Task { await viewModel.loadMore() }
        await fulfillment(of: [paginationStarted], timeout: 1)

        viewModel.updateSelection(
            SpeciesDictionaryCatalogSelection(
                category: .all,
                region: nil,
                group: nil,
                query: "replacement"
            )
        )
        pendingPagination?.resume(
            returning: Self.catalogResponse(items: [stale])
        )
        _ = await paginationTask.value

        XCTAssertEqual(viewModel.items, [loaded])
        XCTAssertEqual(viewModel.nextCursor, cursor)
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testRefreshFailureKeepsLoadedCatalogUsable() async {
        let item = Self.catalogItem(id: "existing")
        var shouldFail = false
        let viewModel = SpeciesDictionaryCatalogViewModel(
            dependencies: .init(
                loadPage: { _ in
                    if shouldFail {
                        throw StubError.expected
                    }
                    return Self.catalogResponse(items: [item])
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.loadIfNeeded(
            category: .all,
            region: nil,
            group: nil,
            query: nil
        )
        shouldFail = true
        await viewModel.reload(
            category: .all,
            region: nil,
            group: nil,
            query: nil
        )

        XCTAssertEqual(viewModel.items, [item])
        XCTAssertEqual(viewModel.errorMessage, "Expected error")
        XCTAssertFalse(viewModel.isLoadingInitial)
    }

    private static func catalogItem(
        id: String
    ) -> SpeciesDictionaryCatalogItem {
        SpeciesDictionaryCatalogItem(
            id: id,
            scientificName: "Species \(id)",
            commonName: "Common \(id)",
            contentQuality: .complete,
            taxonomy: nil,
            iucnRedListStatus: nil,
            hazardType: nil,
            groupTags: [],
            referenceImageUrl: nil
        )
    }

    private static func catalogResponse(
        items: [SpeciesDictionaryCatalogItem],
        nextCursor: SpeciesDictionaryCatalogCursor? = nil
    ) -> SpeciesDictionaryCatalogResponse {
        SpeciesDictionaryCatalogResponse(
            schemaVersion: 1,
            data: items,
            nextCursor: nextCursor
        )
    }

}
