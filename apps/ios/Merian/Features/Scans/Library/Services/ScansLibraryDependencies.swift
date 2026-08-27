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

        return Self(
            events: events,
            sharedPostID: sharedPostID,
            batchShare: { scans in
                await withCheckedContinuation { continuation in
                    InsightMediaExportManager.shared.batchShareDiscovery(records: scans) { items in
                        ShareSheetUtility.present(items: items)
                        continuation.resume()
                    }
                }
            },
            batchSaveMedia: { scans in
                await withCheckedContinuation { continuation in
                    InsightMediaExportManager.shared.batchSaveUserMedia(records: scans) { result in
                        continuation.resume(returning: result)
                    }
                }
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
