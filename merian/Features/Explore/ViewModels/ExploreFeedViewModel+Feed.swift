import Foundation
import SwiftUI

extension ExploreFeedViewModel {
    func loadInitialFeed(force: Bool = false) async {
        guard !isLoadingInitialFeed else { return }
        guard force || !hasLoadedFeedOnce else { return }

        isLoadingInitialFeed = true
        if force {
            errorMessage = nil
        }

        defer { isLoadingInitialFeed = false }

        do {
            let freshPosts = try await MerianNetworkClient.shared.getExploreFeed(
                limit: feedPageSize
            )

            store.setFeedPosts(freshPosts)
            hasLoadedFeedOnce = true
            hasReachedEndOfFeed = freshPosts.count < feedPageSize
            updateFeedCursor(using: freshPosts)
            errorMessage = nil
            reconcileActiveCommentsPost()
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasUnseenExplorePost)

            if let latestSharedAt = freshPosts.first?.sharedAt {
                UserDefaults.standard.set(latestSharedAt, forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt)
            }
        } catch is CancellationError {
            // Silently absorb cancellation
        } catch let error as URLError where error.code == .cancelled {
            // Silently absorb URLSession cancellation
        } catch {
            if posts.isEmpty {
                errorMessage = ExploreErrorFormatter.message(for: error)
            } else {
                toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

    func loadMoreIfNeeded(currentPost: ExplorePost) async {
        guard !isLoadingInitialFeed, !isLoadingMore, !hasReachedEndOfFeed else { return }
        guard let currentIndex = posts.firstIndex(where: { $0.id == currentPost.id }) else { return }

        let triggerIndex = max(posts.count - 5, 0)
        guard currentIndex >= triggerIndex else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            guard let nextFeedCursorSharedAt, let nextFeedCursorPostId else {
                hasReachedEndOfFeed = true
                return
            }

            let nextPage = try await MerianNetworkClient.shared.getExploreFeed(
                limit: feedPageSize,
                beforeSharedAt: nextFeedCursorSharedAt,
                beforePostId: nextFeedCursorPostId
            )

            appendUniquePosts(nextPage)
            hasReachedEndOfFeed = nextPage.count < feedPageSize
            updateFeedCursor(using: nextPage)
            reconcileActiveCommentsPost()
        } catch is CancellationError {
            // Absorb
        } catch let error as URLError where error.code == .cancelled {
            // Absorb
        } catch {
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func updateFeedCursor(using page: [ExplorePost]) {
        nextFeedCursorSharedAt = page.last?.sharedAt
        nextFeedCursorPostId = page.last?.id
    }

    func appendUniquePosts(_ nextPage: [ExplorePost]) {
        guard !nextPage.isEmpty else { return }

        store.appendUniqueFeedPosts(nextPage)
    }
}
