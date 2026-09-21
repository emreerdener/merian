import SwiftUI
import XCTest

@testable import Merian

@MainActor
final class SpeciesSearchViewModelTests: XCTestCase {
    private let context = SpeciesSearchContext(query: "orange black butterfly", group: .insects, media: nil, mode: .description)
    private enum Failure: Error { case expected }
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
            pending = request
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }, errorMessage: { _ in "Failed" }))
        model.selectedTab = .sightings
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
    func testFollowupPreservesContextAndTabSwitchDoesNotInvokeQuestion() async throws {
        var requests: [SpeciesSearchRequest] = []
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            requests.append(request)
            return self.response(request)
        }, errorMessage: { _ in "Failed" }))
        model.submit("Orange and black insects")
        await model.execute()
        XCTAssertEqual(model.context, context)
        XCTAssertEqual(model.draft, "")
        model.selectedTab = .sightings
        model.loadSelectedTab()
        await model.execute()
        XCTAssertNil(requests.last?.question)
        XCTAssertEqual(requests.last?.resultKind, .sightings)
        model.submit("Only butterflies")
        await model.execute()
        XCTAssertEqual(requests.last?.context, context)
        XCTAssertEqual(requests.last?.question, "Only butterflies")
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
        XCTAssertEqual(model.selectedTab, .species)
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
        model.speciesScrollID = "saved-position"
        shouldFail = true
        model.submit("Only blue ones")
        await model.execute()
        XCTAssertEqual(model.context, context)
        XCTAssertEqual(model.draft, "Only blue ones")
        XCTAssertEqual(model.errorMessage, "Offline")
        XCTAssertEqual(model.speciesScrollID, "saved-position")
        XCTAssertFalse(model.hasMore)
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
    func testRetryKeepsFailedPageKindAfterTabChange() async throws {
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
        model.loadMore()
        await model.execute()
        let failedRequest = try XCTUnwrap(model.request)
        model.selectedTab = .sightings
        model.retry()
        XCTAssertEqual(model.request?.resultKind, .species)
        XCTAssertEqual(model.request?.cursor, cursor)
        XCTAssertEqual(model.request?.context, failedRequest.context)
        XCTAssertNotEqual(model.request?.requestId, failedRequest.requestId)
        XCTAssertEqual(model.selectedTab, .sightings)
    }
    func testClarificationSurvivesBrowsingAnotherResultTab() async {
        let unresolved = SpeciesSearchContext(query: "small red creature", group: nil, media: nil, mode: .description)
        let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
            if request.question == "small red creature" {
                return self.response(request, context: unresolved, status: .clarification, message: "Does it have wings?")
            }
            return self.response(request)
        }, errorMessage: { _ in "Failed" }))
        model.submit("Butterflies")
        await model.execute()
        model.submit("small red creature")
        await model.execute()
        model.selectedTab = .sightings
        model.loadSelectedTab()
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
        for (name, hasResults, dark, largeText) in [
            ("intro-light", false, false, false),
            ("intro-dark", false, true, false),
            ("intro-large", false, false, true),
            ("results-light", true, false, false),
            ("results-large-dark", true, true, true)
        ] {
            let model = SpeciesSearchViewModel(dependencies: .init(search: { request in
                SpeciesSearchResponse(schemaVersion: 1, requestId: request.requestId, resultKind: .species,
                    status: .results, message: "Orange and black butterflies", context: self.context,
                    species: [.init(item: .init(id: "00000000-0000-4000-8000-000000000001",
                        scientificName: "Danaus plexippus", commonName: "Monarch",
                        contentQuality: nil, taxonomy: nil, iucnRedListStatus: nil, hazardType: nil,
                        groupTags: ["insect"], referenceImageUrl: nil),
                        excerpt: "An orange and black butterfly. Illustrative dictionary excerpt.")],
                    sightings: [], nextCursor: nil)
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
                    })
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
