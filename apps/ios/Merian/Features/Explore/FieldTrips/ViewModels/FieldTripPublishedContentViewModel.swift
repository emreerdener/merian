import Foundation
import Observation

@MainActor
@Observable
final class FieldTripPublishedContentViewModel {
    static let commentCharacterLimit = 500

    struct Dependencies {
        let endpoint: FieldTripPublishedContentEndpoint
        let selectionFeedback: @MainActor () -> Void
        let successFeedback: @MainActor () -> Void
        let errorFeedback: @MainActor () -> Void
        let errorMessage: @MainActor (Error) -> String

        static func live(endpoint: FieldTripPublishedContentEndpoint) -> Self {
            Self(
                endpoint: endpoint,
                selectionFeedback: { HapticManager.shared.triggerSelectionPulse() },
                successFeedback: { HapticManager.shared.triggerSuccessPulse() },
                errorFeedback: { HapticManager.shared.triggerErrorThump() },
                errorMessage: { ExploreErrorFormatter.message(for: $0) }
            )
        }
    }

    var content: FieldTripPublishedContent?
    var comments: [ExploreComment] = []
    var commentDraft = ""
    var isLoading = false
    var isLoadingComments = false
    var isSubmittingComment = false
    var isUpdatingLike = false
    var errorMessage: String?
    var commentErrorMessage: String?
    var toastMessage: ToastPayload?

    private let dependencies: Dependencies

    init(endpoint: FieldTripPublishedContentEndpoint) {
        dependencies = .live(endpoint: endpoint)
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var canSubmitComment: Bool {
        !normalizedCommentBody.isEmpty
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            content = try await dependencies.endpoint.loadContent()
            await loadComments()
        } catch {
            errorMessage = dependencies.errorMessage(error)
        }
    }

    func loadComments() async {
        isLoadingComments = true
        commentErrorMessage = nil
        defer { isLoadingComments = false }

        do {
            comments = try await dependencies.endpoint.loadComments()
        } catch {
            commentErrorMessage = dependencies.errorMessage(error)
        }
    }

    func toggleLike() async {
        guard let originalContent = content, !isUpdatingLike else { return }
        isUpdatingLike = true
        defer { isUpdatingLike = false }

        let targetLiked = !originalContent.viewerHasLiked
        var optimisticContent = originalContent
        optimisticContent.viewerHasLiked = targetLiked
        optimisticContent.likeCount = max(
            0,
            originalContent.likeCount + (targetLiked ? 1 : -1)
        )
        content = optimisticContent

        do {
            let response = try await dependencies.endpoint.setLike(targetLiked)
            optimisticContent.viewerHasLiked = response.viewerHasLiked
            optimisticContent.likeCount = response.likeCount
            if let commentCount = response.commentCount {
                optimisticContent.commentCount = commentCount
            }
            content = optimisticContent
            dependencies.selectionFeedback()
        } catch {
            content = originalContent
            dependencies.errorFeedback()
            toastMessage = .error(dependencies.errorMessage(error))
        }
    }

    func submitComment() async {
        guard var currentContent = content, !isSubmittingComment else { return }
        let body = normalizedCommentBody
        guard !body.isEmpty else { return }

        isSubmittingComment = true
        commentErrorMessage = nil
        let previousDraft = commentDraft
        commentDraft = ""
        defer { isSubmittingComment = false }

        do {
            let response = try await dependencies.endpoint.createComment(body)
            comments.append(response.comment)
            currentContent.commentCount = response.commentCount
            content = currentContent
            dependencies.successFeedback()
        } catch {
            commentDraft = previousDraft
            commentErrorMessage = dependencies.errorMessage(error)
            dependencies.errorFeedback()
        }
    }

    private var normalizedCommentBody: String {
        String(
            commentDraft
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.commentCharacterLimit)
        )
    }
}
