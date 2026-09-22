import SwiftUI
import XCTest

@testable import Merian

@MainActor
final class SpeciesSearchViewModelTests: XCTestCase {
    private let context = SpeciesSearchContext(query: "orange black butterfly", group: .insects, media: nil, mode: .description)
    private enum Failure: Error { case expected }
    func testInitialPresentationRegistersRetainedSightings() {
        let feed = ExploreFeedViewModel(dependencies: ExploreFeedTestFixtures.dependencies())
        let post = ExploreFeedTestFixtures.post(id: "retained")
        SpeciesSearchSightings.register([post], previous: [post], in: feed)
        XCTAssertNotNil(feed.post(id: post.id))
    }

    func testPaginationAndLateResponsesDoNotRestoreRemovedSightings() {
        let feed = ExploreFeedViewModel(dependencies: ExploreFeedTestFixtures.dependencies())
        let removed = ExploreFeedTestFixtures.post(id: "removed")
        let next = ExploreFeedTestFixtures.post(id: "next")
        SpeciesSearchSightings.register([removed], previous: [], in: feed)
        XCTAssertNotNil(feed.post(id: removed.id))
        feed.removePost(id: removed.id)
        SpeciesSearchSightings.register([removed, next], previous: [removed], in: feed)
        XCTAssertNil(feed.post(id: removed.id))
        XCTAssertNotNil(feed.post(id: next.id))
        SpeciesSearchSightings.register([removed], previous: [], in: feed)
        XCTAssertNil(feed.post(id: removed.id))
    }
    private func response(_ request: SpeciesSearchRequest, context: SpeciesSearchContext? = nil,
                          status: SpeciesSearchResponse.Status = .results, message: String = "Butterflies") -> SpeciesSearchResponse {
        SpeciesSearchResponse(schemaVersion: 1, requestId: request.requestId, resultKind: request.resultKind,
                              status: status, message: message, context: context ?? self.context,
                              species: [], sightings: [], nextCursor: nil)
    }
    func testLateSightingsCannotRestoreUnseenPostsFromBlockedAuthor() async {
        let feed = ExploreFeedViewModel(dependencies: ExploreFeedTestFixtures.dependencies())
        let blocked = ExploreFeedTestFixtures.post(id: "unseen", authorUserId: "blocked-author")
        let allowed = ExploreFeedTestFixtures.post(id: "allowed", authorUserId: "other-author")
        var continuation: CheckedContinuation<SpeciesSearchResponse, Error>?
        var pending: SpeciesSearchRequest?
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            if request.resultKind == .species { return self.response(request) }
            pending = request
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }, errorMessage: { _ in "Failed" }))
        model.submit("Butterflies")
        let work = Task { await model.execute() }
        while continuation == nil { await Task.yield() }
        feed.removePosts(byAuthorUserId: blocked.authorUserId)
        continuation?.resume(returning: .init(schemaVersion: 1, requestId: pending!.requestId, resultKind: .sightings,
            status: .results, message: "Butterflies", context: context, species: [], sightings: [blocked, allowed], nextCursor: nil))
        await work.value
        SpeciesSearchSightings.register(model.sightings, previous: [], in: feed)
        XCTAssertNil(feed.post(id: blocked.id))
        XCTAssertFalse(SpeciesSearchSightings.canSurface(blocked, in: feed))
        XCTAssertNotNil(feed.post(id: allowed.id))
    }
    func testFollowupLoadsBothSectionsWithOneQuestion() async throws {
        var requests: [SpeciesSearchRequest] = []
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            requests.append(request)
            return self.response(request)
        }, errorMessage: { _ in "Failed" }))
        model.submit("Orange and black insects")
        await model.execute()
        XCTAssertEqual(model.context, context)
        XCTAssertEqual(model.draft, "")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.resultKind, .species)
        XCTAssertNil(requests.last?.question)
        XCTAssertEqual(requests.last?.resultKind, .sightings)
        model.submit("Only butterflies")
        await model.execute()
        XCTAssertEqual(requests.last?.context, context)
        XCTAssertEqual(requests[2].question, "Only butterflies")
        XCTAssertEqual(requests[2].resultKind, .species)
        XCTAssertNil(requests[3].question)
        XCTAssertEqual(requests[3].resultKind, .sightings)
    }
    func testNewSearchInvalidatesSuspendedResponseAndResetsSession() async {
        var continuation: CheckedContinuation<SpeciesSearchResponse, Error>?
        var pending: SpeciesSearchRequest?
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            pending = request
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }, errorMessage: { _ in "Failed" }))
        model.submit("butterflies")
        let work = Task { await model.execute() }
        while continuation == nil { await Task.yield() }
        model.newSearch()
        continuation?.resume(returning: response(pending!))
        await work.value
        XCTAssertNil(model.context)
        XCTAssertNil(model.request)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertFalse(model.hasLoaded(.species))
        XCTAssertFalse(model.hasLoaded(.sightings))
    }
    func testOlderRequestCannotOverwriteNewerResults() async {
        var continuation: CheckedContinuation<SpeciesSearchResponse, Error>?
        var first: SpeciesSearchRequest?
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            if request.question == "old" {
                first = request
                return try await withCheckedThrowingContinuation { continuation = $0 }
            }
            return self.response(request, message: "Newest")
        }, errorMessage: { _ in "Failed" }))
        model.submit("old")
        let work = Task { await model.execute() }
        while continuation == nil { await Task.yield() }
        model.submit("new")
        await model.execute()
        continuation?.resume(returning: response(first!, message: "Old"))
        await work.value
        XCTAssertEqual(model.interpretation, "Newest")
    }
    func testFailedReplacementKeepsDraftResultsAndDisablesPagination() async {
        var shouldFail = false
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            if shouldFail { throw Failure.expected }
            return self.response(request)
        }, errorMessage: { _ in "Offline" }))
        model.submit("butterflies")
        await model.execute()
        model.resultsScrollID = "saved-position"
        shouldFail = true
        model.submit("Only blue ones")
        await model.execute()
        XCTAssertEqual(model.context, context)
        XCTAssertEqual(model.draft, "Only blue ones")
        XCTAssertEqual(model.errorMessage, "Offline")
        XCTAssertEqual(model.resultsScrollID, "saved-position")
        XCTAssertFalse(model.hasMore(.species))
        let previousID = model.request?.requestId
        shouldFail = false
        model.retry()
        XCTAssertNotEqual(previousID, model.request?.requestId)
        await model.execute()
        XCTAssertNil(model.errorMessage)
    }
    func testClarificationCarriesUnresolvedQueryIntoNextSubmission() async {
        let unresolved = SpeciesSearchContext(query: "small red creature", group: nil, media: nil, mode: .description)
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            self.response(request, context: unresolved, status: .clarification, message: "Does it have wings?")
        }, errorMessage: { _ in "Failed" }))
        model.submit("small red creature")
        await model.execute()
        XCTAssertFalse(model.hasResults)
        XCTAssertEqual(model.notice, "Does it have wings?")
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertTrue(model.needsClarification)
        model.submit("Yes")
        XCTAssertEqual(model.request?.context, unresolved)
    }
    func testRetryKeepsFailedSectionAndCursor() async throws {
        let cursor = SpeciesSearchCursor(id: "00000000-0000-4000-8000-000000000001", rank: 1, sharedAt: nil)
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            if request.cursor != nil { throw Failure.expected }
            return SpeciesSearchResponse(schemaVersion: 1, requestId: request.requestId, resultKind: request.resultKind,
                status: .results, message: "Butterflies", context: self.context,
                species: [.init(item: .init(id: cursor.id, scientificName: "Danaus plexippus", commonName: "Monarch",
                    contentQuality: nil, taxonomy: nil, iucnRedListStatus: nil, hazardType: nil,
                    groupTags: ["insect"], referenceImageUrl: nil), excerpt: "")],
                sightings: [], nextCursor: cursor)
        }, errorMessage: { _ in "Offline" }))
        model.submit("Butterflies")
        await model.execute()
        model.loadMore(.species)
        await model.execute()
        let failedRequest = try XCTUnwrap(model.request)
        model.loadMore(.sightings) // A failed page must not be overwritten.
        model.retry()
        XCTAssertEqual(model.request?.resultKind, .species)
        XCTAssertEqual(model.request?.cursor, cursor)
        XCTAssertEqual(model.request?.context, failedRequest.context)
        XCTAssertNotEqual(model.request?.requestId, failedRequest.requestId)
    }
    func testClarificationSurvivesExistingSectionPagination() async {
        let unresolved = SpeciesSearchContext(query: "small red creature", group: nil, media: nil, mode: .description)
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            if request.question == "small red creature" {
                return self.response(request, context: unresolved, status: .clarification, message: "Does it have wings?")
            }
            return SpeciesSearchResponse(schemaVersion: 1, requestId: request.requestId, resultKind: request.resultKind,
                status: .results, message: "Butterflies", context: self.context, species: [], sightings: [],
                nextCursor: .init(id: "00000000-0000-4000-8000-000000000001", rank: nil, sharedAt: "2026-08-01T12:00:00Z"))
        }, errorMessage: { _ in "Failed" }))
        model.submit("Butterflies")
        await model.execute()
        model.submit("small red creature")
        await model.execute()
        model.loadMore(.sightings)
        XCTAssertEqual(model.notice, "Does it have wings?")
        await model.execute()
        XCTAssertTrue(model.needsClarification)
        XCTAssertEqual(model.notice, "Does it have wings?")
        model.submit("Yes")
        XCTAssertEqual(model.request?.context, unresolved)
    }
    func testRapidFilterEditsComposeAgainstPendingSelection() async {
        let model = SpeciesSearchViewModel(dependencies: .init(search: { self.response($0) }, errorMessage: { _ in "Failed" }))
        model.submit("Butterflies")
        await model.execute()
        model.setGroup(.birds)
        model.setMedia(.image)
        XCTAssertEqual(model.request?.context?.group, .birds)
        XCTAssertEqual(model.request?.context?.media, .image)
        XCTAssertEqual(model.request?.context?.query, context.query)
    }
    func testCancelledSuccessBecomesRetryableInsteadOfStuckLoading() async {
        var continuation: CheckedContinuation<SpeciesSearchResponse, Error>?
        var pending: SpeciesSearchRequest?
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            pending = request
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }, errorMessage: { _ in "Failed" }))
        model.submit("birds")
        let task = Task { await model.execute() }
        while continuation == nil { await Task.yield() }
        task.cancel()
        continuation?.resume(returning: response(pending!))
        await task.value
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.draft, "birds")
    }

    func testSightingsFailureKeepsNewSpeciesAndRetriesOnlySightings() async {
        var failSightings = false
        var requests: [SpeciesSearchRequest] = []
        let item = starterFixtures[0]
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            requests.append(request)
            if failSightings && request.resultKind == .sightings { throw Failure.expected }
            return SpeciesSearchResponse(schemaVersion: 1, requestId: request.requestId, resultKind: request.resultKind,
                status: .results, message: "Butterflies", context: self.context,
                species: request.resultKind == .species ? [.init(item: item, excerpt: "")] : [],
                sightings: request.resultKind == .sightings ? [ExploreFeedTestFixtures.post(id: "old-sighting")] : [], nextCursor: nil)
        }, errorMessage: { _ in "Offline" }))
        model.submit("Butterflies")
        await model.execute()
        failSightings = true
        model.submit("Only monarchs")
        await model.execute()
        XCTAssertEqual(model.species.map(\.id), [item.id])
        XCTAssertTrue(model.sightings.isEmpty, "Do not show old sightings under the new criteria")
        XCTAssertTrue(model.hasLoaded(.species))
        XCTAssertFalse(model.hasLoaded(.sightings))
        XCTAssertEqual(model.request?.resultKind, .sightings)
        XCTAssertNil(model.request?.question)
        failSightings = false
        model.retry()
        await model.execute()
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests.last?.resultKind, .sightings)
        XCTAssertNil(requests.last?.question)
        XCTAssertTrue(model.hasLoaded(.sightings))
        XCTAssertNil(model.errorMessage)
    }

    func testResetDuringAutomaticSightingsReadRejectsLateResults() async {
        var continuation: CheckedContinuation<SpeciesSearchResponse, Error>?
        var pending: SpeciesSearchRequest?
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            if request.resultKind == .species { return self.response(request) }
            pending = request
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }, errorMessage: { _ in "Failed" }))
        model.submit("Butterflies")
        let work = Task { await model.execute() }
        while continuation == nil { await Task.yield() }
        XCTAssertTrue(model.hasLoaded(.species))
        model.newSearch()
        continuation?.resume(returning: response(pending!))
        await work.value
        XCTAssertFalse(model.hasResults)
        XCTAssertFalse(model.hasLoaded(.sightings))
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.request)
    }

    func testSectionPaginationKeepsSeparateCursorsAndDeduplicatesRows() async {
        let first = starterFixtures[0]
        let second = starterFixtures[1]
        let speciesCursor = SpeciesSearchCursor(id: first.id, rank: 1, sharedAt: nil)
        let sightingCursor = SpeciesSearchCursor(id: "00000000-0000-4000-8000-000000000009", rank: nil,
                                                sharedAt: "2026-08-01T12:00:00Z")
        var requests: [SpeciesSearchRequest] = []
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            requests.append(request)
            let species = request.resultKind == .species
                ? (request.cursor == nil ? [first] : [first, second]).map { SpeciesSearchMatch(item: $0, excerpt: "") } : []
            let posts = request.resultKind == .sightings
                ? (request.cursor == nil ? ["one"] : ["one", "two"]).map { ExploreFeedTestFixtures.post(id: $0) } : []
            return SpeciesSearchResponse(schemaVersion: 1, requestId: request.requestId, resultKind: request.resultKind,
                status: .results, message: "Butterflies", context: self.context, species: species, sightings: posts,
                nextCursor: request.cursor == nil ? (request.resultKind == .species ? speciesCursor : sightingCursor) : nil)
        }, errorMessage: { _ in "Failed" }))
        model.submit("Butterflies")
        await model.execute()
        model.loadMore(.sightings)
        await model.execute()
        XCTAssertEqual(requests.last?.cursor, sightingCursor)
        XCTAssertEqual(model.sightings.map(\.id), ["one", "two"])
        XCTAssertTrue(model.hasMore(.species))
        XCTAssertFalse(model.hasMore(.sightings))
        model.loadMore(.species)
        await model.execute()
        XCTAssertEqual(requests.last?.cursor, speciesCursor)
        XCTAssertEqual(model.species.map(\.id), [first.id, second.id])
        XCTAssertTrue(requests.dropFirst().allSatisfy { $0.question == nil })
    }

    func testNewSearchRotatesPromptsWithoutRepeatingCurrentSet() async {
        let model = SpeciesSearchViewModel(dependencies: .init(search: { self.response($0) }, errorMessage: { _ in "Failed" }))
        let initialIllustration = model.illustrationName
        model.rotateIllustration()
        XCTAssertNotEqual(model.illustrationName, initialIllustration)
        let illustration = model.illustrationName
        XCTAssertNotNil(UIImage(named: illustration))
        let original = model.suggestedPrompts
        XCTAssertEqual(Set(original).count, 3)
        model.submit(original[0])
        await model.execute()
        XCTAssertEqual(model.suggestedPrompts, original)
        XCTAssertEqual(model.illustrationName, illustration)
        model.newSearch()
        XCTAssertEqual(Set(model.suggestedPrompts).count, 3)
        XCTAssertTrue(Set(original).isDisjoint(with: model.suggestedPrompts))
        XCTAssertNotEqual(model.illustrationName, illustration)
        XCTAssertNotNil(UIImage(named: model.illustrationName))
    }

    func testStarterCatalogLoadsWithoutAIAndReusesSuccessfulPage() async {
        var catalogCalls = 0
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            XCTFail("Browsing starter species must not invoke AI search")
            return self.response(request)
        }, errorMessage: { _ in "Failed" }, starterCatalog: .init(loadPage: { request in
            catalogCalls += 1
            XCTAssertEqual(request.category, .recentlyAdded)
            XCTAssertEqual(request.limit, 6)
            return .init(schemaVersion: 1, data: self.starterFixtures, nextCursor: nil)
        }, errorMessage: { _ in "Failed" })))
        await model.starterCatalog.loadIfNeeded(category: .recentlyAdded, region: nil, group: nil, query: nil)
        model.newSearch()
        await model.starterCatalog.loadIfNeeded(category: .recentlyAdded, region: nil, group: nil, query: nil)
        XCTAssertEqual(catalogCalls, 1)
        XCTAssertEqual(model.starterCatalog.items, starterFixtures)
        XCTAssertNil(model.context)
    }

    private var starterFixtures: [SpeciesDictionaryCatalogItem] {
        [("Monarch", "Danaus plexippus"), ("Common sunflower", "Helianthus annuus"),
         ("Fly agaric", "Amanita muscaria"), ("Northern cardinal", "Cardinalis cardinalis")]
            .enumerated().map { index, names in
                .init(id: "00000000-0000-4000-8000-00000000000\(index + 1)",
                      scientificName: names.1, commonName: names.0, contentQuality: nil, taxonomy: nil,
                      iucnRedListStatus: nil, hazardType: nil, groupTags: [],
                      referenceImageUrl: "https://example.invalid/species-\(index).jpg")
            }
    }

    func testSearchVisualFixtures() async throws {
        for (name, hasResults, dark, largeText, sightingCount) in [
            ("intro-light", false, false, false, 0),
            ("intro-dark", false, true, false, 0),
            ("intro-large", false, false, true, 0),
            ("results-single", true, false, false, 1),
            ("results-pair", true, false, false, 2),
            ("results-large-dark", true, true, true, 2)
        ] {
            let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
                SpeciesSearchResponse(schemaVersion: 1, requestId: request.requestId, resultKind: request.resultKind,
                    status: .results, message: "Orange and black butterflies", context: self.context,
                    species: request.resultKind == .species ? [.init(item: .init(id: "00000000-0000-4000-8000-000000000001",
                        scientificName: "Danaus plexippus", commonName: "Monarch",
                        contentQuality: nil, taxonomy: nil, iucnRedListStatus: nil, hazardType: nil,
                        groupTags: ["insect"], referenceImageUrl: "https://example.invalid/species-0.jpg"),
                        excerpt: "An orange and black butterfly. Illustrative dictionary excerpt.")] : [],
                    sightings: request.resultKind == .sightings ? (0..<sightingCount).map { ExploreFeedTestFixtures.post(id: "sighting-\($0)") } : [], nextCursor: nil)
            }, errorMessage: { _ in "Offline" }, starterCatalog: .init(
                loadPage: { _ in .init(schemaVersion: 1, data: self.starterFixtures, nextCursor: nil) },
                errorMessage: { _ in "Unavailable" }
            )))
            if hasResults { model.submit("Orange and black butterflies"); await model.execute() }
            let feed = ExploreFeedViewModel(dependencies: ExploreFeedTestFixtures.dependencies())
            let content = NavigationStack {
                SpeciesSearchView(model: model, exploreViewModel: feed, onOpenPost: { _ in },
                    starterImageDependencies: .init { source, _ in
                        let assets = ["fieldtrip-park-butterfly", "fieldtrip-park-flowering-plant", "fieldtrip-backyard-mushrooms", "bird-cardinal"]
                        let index = (0..<4).first { source.contains("species-\($0)") } ?? 0
                        return UIImage(named: assets[index])
                    }, sightingImageDependencies: .init(loadImage: { _, _ in UIImage(named: "bird-cardinal") }))
            }
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large)
            let controller = UIHostingController(rootView: content)
            controller.overrideUserInterfaceStyle = dark ? .dark : .light
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { controller.view.endEditing(true); window.isHidden = true }
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            controller.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let rendered = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "species-search-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(rendered.size.width, 390)
            XCTAssertFalse(containsFirstResponder(controller.view), "Search should not open the keyboard automatically")
        }
    }

    private func containsFirstResponder(_ view: UIView) -> Bool {
        view.isFirstResponder || view.subviews.contains(where: containsFirstResponder)
    }
}
