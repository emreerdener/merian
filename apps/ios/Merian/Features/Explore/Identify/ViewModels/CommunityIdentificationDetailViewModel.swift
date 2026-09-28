import Foundation
import Observation

@MainActor
@Observable
final class CommunityIdentificationDetailViewModel {
    struct Dependencies {
        let loadDetail: @MainActor (String) async throws -> CommunityIdentificationDetail
        let updateRequest: @MainActor (CommunityIdentificationUpdateRequest) async throws -> Void
        let reportPost: @MainActor (CommunityIdentificationPostReportRequest) async throws -> Void
        let submitIdentification: @MainActor (CommunityIdentificationSubmissionRequest) async throws -> Void
        let withdrawIdentification: @MainActor (String) async throws -> Void
        let restoreIdentification: @MainActor (String) async throws -> Void
        let currentUserId: @MainActor () -> String?
        let requestDidChange: @MainActor (String) -> Void
        let successFeedback: @MainActor () -> Void
        let selectionFeedback: @MainActor () -> Void
        let errorFeedback: @MainActor () -> Void
        let errorMessage: @MainActor (Error) -> String
        var visibility: ExploreContentVisibilityStore?
    }

    let requestId: String

    var detail: CommunityIdentificationDetail?
    var isLoading = true
    var errorMessage: String?
    var isSubmitting = false
    var isUpdatingRequest = false
    var isReporting = false
    var toastMessage: ToastPayload?

    private let dependencies: Dependencies

    convenience init(requestId: String) {
        self.init(requestId: requestId, dependencies: .live)
    }

    init(
        requestId: String,
        dependencies: Dependencies
    ) {
        self.requestId = requestId
        self.dependencies = dependencies
    }

    func load() async {
        let context = dependencies.visibility?.context
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await dependencies.loadDetail(requestId)
            guard context == dependencies.visibility?.context,
                  dependencies.visibility?.isVisible(postID: loaded.postId) != false else { return }
            detail = loaded
            errorMessage = nil
        } catch {
            errorMessage = dependencies.errorMessage(error)
        }
    }

    func updateRequest(
        note: String?,
        locationSharing: ExplorePostLocationSharing,
        onUpdated: @MainActor () -> Void = {}
    ) async -> Bool {
        guard !isUpdatingRequest else { return false }
        isUpdatingRequest = true
        defer { isUpdatingRequest = false }

        do {
            try await dependencies.updateRequest(
                CommunityIdentificationUpdateRequest(
                    requestId: requestId,
                    note: note,
                    locationSharing: locationSharing
                )
            )
            await load()
            onUpdated()
            dependencies.successFeedback()
            toastMessage = .success("Request updated")
            return true
        } catch {
            dependencies.errorFeedback()
            toastMessage = .error(dependencies.errorMessage(error))
            return false
        }
    }

    func isOwnedByCurrentUser(_ detail: CommunityIdentificationDetail) -> Bool {
        guard let currentUserId = dependencies.currentUserId() else { return false }
        return currentUserId.lowercased() == detail.authorUserId.lowercased()
    }

    func report(_ detail: CommunityIdentificationDetail) async {
        let viewer = dependencies.currentUserId()
        let context = dependencies.visibility?.context
        if let context {
            guard let viewerID = viewer.flatMap(UUID.init(uuidString:)), viewerID == context.viewerID else { return }
        }
        guard !isReporting else { return }
        isReporting = true
        defer { isReporting = false }

        do {
            try await dependencies.reportPost(
                CommunityIdentificationPostReportRequest(
                    postId: detail.postId
                )
            )
            guard viewer == dependencies.currentUserId() else { return }
            if let context {
                guard dependencies.visibility?.viewerID == context.viewerID,
                      dependencies.visibility?.context.accountGeneration == context.accountGeneration else { return }
                dependencies.visibility?.hide(postID: detail.postId, for: context.viewerID)
            }
            self.detail = nil
            errorMessage = "This discovery is no longer available."
            dependencies.successFeedback()
            toastMessage = .success("Report submitted. Thanks!")
        } catch {
            dependencies.errorFeedback()
            toastMessage = .error(dependencies.errorMessage(error))
        }
    }

    func submit(
        taxon: CommunityTaxonSearchResult,
        disagreementMode: CommunityIdentificationDisagreementMode,
        reasoning: String?,
        isGenusBestPossible: Bool,
        onSubmitted: @MainActor () -> Void = {}
    ) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await dependencies.submitIdentification(
                CommunityIdentificationSubmissionRequest(
                    requestId: requestId,
                    taxonId: taxon.taxonId,
                    disagreementMode: disagreementMode,
                    reasoning: reasoning,
                    isGenusBestPossible: isGenusBestPossible
                )
            )
            onSubmitted()
            dependencies.successFeedback()
            await load()
            dependencies.requestDidChange(requestId)
            return true
        } catch {
            dependencies.errorFeedback()
            errorMessage = dependencies.errorMessage(error)
            return false
        }
    }

    func withdraw(identificationId: String) async {
        do {
            try await dependencies.withdrawIdentification(identificationId)
            dependencies.selectionFeedback()
            await load()
            dependencies.requestDidChange(requestId)
        } catch {
            dependencies.errorFeedback()
            errorMessage = dependencies.errorMessage(error)
        }
    }

    func restore(identificationId: String) async {
        do {
            try await dependencies.restoreIdentification(identificationId)
            dependencies.selectionFeedback()
            await load()
            dependencies.requestDidChange(requestId)
        } catch {
            dependencies.errorFeedback()
            errorMessage = dependencies.errorMessage(error)
        }
    }
}
