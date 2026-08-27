import Foundation
import Observation

@MainActor
@Observable
final class ExploreAuthorProfileViewModel {
    struct Dependencies {
        let loadProfile: @MainActor (
            _ authorUserId: String,
            _ previewLimit: Int
        ) async throws -> ExploreAuthorProfile
        let loadPosts: @MainActor (
            _ authorUserId: String,
            _ limit: Int,
            _ cursor: ExploreAuthorPostCursor?
        ) async throws -> ExploreAuthorPostsResponse
        let setFollowing: @MainActor (
            _ authorUserId: String,
            _ isFollowing: Bool
        ) async throws -> ExploreFollowState
        let prefetchImages: @MainActor (_ imageUrls: [String]) -> Void
        let successFeedback: @MainActor () -> Void
        let errorFeedback: @MainActor () -> Void
        let errorMessage: @MainActor (Error) -> String
    }

    enum ProfileState {
        case loading
        case error(String)
        case loaded(ExploreAuthorProfile)
    }

    private(set) var profile: ExploreAuthorProfile?
    private(set) var isLoadingProfile = true
    private(set) var profileErrorMessage: String?
    private(set) var libraryPosts: [ExplorePost] = []
    private(set) var libraryCursor = ExploreAuthorPostCursor.empty
    private(set) var isLoadingLibrary = false
    private(set) var hasReachedEndOfLibrary = false
    private(set) var isUpdatingFollow = false

    private let dependencies: Dependencies
    private var activeAuthorUserId: String?
    private var profileLoadGeneration = 0
    private var libraryLoadGeneration = 0
    private var followMutationGeneration = 0
    private var interactionErrorMessage: String?

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    var profileState: ProfileState {
        if isLoadingProfile && profile == nil {
            return .loading
        }
        if let profile {
            return .loaded(profile)
        }
        return .error(profileErrorMessage ?? "This profile is not available right now.")
    }

    @discardableResult
    func loadProfile(
        authorUserId: String,
        force: Bool = false,
        localReferenceUrlsByScanId: [String: String] = [:]
    ) async -> [ExplorePost] {
        prepareForAuthor(authorUserId)
        guard force || profile == nil else { return [] }

        profileLoadGeneration += 1
        let generation = profileLoadGeneration
        let normalizedAuthorUserId = authorUserId.lowercased()
        isLoadingProfile = true
        profileErrorMessage = nil

        do {
            let loadedProfile = try await dependencies.loadProfile(
                authorUserId,
                ExploreAuthorProfilePresentation.previewLimit
            )
            guard canApplyProfileLoad(
                generation: generation,
                authorUserId: normalizedAuthorUserId
            ) else { return [] }

            let imageUrls = loadedProfile.previewPosts.map { post in
                post.gridThumbnailUrl(localReferenceUrl: localReferenceUrlsByScanId[post.scanId])
            }
            dependencies.prefetchImages(imageUrls)
            profile = loadedProfile
            profileErrorMessage = nil
            invalidateLibraryLoad()
            seedLibrary(from: loadedProfile)
            isLoadingProfile = false
            return loadedProfile.previewPosts
        } catch {
            guard canApplyProfileLoad(
                generation: generation,
                authorUserId: normalizedAuthorUserId
            ) else { return [] }

            profile = nil
            profileErrorMessage = dependencies.errorMessage(error)
            isLoadingProfile = false
            return []
        }
    }

    func seedLibraryIfNeeded(from profile: ExploreAuthorProfile) {
        guard libraryPosts.isEmpty else { return }
        invalidateLibraryLoad()
        seedLibrary(from: profile)
    }

    @discardableResult
    func reloadLibrary(authorUserId: String, fallbackProfile: ExploreAuthorProfile) async -> [ExplorePost] {
        prepareForAuthor(authorUserId)
        invalidateLibraryLoad()
        libraryPosts = []
        libraryCursor = .empty
        hasReachedEndOfLibrary = false
        let loadedPosts = await loadMoreLibraryPosts(authorUserId: authorUserId)
        if isActiveAuthor(authorUserId), libraryPosts.isEmpty {
            seedLibrary(from: fallbackProfile)
        }
        return loadedPosts
    }

    @discardableResult
    func loadMoreLibraryPosts(authorUserId: String) async -> [ExplorePost] {
        prepareForAuthor(authorUserId)
        guard !isLoadingLibrary, !hasReachedEndOfLibrary, profile != nil else { return [] }

        libraryLoadGeneration += 1
        let generation = libraryLoadGeneration
        isLoadingLibrary = true
        defer {
            if libraryLoadGeneration == generation, isActiveAuthor(authorUserId) {
                isLoadingLibrary = false
            }
        }

        do {
            let page = try await dependencies.loadPosts(
                authorUserId,
                ExploreAuthorProfilePresentation.libraryPageSize,
                libraryCursor.isEmpty ? nil : libraryCursor
            )
            guard canApplyLibraryLoad(
                generation: generation,
                authorUserId: authorUserId
            ) else { return [] }

            libraryPosts = ExploreAuthorProfilePresentation.deduplicatedPosts(
                libraryPosts + page.data
            )
            libraryCursor = page.nextCursor ?? .empty
            hasReachedEndOfLibrary = page.nextCursor == nil
            return page.data
        } catch {
            guard canApplyLibraryLoad(
                generation: generation,
                authorUserId: authorUserId
            ) else { return [] }
            interactionErrorMessage = dependencies.errorMessage(error)
            dependencies.errorFeedback()
            return []
        }
    }

    func toggleFollow(currentUserId: String?) async {
        guard !isUpdatingFollow,
              let currentProfile = profile,
              !ExploreAuthorProfilePresentation.isCurrentUser(
                  authorUserId: currentProfile.authorUserId,
                  currentUserId: currentUserId
              ) else { return }

        let nextFollowingState = !currentProfile.viewerIsFollowing
        var optimisticProfile = currentProfile
        optimisticProfile.viewerIsFollowing = nextFollowingState
        optimisticProfile.followerCount = max(
            0,
            currentProfile.followerCount + (nextFollowingState ? 1 : -1)
        )

        followMutationGeneration += 1
        let generation = followMutationGeneration
        isUpdatingFollow = true
        profile = optimisticProfile
        defer {
            if followMutationGeneration == generation,
               isActiveAuthor(currentProfile.authorUserId) {
                isUpdatingFollow = false
            }
        }

        do {
            let followState = try await dependencies.setFollowing(
                currentProfile.authorUserId,
                nextFollowingState
            )
            guard canApplyFollowMutation(
                generation: generation,
                authorUserId: currentProfile.authorUserId
            ) else { return }
            applyFollowState(followState)
            dependencies.successFeedback()
        } catch {
            guard canApplyFollowMutation(
                generation: generation,
                authorUserId: currentProfile.authorUserId
            ) else { return }
            if profile == optimisticProfile {
                profile = currentProfile
            }
            interactionErrorMessage = dependencies.errorMessage(error)
            dependencies.errorFeedback()
        }
    }

    func takeInteractionErrorMessage() -> String? {
        defer { interactionErrorMessage = nil }
        return interactionErrorMessage
    }

    private func prepareForAuthor(_ authorUserId: String) {
        let normalizedAuthorUserId = authorUserId.lowercased()
        guard activeAuthorUserId != normalizedAuthorUserId else { return }

        activeAuthorUserId = normalizedAuthorUserId
        profileLoadGeneration += 1
        invalidateLibraryLoad()
        followMutationGeneration += 1
        profile = nil
        isLoadingProfile = true
        profileErrorMessage = nil
        libraryPosts = []
        libraryCursor = .empty
        hasReachedEndOfLibrary = false
        isUpdatingFollow = false
        interactionErrorMessage = nil
    }

    private func isActiveAuthor(_ authorUserId: String) -> Bool {
        activeAuthorUserId == authorUserId.lowercased()
    }

    private func canApplyProfileLoad(generation: Int, authorUserId: String) -> Bool {
        !Task.isCancelled &&
            profileLoadGeneration == generation &&
            activeAuthorUserId == authorUserId
    }

    private func canApplyLibraryLoad(generation: Int, authorUserId: String) -> Bool {
        !Task.isCancelled &&
            libraryLoadGeneration == generation &&
            isActiveAuthor(authorUserId)
    }

    private func canApplyFollowMutation(generation: Int, authorUserId: String) -> Bool {
        !Task.isCancelled &&
            followMutationGeneration == generation &&
            isActiveAuthor(authorUserId)
    }

    private func invalidateLibraryLoad() {
        libraryLoadGeneration += 1
        isLoadingLibrary = false
    }

    private func seedLibrary(from profile: ExploreAuthorProfile) {
        libraryPosts = ExploreAuthorProfilePresentation.deduplicatedPosts(profile.previewPosts)
        if let lastPost = libraryPosts.last {
            libraryCursor = ExploreAuthorPostCursor(
                beforeSharedAt: lastPost.sharedAt,
                beforePostId: lastPost.id
            )
        } else {
            libraryCursor = .empty
        }
        hasReachedEndOfLibrary = false
    }

    private func applyFollowState(_ followState: ExploreFollowState) {
        guard var currentProfile = profile,
              currentProfile.authorUserId.lowercased() == followState.authorUserId.lowercased() else {
            return
        }

        currentProfile.followerCount = followState.followerCount
        currentProfile.followingCount = followState.followingCount
        currentProfile.viewerIsFollowing = followState.viewerIsFollowing
        profile = currentProfile
    }
}
