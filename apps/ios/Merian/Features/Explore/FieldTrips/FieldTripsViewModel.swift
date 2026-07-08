import Foundation
import Observation

@MainActor
@Observable
final class FieldTripsViewModel {
    var templates: [FieldTripTemplate] = []
    var isLoading = false
    var errorMessage: String?
    var toastMessage: String?

    private var didLoad = false

    func load(userRegion: String? = nil, force: Bool = false) async {
        guard force || !didLoad else { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            didLoad = true
        }

        do {
            templates = try await MerianNetworkClient.shared.getFieldTrips(userRegion: userRegion)
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func refresh(userRegion: String? = nil) async {
        await load(userRegion: userRegion, force: true)
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
