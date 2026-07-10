import Foundation
import Observation

@MainActor
@Observable
final class FieldTripsViewModel {
    var templates: [FieldTripTemplate] = []
    var challenges: [FieldTripChallenge] = []
    var isLoading = false
    var errorMessage: String?
    var challengeErrorMessage: String?
    var toastMessage: String?

    private var didLoad = false

    func load(userRegion: String? = nil, force: Bool = false) async {
        guard force || !didLoad else { return }
        isLoading = true
        errorMessage = nil
        challengeErrorMessage = nil
        defer {
            isLoading = false
            didLoad = true
        }

        do {
            templates = try await MerianNetworkClient.shared.getFieldTrips(userRegion: userRegion)
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }

        do {
            challenges = try await MerianNetworkClient.shared.getFieldTripChallenges(userRegion: userRegion)
        } catch {
            challengeErrorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func refresh(userRegion: String? = nil) async {
        await load(userRegion: userRegion, force: true)
    }

    func template(withId templateId: String) -> FieldTripTemplate? {
        templates.first { $0.templateId == templateId }
    }

    func replaceTemplate(_ template: FieldTripTemplate) {
        guard let index = templates.firstIndex(where: { $0.templateId == template.templateId }) else {
            return
        }
        templates[index] = template
    }

    func challenge(withId challengeId: String) -> FieldTripChallenge? {
        challenges.first { $0.challengeId == challengeId }
    }

    func replaceChallenge(_ challenge: FieldTripChallenge) {
        guard let index = challenges.firstIndex(where: { $0.challengeId == challenge.challengeId }) else {
            return
        }
        challenges[index] = challenge
    }

    func applyProgressToast(_ updates: [FieldTripProgressUpdate]) {
        guard let update = updates.first,
              let item = update.newlyCompletedItems.first else {
            return
        }

        let label = item.commonName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? item.prompt
        toastMessage = "\(update.title): \(label)"
    }

    func applyChallengeProgressToast(_ updates: [FieldTripChallengeProgressUpdate]) {
        guard let update = updates.first,
              let item = update.newlyCompletedItems.first else {
            return
        }

        let label = item.commonName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? item.prompt
        toastMessage = "\(update.title): \(label)"
    }
}

@MainActor
@Observable
final class FieldTripChallengeDetailViewModel {
    var challenge: FieldTripChallenge?
    var entries: [FieldTripChallengeEntry] = []
    var isLoading = false
    var isJoining = false
    var isLoadingMoreEntries = false
    var errorMessage: String?
    var toastMessage: String?
    var hasMoreEntries = true

    private let challengeId: String
    private let entriesPageSize = 12

    init(challengeId: String) {
        self.challengeId = challengeId
    }

    func load(force: Bool = false) async {
        guard force || challenge == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await MerianNetworkClient.shared.getFieldTripChallenge(
                challengeId: challengeId,
                entriesLimit: entriesPageSize
            )
            challenge = loaded
            entries = loaded.entries
            hasMoreEntries = loaded.entries.count >= entriesPageSize
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
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
            let loaded = try await MerianNetworkClient.shared.joinFieldTripChallenge(challengeId: challengeId)
            challenge = loaded
            entries = loaded.entries
            hasMoreEntries = loaded.entries.count >= entriesPageSize
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Challenge joined."
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
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
            let page = try await MerianNetworkClient.shared.getFieldTripChallengePublications(
                challengeId: challengeId,
                limit: entriesPageSize,
                beforePublishedAt: cursor.publishedAt,
                beforeEntryId: cursor.entryId
            )
            entries.append(contentsOf: page)
            hasMoreEntries = page.count >= entriesPageSize
        } catch {
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }
}

@MainActor
@Observable
final class FieldTripPublicationViewModel {
    var detail: FieldTripPublicationDetail?
    var comments: [ExploreComment] = []
    var commentDraft = ""
    var isLoading = false
    var isLoadingComments = false
    var isSubmittingComment = false
    var isUpdatingLike = false
    var errorMessage: String?
    var commentErrorMessage: String?
    var toastMessage: String?

    private let publicationId: String

    init(publicationId: String) {
        self.publicationId = publicationId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await MerianNetworkClient.shared.getFieldTripPublication(publicationId: publicationId)
            await loadComments()
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func loadComments() async {
        isLoadingComments = true
        commentErrorMessage = nil
        defer { isLoadingComments = false }

        do {
            comments = try await MerianNetworkClient.shared.getFieldTripComments(publicationId: publicationId)
        } catch {
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func toggleLike() async {
        guard var current = detail, !isUpdatingLike else { return }
        isUpdatingLike = true
        defer { isUpdatingLike = false }

        let targetLiked = !current.viewerHasLiked
        current.viewerHasLiked = targetLiked
        current.likeCount = max(0, current.likeCount + (targetLiked ? 1 : -1))
        detail = current

        do {
            let response = try await MerianNetworkClient.shared.setFieldTripLike(
                publicationId: publicationId,
                liked: targetLiked
            )
            current.viewerHasLiked = response.viewerHasLiked
            current.likeCount = response.likeCount
            if let commentCount = response.commentCount {
                current.commentCount = commentCount
            }
            detail = current
            HapticManager.shared.triggerSelectionPulse()
        } catch {
            current.viewerHasLiked.toggle()
            current.likeCount = max(0, current.likeCount + (targetLiked ? -1 : 1))
            detail = current
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func submitComment() async {
        guard var current = detail, !isSubmittingComment else { return }
        let trimmed = String(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { return }

        isSubmittingComment = true
        commentErrorMessage = nil
        let previousDraft = commentDraft
        commentDraft = ""
        defer { isSubmittingComment = false }

        do {
            let response = try await MerianNetworkClient.shared.createFieldTripComment(
                publicationId: publicationId,
                body: trimmed
            )
            comments.append(response.comment)
            current.commentCount = response.commentCount
            detail = current
            HapticManager.shared.triggerSuccessPulse()
        } catch {
            commentDraft = previousDraft
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
            HapticManager.shared.triggerErrorThump()
        }
    }
}

@MainActor
@Observable
final class FieldTripChallengeEntryViewModel {
    var detail: FieldTripChallengeEntryDetail?
    var comments: [ExploreComment] = []
    var commentDraft = ""
    var isLoading = false
    var isLoadingComments = false
    var isSubmittingComment = false
    var isUpdatingLike = false
    var errorMessage: String?
    var commentErrorMessage: String?
    var toastMessage: String?

    private let entryId: String

    init(entryId: String) {
        self.entryId = entryId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await MerianNetworkClient.shared.getFieldTripChallengeEntry(entryId: entryId)
            await loadComments()
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func loadComments() async {
        isLoadingComments = true
        commentErrorMessage = nil
        defer { isLoadingComments = false }

        do {
            comments = try await MerianNetworkClient.shared.getFieldTripChallengeEntryComments(entryId: entryId)
        } catch {
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func toggleLike() async {
        guard var current = detail, !isUpdatingLike else { return }
        isUpdatingLike = true
        defer { isUpdatingLike = false }

        let targetLiked = !current.viewerHasLiked
        current.viewerHasLiked = targetLiked
        current.likeCount = max(0, current.likeCount + (targetLiked ? 1 : -1))
        detail = current

        do {
            let response = try await MerianNetworkClient.shared.setFieldTripChallengeEntryLike(
                entryId: entryId,
                liked: targetLiked
            )
            current.viewerHasLiked = response.viewerHasLiked
            current.likeCount = response.likeCount
            if let commentCount = response.commentCount {
                current.commentCount = commentCount
            }
            detail = current
            HapticManager.shared.triggerSelectionPulse()
        } catch {
            current.viewerHasLiked.toggle()
            current.likeCount = max(0, current.likeCount + (targetLiked ? -1 : 1))
            detail = current
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func submitComment() async {
        guard var current = detail, !isSubmittingComment else { return }
        let trimmed = String(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { return }

        isSubmittingComment = true
        commentErrorMessage = nil
        let previousDraft = commentDraft
        commentDraft = ""
        defer { isSubmittingComment = false }

        do {
            let response = try await MerianNetworkClient.shared.createFieldTripChallengeEntryComment(
                entryId: entryId,
                body: trimmed
            )
            comments.append(response.comment)
            current.commentCount = response.commentCount
            detail = current
            HapticManager.shared.triggerSuccessPulse()
        } catch {
            commentDraft = previousDraft
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
            HapticManager.shared.triggerErrorThump()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
