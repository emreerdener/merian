import Foundation
import SwiftData

extension InsightSheetViewModel {
    func requestCommunityIdentification(
        note: String?,
        locationSharing: ExplorePostLocationSharing,
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext
    ) async {
        guard canRequestCommunityIdentification,
              isPresentingLocalRecord(
                  scanId: expectedScanId,
                  generation: expectedGeneration
              ),
              let record = fetchActiveLocalRecord(
                  modelContext: modelContext
              ),
              record.id.caseInsensitiveCompare(expectedScanId) ==
                .orderedSame,
              !state.isRequestingCommunityIdentification else { return }

        let scanId = record.id
        let generation = scanBoundActionGeneration
        state.isRequestingCommunityIdentification = true
        defer {
            if generation == scanBoundActionGeneration {
                state.isRequestingCommunityIdentification = false
            }
        }

        do {
            let request = try await sharingDependencies
                .requestCommunityIdentification(
                    record,
                    activeMedia.liveImageData,
                    resolvedHeaderTitle,
                    note,
                    locationSharing
                )
            sharingDependencies.storeCachedPostID(nil, scanId)
            sharingDependencies.publishShareStateChanged(scanId, nil)
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return }
            sharingOperations.recordMutation()
            state.sharedExplorePostId = nil
            state.isExploreFeedVisible = false
            state.sharedCommunityIdentificationRequestId = request.id
            state.sharedCommunityIdentificationStatus = request.status
            state.sharedExploreLocationSharing = locationSharing
            state.isCommunityRequestSheetPresented = false
            state.communityRequestPresentationScanId = nil
            state.communityRequestPresentationGeneration = nil
            state.communityRequestPresentationRequestId = nil
            sharingDependencies.successFeedback()
            state.toastMessage = .success(
                "Asked the community",
                action: .viewCommunityRequest
            )
            toastAction = explorePresentationAction(
                target: .communityRequest,
                scanId: scanId,
                generation: generation
            )
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return }
            sharingDependencies.errorFeedback()
            state.toastMessage = .error(
                ExploreErrorFormatter.titledMessage(
                    "Couldn’t ask the community",
                    for: error
                )
            )
        }
    }

    func updateCommunityIdentificationRequest(
        note: String?,
        locationSharing: ExplorePostLocationSharing,
        expectedScanId: String,
        expectedGeneration: UInt64
    ) async {
        guard let scanId = presentedLocalRecordScanId,
              scanId.caseInsensitiveCompare(expectedScanId) == .orderedSame,
              expectedGeneration == scanBoundActionGeneration,
              let requestId =
                state.sharedCommunityIdentificationRequestId,
              !state.isRequestingCommunityIdentification else { return }

        let generation = scanBoundActionGeneration
        state.isRequestingCommunityIdentification = true
        defer {
            if generation == scanBoundActionGeneration {
                state.isRequestingCommunityIdentification = false
            }
        }

        do {
            _ = try await sharingDependencies
                .updateCommunityIdentificationRequest(
                    requestId,
                    note,
                    locationSharing
                )
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
            state.sharedCommunityIdentificationRequestId?
                .caseInsensitiveCompare(requestId) == .orderedSame else {
                return
            }
            sharingOperations.recordMutation()
            state.sharedExploreLocationSharing = locationSharing
            state.isCommunityRequestSheetPresented = false
            state.communityRequestPresentationScanId = nil
            state.communityRequestPresentationGeneration = nil
            state.communityRequestPresentationRequestId = nil
            sharingDependencies.successFeedback()
            state.toastMessage = .success(
                "Request updated",
                action: .viewCommunityRequest
            )
            toastAction = explorePresentationAction(
                target: .communityRequest,
                scanId: scanId,
                generation: generation
            )
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
            state.sharedCommunityIdentificationRequestId?
                .caseInsensitiveCompare(requestId) == .orderedSame else {
                return
            }
            sharingDependencies.errorFeedback()
            state.toastMessage = .error(
                ExploreErrorFormatter.titledMessage(
                    "Couldn’t update request",
                    for: error
                )
            )
        }
    }
}
