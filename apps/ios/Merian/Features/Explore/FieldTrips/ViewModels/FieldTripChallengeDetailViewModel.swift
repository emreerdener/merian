import Foundation
import Observation

@MainActor
@Observable
final class FieldTripChallengeDetailViewModel {
    struct EntriesPageRequest {
        let challengeId: String
        let limit: Int
        let beforePublishedAt: String
        let beforeEntryId: String
    }

    struct Dependencies {
        let loadChallenge: @MainActor (_ challengeId: String, _ entriesLimit: Int) async throws -> FieldTripChallenge
        let joinChallenge: @MainActor (_ challengeId: String) async throws -> FieldTripChallenge
        let loadEntriesPage: @MainActor (EntriesPageRequest) async throws -> [FieldTripChallengeEntry]
        let successFeedback: @MainActor () -> Void
        let errorFeedback: @MainActor () -> Void
        let progressDidChange: @MainActor () -> Void
        let errorMessage: @MainActor (Error) -> String
    }

    var challenge: FieldTripChallenge?
    var entries: [FieldTripChallengeEntry] = []
    var isLoading = false
    var isJoining = false
    var isLoadingMoreEntries = false
    var errorMessage: String?
    var toastMessage: ToastPayload?
    var hasMoreEntries = true

    private let challengeId: String
    private let entriesPageSize = 12
    private let dependencies: Dependencies

    init(challengeId: String, dependencies: Dependencies = .live) {
        self.challengeId = challengeId
        self.dependencies = dependencies
    }

    func load(force: Bool = false) async {
        guard force || challenge == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await dependencies.loadChallenge(challengeId, entriesPageSize)
            challenge = loaded
            entries = loaded.entries
            hasMoreEntries = loaded.entries.count >= entriesPageSize
        } catch {
            errorMessage = dependencies.errorMessage(error)
        }
    }

    func refresh() async {
        await load(force: true)
    }

    func join() async {
        guard !isJoining else { return }
        isJoining = true
        errorMessage = nil
        defer { isJoining = false }

        do {
            let loaded = try await dependencies.joinChallenge(challengeId)
            challenge = loaded
            entries = loaded.entries
            hasMoreEntries = loaded.entries.count >= entriesPageSize
            dependencies.successFeedback()
            toastMessage = .success("Challenge joined.")
            dependencies.progressDidChange()
        } catch {
            dependencies.errorFeedback()
            toastMessage = .error(dependencies.errorMessage(error))
        }
    }

    func loadMoreEntries() async {
        guard hasMoreEntries,
              !isLoadingMoreEntries,
              let cursor = entries.last else {
            return
        }

        isLoadingMoreEntries = true
        defer { isLoadingMoreEntries = false }

        do {
            let page = try await dependencies.loadEntriesPage(
                EntriesPageRequest(
                    challengeId: challengeId,
                    limit: entriesPageSize,
                    beforePublishedAt: cursor.publishedAt,
                    beforeEntryId: cursor.entryId
                )
            )
            entries.append(contentsOf: page)
            hasMoreEntries = page.count >= entriesPageSize
        } catch {
            toastMessage = .error(dependencies.errorMessage(error))
        }
    }
}
