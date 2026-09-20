import Foundation
import Observation

@MainActor
@Observable
final class ExplorePostReactorsViewModel {
    private(set) var reactors: [ExplorePostReactor] = []
    private(set) var totalCount = 0
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false
    private let postId: String
    private let load: @MainActor (String, String?) async throws -> ExplorePostReactorsPage
    private let currentViewer: @MainActor () -> String?
    private var generation = UUID()

    init(
        postId: String,
        load: @escaping @MainActor (String, String?) async throws -> ExplorePostReactorsPage,
        currentViewer: @escaping @MainActor () -> String?
    ) {
        self.postId = postId
        self.load = load
        self.currentViewer = currentViewer
    }

    var summary: String? {
        guard totalCount > 0 else { return nil }
        let previewUsernames = reactors.prefix(min(totalCount, 2)).compactMap {
            ExplorePost.publicUsernameDisplayValue($0.username)
        }
        guard previewUsernames.count == min(totalCount, 2), let first = previewUsernames.first else {
            return "\(totalCount) \(totalCount == 1 ? "person" : "people") reacted"
        }
        if totalCount == 1 { return "\(first) reacted" }
        let names = "\(first), \(previewUsernames[1])"
        if totalCount == 2 { return "\(first) and \(previewUsernames[1]) reacted" }
        let others = totalCount - 2
        return "\(names), and \(others) \(others == 1 ? "other" : "others") reacted"
    }

    func refresh() async {
        invalidate()
        let request = generation
        let viewer = currentViewer()
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let page = try await load(postId, nil)
            guard !Task.isCancelled, generation == request, viewer == currentViewer() else { return }
            reactors = page.reactors
            applySummary(page)
            hasLoaded = true
        } catch {
            guard !Task.isCancelled, generation == request, viewer == currentViewer() else { return }
            errorMessage = "Couldn’t load reactions. Please try again."
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoading, !isLoadingMore else { return }
        let request = generation
        let viewer = currentViewer()
        isLoadingMore = true
        errorMessage = nil
        defer { if generation == request { isLoadingMore = false } }
        do {
            let page = try await load(postId, cursor)
            guard !Task.isCancelled, generation == request, viewer == currentViewer() else { return }
            for reactor in page.reactors {
                if let index = reactors.firstIndex(where: { $0.id == reactor.id }) {
                    reactors[index] = reactor
                } else {
                    reactors.append(reactor)
                }
            }
            applySummary(page)
        } catch {
            guard !Task.isCancelled, generation == request, viewer == currentViewer() else { return }
            errorMessage = "Couldn’t load more reactions. Please try again."
        }
    }

    func invalidate() {
        generation = UUID()
        reactors = []
        totalCount = 0
        nextCursor = nil
        errorMessage = nil
        isLoading = false
        isLoadingMore = false
        hasLoaded = false
    }

    private func applySummary(_ page: ExplorePostReactorsPage) {
        totalCount = page.totalCount
        nextCursor = page.nextCursor
    }
}
