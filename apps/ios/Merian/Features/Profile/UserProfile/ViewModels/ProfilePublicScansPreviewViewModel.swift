import Combine
import Observation

struct ProfilePublicationsUpdate {
    let postsToRegister: [ExplorePost]
    let refreshesSocialStats: Bool

    static let none = Self(
        postsToRegister: [],
        refreshesSocialStats: false
    )
}

@MainActor
@Observable
final class ProfilePublicScansPreviewViewModel {
    private(set) var posts: [ExplorePost] = []
    private(set) var isLoading = true
    private(set) var hasLoaded = false
    private(set) var didFail = false

    private let dependencies: ProfilePublicationsDependencies
    private let previewLimit: Int
    private var activeAuthorUserID: String?
    private var loadGeneration = 0

    init(
        previewLimit: Int = 9,
        dependencies: ProfilePublicationsDependencies? = nil
    ) {
        self.previewLimit = previewLimit
        self.dependencies = dependencies ?? .live
    }

    var appEvents: AnyPublisher<AppEvent, Never> {
        dependencies.appEvents
    }

    func load(authorUserID: String?) async -> [ExplorePost] {
        guard let authorUserID = normalizedID(authorUserID) else {
            resetForSignedOutState()
            return []
        }

        prepareForAuthor(authorUserID)
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        hasLoaded = false
        didFail = false
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
                previewLimit,
                nil
            )
            guard canApply(generation: generation, authorUserID: authorUserID) else {
                return []
            }
            posts = Array(page.data.prefix(previewLimit))
            hasLoaded = true
            return page.data
        } catch {
            guard canApply(generation: generation, authorUserID: authorUserID) else {
                return []
            }
            posts = []
            didFail = true
            hasLoaded = true
            return []
        }
    }

    func retainPosts(where shouldRetain: (ExplorePost) -> Bool) {
        posts.removeAll { !shouldRetain($0) }
    }

    func handle(
        event: AppEvent,
        currentUserID: String?
    ) async -> ProfilePublicationsUpdate {
        switch event {
        case .exploreShareStateChanged(let scanID, let postID):
            if postID == nil {
                posts.removeAll { $0.scanId == scanID }
            }
            let loaded = await load(authorUserID: currentUserID)
            return ProfilePublicationsUpdate(
                postsToRegister: loaded,
                refreshesSocialStats: true
            )

        case .explorePostNeedsRefresh(let postID):
            guard posts.contains(where: { $0.id == postID }),
                  let authorUserID = activeAuthorUserID else {
                return .none
            }
            let generation = loadGeneration
            do {
                let post = try await dependencies.loadPost(postID)
                guard canApply(
                    generation: generation,
                    authorUserID: authorUserID
                ) else { return .none }
                upsert(post)
                return ProfilePublicationsUpdate(
                    postsToRegister: [post],
                    refreshesSocialStats: false
                )
            } catch {
                return .none
            }

        case .publicAuthorIdentityChanged(_, let updatedUserID):
            guard normalizedID(currentUserID) == normalizedID(updatedUserID) else {
                return .none
            }
            let loaded = await load(authorUserID: currentUserID)
            return ProfilePublicationsUpdate(
                postsToRegister: loaded,
                refreshesSocialStats: true
            )

        default:
            return .none
        }
    }

    func reviewRecovery(ownerUserID: String) {
        dependencies.reviewRecovery(ownerUserID)
    }

    func selectionFeedback() {
        dependencies.selectionFeedback()
    }

    private func prepareForAuthor(_ authorUserID: String) {
        guard activeAuthorUserID != authorUserID else { return }
        activeAuthorUserID = authorUserID
        loadGeneration += 1
        posts = []
        isLoading = true
        hasLoaded = false
        didFail = false
    }

    private func resetForSignedOutState() {
        activeAuthorUserID = nil
        loadGeneration += 1
        posts = []
        isLoading = false
        hasLoaded = false
        didFail = false
    }

    private func upsert(_ post: ExplorePost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        } else {
            posts.insert(post, at: 0)
            posts = Array(posts.prefix(previewLimit))
        }
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

    private func normalizedID(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }
}
