import Combine
import Foundation

struct ScansLibraryDependencies {
    let events: AnyPublisher<AppEvent, Never>
    let sharedPostID: @MainActor (_ scanID: String) -> String?
    let batchShare: @MainActor (_ scans: [LocalScanRecord]) async -> Void
    let batchSaveMedia: @MainActor (_ scans: [LocalScanRecord]) async -> MediaSaveResult
    let shareToExplore: @MainActor (_ scan: LocalScanRecord) async throws -> String
    let storeSharedPostID: @MainActor (_ postID: String, _ scanID: String) -> Void
    let sendExploreShareChanged: @MainActor (_ scanID: String, _ postID: String?) -> Void
    let triggerSelectionFeedback: @MainActor () -> Void
    let triggerMediumFeedback: @MainActor () -> Void
    let triggerLightFeedback: @MainActor () -> Void
    let triggerSuccessFeedback: @MainActor () -> Void
    let triggerErrorFeedback: @MainActor () -> Void
    let exploreShareErrorMessage: @MainActor (_ error: Error) -> String

    @MainActor
    static func live(
        sharedPostID: @escaping @MainActor (_ scanID: String) -> String?,
        eventStream: (any AppEventStreaming)?
    ) -> Self {
        let container = AppDIContainer.shared
        let events = (eventStream ?? container.appEventPublisher).publisher
        let mediaExportService = MediaExportService.live

        return Self(
            events: events,
            sharedPostID: sharedPostID,
            batchShare: { scans in
                let request = BatchDiscoveryShareRequest(
                    discoveries: scans.map { scan in
                        let petLabel = scan.petIdentification?.label
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return BatchDiscoveryShareRequest.Discovery(
                            commonName: petLabel?.isEmpty == false
                                ? petLabel ?? scan.commonName
                                : scan.commonName,
                            scientificName: scan.scientificName,
                            primaryImageReference: scan.capturedMediaSnapshot
                                .primaryImagePath,
                            fallbackImageReference: scan.referenceImageUrl
                        )
                    }
                )
                let payload = await mediaExportService.prepareBatchShare(
                    request
                )
                guard !Task.isCancelled else { return }
                ShareSheetUtility.present(items: payload.activityItems)
            },
            batchSaveMedia: { scans in
                let requests = scans.map { scan in
                    let media = scan.capturedMediaSnapshot.activeScanMedia
                    return MediaSaveRequest.make(
                        liveImageData: nil,
                        imagePaths: media.imagePathsForUpload,
                        videoPaths: media.videoPaths,
                        referenceImageURL: scan.referenceImageUrl
                    )
                }
                return await mediaExportService.batchSave(requests)
            },
            shareToExplore: { scan in
                try await MerianNetworkClient.shared.shareScanToExplore(scan: scan).postId
            },
            storeSharedPostID: { postID, scanID in
                ExploreShareStateStore.setSharedPostId(postID, for: scanID)
            },
            sendExploreShareChanged: { scanID, postID in
                container.appEventPublisher.send(
                    .exploreShareStateChanged(scanId: scanID, postId: postID)
                )
            },
            triggerSelectionFeedback: {
                container.hapticManager.triggerSelectionPulse()
            },
            triggerMediumFeedback: {
                container.hapticManager.triggerMediumPulse()
            },
            triggerLightFeedback: {
                container.hapticManager.triggerLightImpact(intensity: 0.5)
            },
            triggerSuccessFeedback: {
                container.hapticManager.triggerSuccessPulse()
            },
            triggerErrorFeedback: {
                container.hapticManager.triggerErrorThump()
            },
            exploreShareErrorMessage: { error in
                ExploreErrorFormatter.titledMessage("Couldn’t share to Explore", for: error)
            }
        )
    }

    static func liveSharedPostID(for scanID: String) -> String? {
        ExploreShareStateStore.sharedPostId(for: scanID)
    }
}
