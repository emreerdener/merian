import Foundation
import SwiftData

extension InferenceLivePipelineCoordinator {
    enum Modality: Equatable, Sendable {
        case visual
        case nonVisual(hasAudio: Bool)

        var failureMode: InferenceLiveFailurePolicy.Mode {
            switch self {
            case .visual:
                .visual
            case .nonVisual(let hasAudio):
                .nonVisual(hasAudio: hasAudio)
            }
        }

        var persistenceRejectionReason: String {
            switch self {
            case .visual:
                "live_result_persistence_rejected"
            case .nonVisual:
                "live_nonvisual_persistence_rejected"
            }
        }
    }

    enum AdmissionIssue: Equatable, Sendable {
        case missingForegroundOwner(scanId: String)
        case duplicateForegroundOwner(scanId: String)
        case unavailableForegroundOwner(scanId: String)
        case foregroundOwnerWithoutScan
    }

    enum Benchmark: Equatable, Sendable {
        case tapToFirstRenderedFrame(TimeInterval)
        case responseToFirstResult(TimeInterval)
        case postFlight(TimeInterval)
        case total(TimeInterval)
    }

    struct Session: Equatable, Sendable {
        let scanId: String?
        let resolvedClientScanId: String
        let attemptGeneration: UUID
        let foregroundGeneration: UUID?
        let modality: Modality
        var isProFunded: Bool = false

        var durableQueueOwnsRecovery: Bool {
            foregroundGeneration != nil
        }

        var persistenceFence: LiveInferencePersistenceFence? {
            guard let scanId, let foregroundGeneration else { return nil }
            return LiveInferencePersistenceFence(
                scanId: scanId,
                generation: foregroundGeneration
            )
        }
    }

    struct VisualRequest {
        let session: Session
        let compressedImages: [Data]
        let displayImages: [Data]
        let submissionProjection: CaptureSubmissionMediaProjection
        let ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]?
        let mediaTimeline: [CaptureSubmissionMediaItem]
        let visualMediaItems: [IdentifyVisualMediaItem]?
        let telemetry: CaptureTelemetry
        let preferredGoal: FieldTripPreferredGoal?
        let modelContext: ModelContext?
        let targetEradicationScanId: String?
    }

    struct NonVisualRequest {
        let session: Session
        let submissionProjection: CaptureSubmissionMediaProjection
        let ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]?
        let mediaTimeline: [CaptureSubmissionMediaItem]
        let telemetry: CaptureTelemetry
        let modelContext: ModelContext?
        let targetEradicationScanId: String?
    }

    struct Callbacks {
        let finish: @MainActor (Session) -> Void
        let publishCompletion:
            @MainActor (
                InferenceLiveCompletionCoordinator.PreparedCompletion
            ) -> Bool
        let scheduleHydration: @MainActor (SpeciesData) -> Void
        let applyFailure:
            @MainActor (
                InferenceLiveFailureCoordinator.PresentationAction
            ) -> Void
    }

    struct VisualCallbacks {
        let shared: Callbacks
        let cancelLocalAnalysis: @MainActor () -> Void
        let markRequestBodySent: @MainActor @Sendable (Session) -> Void
    }
}
