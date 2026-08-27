import Foundation
import Observation

@MainActor
@Observable
final class ExploreHashtagPostsViewModel {
    struct Dependencies {
        let loadPage: @MainActor (
            _ hashtag: String,
            _ limit: Int,
            _ cursor: ExploreHashtagPostCursor?
        ) async throws -> [ExplorePost]
        let errorMessage: @MainActor (Error) -> String
    }

    let hashtag: String
    private let dependencies: Dependencies
    private let pageSize: Int
    private var cursor = ExploreHashtagPostCursor.empty
    private var requestGeneration = UUID()
    private var loadMoreRequestGeneration: UUID?

    private(set) var posts: [ExplorePost] = []
    private(set) var isLoadingInitialPage = true
    private(set) var isLoadingMore = false
    private(set) var hasReachedEnd = false
    private(set) var errorMessage: String?

    init(
        hashtag: String,
        pageSize: Int = 30,
        dependencies: Dependencies = .live
    ) {
        self.hashtag = hashtag
        self.pageSize = pageSize
        self.dependencies = dependencies
    }

    func reload() async {
        let generation = UUID()
        requestGeneration = generation
        loadMoreRequestGeneration = nil
        posts = []
        cursor = .empty
        hasReachedEnd = false
        errorMessage = nil
        isLoadingInitialPage = true
        isLoadingMore = false

        defer {
            if requestGeneration == generation {
                isLoadingInitialPage = false
            }
        }

        do {
            let page = try await dependencies.loadPage(hashtag, pageSize, nil)
            guard requestGeneration == generation else { return }
            apply(page)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard requestGeneration == generation else { return }
            errorMessage = dependencies.errorMessage(error)
        }
    }

    @discardableResult
    func loadMoreIfNeeded() async -> String? {
        guard !isLoadingInitialPage,
              loadMoreRequestGeneration == nil,
              !hasReachedEnd else { return nil }

        let generation = requestGeneration
        loadMoreRequestGeneration = generation
        isLoadingMore = true
        defer {
            if loadMoreRequestGeneration == generation {
                loadMoreRequestGeneration = nil
                isLoadingMore = false
            }
        }

        do {
            let page = try await dependencies.loadPage(
                hashtag,
                pageSize,
                cursor.isEmpty ? nil : cursor
            )
            guard requestGeneration == generation else { return nil }
            apply(page)
            return nil
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            guard requestGeneration == generation else { return nil }
            return dependencies.errorMessage(error)
        }
    }

    private func apply(_ page: [ExplorePost]) {
        let existingIDs = Set(posts.map(\.id))
        posts.append(contentsOf: page.filter { !existingIDs.contains($0.id) })
        if let lastPost = posts.last {
            cursor = ExploreHashtagPostCursor(
                beforeSharedAt: lastPost.sharedAt,
                beforePostId: lastPost.id
            )
        }
        hasReachedEnd = page.count < pageSize
        errorMessage = nil
    }
}
