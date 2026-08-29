import Combine
import Observation
import SwiftData

@MainActor
@Observable
final class ProfilePublishedScansViewModel {
    private(set) var posts: [ExplorePost] = []
    private(set) var cursor = ExploreAuthorPostCursor.empty
    private(set) var isLoading = false
    private(set) var didFail = false
    private(set) var hasReachedEnd = false

    private let dependencies: ProfilePublicationsDependencies
    private let pageSize: Int
    private var activeAuthorUserID: String?
    private var loadGeneration = 0

    init(
        pageSize: Int = 30,
        dependencies: ProfilePublicationsDependencies? = nil
    ) {
        self.pageSize = pageSize
        self.dependencies = dependencies ?? .live
    }

    var appEvents: AnyPublisher<AppEvent, Never> {
        dependencies.appEvents
    }

    @discardableResult
    func reload(authorUserID: String) async -> [ExplorePost] {
        let authorUserID = normalizedID(authorUserID)
        activeAuthorUserID = authorUserID
        loadGeneration += 1
        let generation = loadGeneration
        posts = []
        cursor = .empty
        hasReachedEnd = false
        didFail = false
        isLoading = true
        return await loadPage(
            authorUserID: authorUserID,
            cursor: nil,
            generation: generation
        )
    }

    @discardableResult
    func loadMore(authorUserID: String) async -> [ExplorePost] {
        let authorUserID = normalizedID(authorUserID)
        prepareForAuthor(authorUserID)
        guard !isLoading, !hasReachedEnd else { return [] }

        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        return await loadPage(
            authorUserID: authorUserID,
            cursor: cursor.isEmpty ? nil : cursor,
            generation: generation
        )
    }

    func identityChangeAffects(
        authorUserID: String,
        previousUserID: String?,
        currentUserID: String
    ) -> Bool {
        let authorUserID = normalizedID(authorUserID)
        return normalizedID(previousUserID) == authorUserID ||
            normalizedID(currentUserID) == authorUserID
    }

    func reviewRecovery(ownerUserID: String) {
        dependencies.reviewRecovery(ownerUserID)
    }

    func selectionFeedback() {
        dependencies.selectionFeedback()
    }

    func insightRoute(
        scanID: String,
        modelContext: ModelContext
    ) -> ScanInsightRoute? {
        dependencies.resolveScanRoute(scanID, modelContext)
    }

    private func loadPage(
        authorUserID: String,
        cursor requestCursor: ExploreAuthorPostCursor?,
        generation: Int
    ) async -> [ExplorePost] {
        defer {
            if isCurrentLoad(
                generation: generation,
                authorUserID: authorUserID
            ) {
                isLoading = false
            }
        }

        do {
            let page = try await dependencies.loadPosts(
                authorUserID,
                pageSize,
                requestCursor
            )
            guard canApply(generation: generation, authorUserID: authorUserID) else {
                return []
            }
            merge(page.data)
            cursor = page.nextCursor ?? .empty
            hasReachedEnd = page.nextCursor == nil
            didFail = false
            return page.data
        } catch {
            guard canApply(generation: generation, authorUserID: authorUserID) else {
                return []
            }
            didFail = true
            return []
        }
    }

    private func prepareForAuthor(_ authorUserID: String) {
        guard activeAuthorUserID != authorUserID else { return }
        activeAuthorUserID = authorUserID
        loadGeneration += 1
        posts = []
        cursor = .empty
        isLoading = false
        didFail = false
        hasReachedEnd = false
    }

    private func merge(_ page: [ExplorePost]) {
        var seenIDs = Set(posts.map(\.id))
        posts.append(contentsOf: page.filter { seenIDs.insert($0.id).inserted })
    }

    private func canApply(generation: Int, authorUserID: String) -> Bool {
        !Task.isCancelled && isCurrentLoad(
            generation: generation,
            authorUserID: authorUserID
        )
    }

    private func isCurrentLoad(
        generation: Int,
        authorUserID: String
    ) -> Bool {
        loadGeneration == generation &&
            activeAuthorUserID == authorUserID
    }

    private func normalizedID(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}
