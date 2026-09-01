import XCTest

@testable import Merian

@MainActor
final class SpeciesDictionaryPageViewModelTests: XCTestCase {
    private static let speciesID =
        "1cf79982-e5ee-4e3d-8d65-274527e6ae01"

    private enum StubError: Error, Equatable {
        case missing
        case failed
    }

    func testLoadNormalizesRequestPublishesSpeciesAndTracksOnce() async {
        let species = Self.entry()
        var capturedRequest: SpeciesDictionaryDetailRequest?
        var events: [SpeciesDictionaryDetailTelemetryEvent] = []
        let viewModel = SpeciesDictionaryPageViewModel(
            scientificName: "  Testus floridus  ",
            speciesId: "  \(Self.speciesID.uppercased())  ",
            entryPoint: .search,
            dependencies: .init(
                loadSpecies: { request in
                    capturedRequest = request
                    return species
                },
                classifyLoadError: { _ in .message("Unexpected error") },
                track: { events.append($0) }
            )
        )

        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(capturedRequest, SpeciesDictionaryDetailRequest(
            speciesId: Self.speciesID,
            scientificName: "Testus floridus"
        ))
        XCTAssertEqual(viewModel.state, .loaded(species))
        XCTAssertEqual(events.filter {
            if case .opened = $0 { return true }
            return false
        }.count, 1)
        XCTAssertEqual(events.filter {
            if case .loaded = $0 { return true }
            return false
        }.count, 2)
        XCTAssertTrue(events.contains(.loaded(
            entryPoint: SpeciesDictionaryEntryPoint.search.rawValue,
            contentQuality: SpeciesDictionaryContentQuality.complete.rawValue
        )))
    }

    func testEmptyIdentityPublishesNotFoundWithoutCallingEndpoint() async {
        var loadCount = 0
        var events: [SpeciesDictionaryDetailTelemetryEvent] = []
        let viewModel = SpeciesDictionaryPageViewModel(
            scientificName: "   ",
            speciesId: "  ",
            entryPoint: .deepLink,
            dependencies: .init(
                loadSpecies: { _ in
                    loadCount += 1
                    throw StubError.failed
                },
                classifyLoadError: { _ in .message("Load failed") },
                track: { events.append($0) }
            )
        )

        await viewModel.load()

        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(viewModel.state, .notFound)
        XCTAssertEqual(events, [
            .opened(entryPoint: SpeciesDictionaryEntryPoint.deepLink.rawValue),
            .notFound(entryPoint: SpeciesDictionaryEntryPoint.deepLink.rawValue)
        ])
    }

    func testMalformedIDFallsBackToNormalizedScientificName() async {
        var capturedRequest: SpeciesDictionaryDetailRequest?
        let viewModel = SpeciesDictionaryPageViewModel(
            scientificName: "  Testus   floridus  ",
            speciesId: "external:testus%20floridus",
            dependencies: .init(
                loadSpecies: { request in
                    capturedRequest = request
                    return Self.entry()
                },
                classifyLoadError: { _ in .message("Unexpected error") },
                track: { _ in }
            )
        )

        await viewModel.load()

        XCTAssertEqual(capturedRequest, SpeciesDictionaryDetailRequest(
            speciesId: nil,
            scientificName: "Testus floridus"
        ))
        XCTAssertNil(viewModel.speciesId)
    }

    func testLoadUsesInjectedErrorClassification() async {
        var shouldReturnNotFound = true
        let viewModel = SpeciesDictionaryPageViewModel(
            scientificName: "Missing species",
            dependencies: .init(
                loadSpecies: { _ in
                    throw shouldReturnNotFound
                        ? StubError.missing
                        : StubError.failed
                },
                classifyLoadError: { error in
                    if error as? StubError == .missing {
                        return .notFound
                    }
                    return .message("Readable failure")
                },
                track: { _ in }
            )
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .notFound)

        shouldReturnNotFound = false
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .error("Readable failure"))
    }

    func testRetryTracksActionAndReloads() async {
        let species = Self.entry()
        var loadCount = 0
        var events: [SpeciesDictionaryDetailTelemetryEvent] = []
        let viewModel = SpeciesDictionaryPageViewModel(
            scientificName: species.scientificName,
            entryPoint: .web,
            dependencies: .init(
                loadSpecies: { _ in
                    loadCount += 1
                    return species
                },
                classifyLoadError: { _ in .message("Unexpected error") },
                track: { events.append($0) }
            )
        )

        await viewModel.retry()

        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(viewModel.state, .loaded(species))
        XCTAssertEqual(events.first, .retry(
            entryPoint: SpeciesDictionaryEntryPoint.web.rawValue
        ))
        XCTAssertEqual(events.filter {
            if case .opened = $0 { return true }
            return false
        }.count, 1)
    }

    func testLateLoadCannotOverwriteNewerResult() async {
        let stale = Self.entry(id: "stale", commonName: "Stale")
        let fresh = Self.entry(id: "fresh", commonName: "Fresh")
        let firstLoadStarted = expectation(
            description: "First species detail load started"
        )
        var loadCount = 0
        var pendingFirstLoad: CheckedContinuation<
            SpeciesDictionaryEntry,
            any Error
        >?
        var events: [SpeciesDictionaryDetailTelemetryEvent] = []
        let viewModel = SpeciesDictionaryPageViewModel(
            scientificName: fresh.scientificName,
            dependencies: .init(
                loadSpecies: { _ in
                    loadCount += 1
                    if loadCount == 1 {
                        return try await withCheckedThrowingContinuation {
                            pendingFirstLoad = $0
                            firstLoadStarted.fulfill()
                        }
                    }
                    return fresh
                },
                classifyLoadError: { _ in .message("Unexpected error") },
                track: { events.append($0) }
            )
        )

        let staleTask = Task { await viewModel.load() }
        await fulfillment(of: [firstLoadStarted], timeout: 1)
        await viewModel.load()
        pendingFirstLoad?.resume(returning: stale)
        _ = await staleTask.value

        XCTAssertEqual(viewModel.state, .loaded(fresh))
        XCTAssertEqual(events.filter {
            if case .loaded = $0 { return true }
            return false
        }.count, 1)
    }

    func testLateFailureCannotOverwriteNewerResult() async {
        let fresh = Self.entry(id: "fresh", commonName: "Fresh")
        let firstLoadStarted = expectation(
            description: "First species detail load started"
        )
        var loadCount = 0
        var pendingFirstLoad: CheckedContinuation<
            SpeciesDictionaryEntry,
            any Error
        >?
        let viewModel = SpeciesDictionaryPageViewModel(
            scientificName: fresh.scientificName,
            dependencies: .init(
                loadSpecies: { _ in
                    loadCount += 1
                    if loadCount == 1 {
                        return try await withCheckedThrowingContinuation {
                            pendingFirstLoad = $0
                            firstLoadStarted.fulfill()
                        }
                    }
                    return fresh
                },
                classifyLoadError: { _ in .message("Stale failure") },
                track: { _ in }
            )
        )

        let staleTask = Task { await viewModel.load() }
        await fulfillment(of: [firstLoadStarted], timeout: 1)
        await viewModel.load()
        pendingFirstLoad?.resume(throwing: StubError.failed)
        _ = await staleTask.value

        XCTAssertEqual(viewModel.state, .loaded(fresh))
    }

    private static func entry(
        id: String = "species-123",
        commonName: String = "Field Test"
    ) -> SpeciesDictionaryEntry {
        SpeciesDictionaryEntry(
            id: id,
            scientificName: "Testus floridus",
            commonName: commonName,
            contentQuality: .complete,
            alternativeCommonNames: [],
            taxonomy: nil,
            hazardType: "none",
            iucnRedListStatus: nil,
            wikipediaUrl: nil,
            wikipediaOverview: nil,
            habitatDescription: nil,
            gbifTaxonKey: nil,
            groupTags: [],
            referenceImages: [],
            similarSpecies: []
        )
    }
}
