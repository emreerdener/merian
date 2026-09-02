import Foundation
import SwiftData

/// Adapts one live response to the existing parsing/persistence actor.
///
/// The actor remains authoritative for durable completion. The engine supplies
/// exact-attempt validation and retains presentation, queue retirement, discovery
/// feedback, replacement metadata, and post-result effects.
struct InferenceLiveResultService {
    struct Dependencies {
        let parseAndSave:
            @MainActor (PersistenceRequest) async throws
                -> InferenceProcessingActor.ParseAndSaveResult
    }

    enum Media: Sendable {
        case visual(compressedImages: [Data], displayImages: [Data])
        case nonVisual
    }

    /// Main-actor input: the model context is forwarded to the existing actor
    /// adapter, never stored by the service or made unchecked-Sendable.
    struct Request {
        let response: InferenceLiveRequestService.Response
        let telemetry: CaptureTelemetry
        let media: Media
        let mediaTimeline: [CaptureSubmissionMediaItem]
        let submissionProjection: CaptureSubmissionMediaProjection
        let modelContext: ModelContext?
        let persistenceFence: LiveInferencePersistenceFence?
    }

    struct PersistenceRequest {
        let resultData: Data
        let telemetry: CaptureTelemetry
        let modelContext: ModelContext?
        let compressedDatas: [Data]
        let displayDatas: [Data]
        let skipImageRequirement: Bool
        let observationContextsJSON: [String]
        let audioFilePaths: [String]?
        let videoFilePaths: [String]?
        let mediaTimeline: [CaptureSubmissionMediaItem]
        let persistenceFence: LiveInferencePersistenceFence?
    }

    struct CompletedResult {
        let speciesData: SpeciesData
        let isNewDiscovery: Bool
        let savedImagePaths: [String]
        let planUsed: String?
    }

    enum Outcome {
        case persisted(CompletedResult)
        case completedWithoutRecord(CompletedResult)
        case persistenceRejected

        /// Confidence-zero completion still publishes its result and finalizes
        /// the exact queue owner. Only rejected persistence withholds those effects.
        var completedResult: CompletedResult? {
            switch self {
            case .persisted(let result), .completedWithoutRecord(let result):
                return result
            case .persistenceRejected:
                return nil
            }
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    static let live = InferenceLiveResultService(
        dependencies: Dependencies(
            parseAndSave: { request in
                try await InferenceProcessingActor.shared.parseAndSave(
                    resultData: request.resultData,
                    telemetry: request.telemetry,
                    modelContext: request.modelContext,
                    compressedDatas: request.compressedDatas,
                    displayDatas: request.displayDatas,
                    skipImageRequirement: request.skipImageRequirement,
                    observationContextsJSON: request.observationContextsJSON,
                    audioFilePaths: request.audioFilePaths,
                    videoFilePaths: request.videoFilePaths,
                    mediaTimeline: request.mediaTimeline,
                    persistenceFence: request.persistenceFence
                )
            }
        )
    )

    @MainActor
    func process(
        _ request: Request,
        validateAttempt: @MainActor () throws -> Void
    ) async throws -> Outcome {
        try validateAttempt()
        let parsed = try await dependencies.parseAndSave(
            persistenceRequest(from: request)
        )
        try validateAttempt()

        // Do not infer completion from confidence alone: even confidence-zero
        // results must pass the actor's exact scan-ID persistence fence.
        guard parsed.didCompletePersistence,
              let mappedData = parsed.mappedData else {
            return .persistenceRejected
        }
        let result = CompletedResult(
            speciesData: mappedData,
            isNewDiscovery: parsed.isNewDiscovery,
            savedImagePaths: parsed.savedPaths,
            planUsed: parsed.planUsed
        )
        return mappedData.confidenceScore <= 0
            ? .completedWithoutRecord(result)
            : .persisted(result)
    }

    private func persistenceRequest(from request: Request) -> PersistenceRequest {
        let compressedDatas: [Data]
        let displayDatas: [Data]
        let skipImageRequirement: Bool
        switch request.media {
        case .visual(let compressedImages, let displayImages):
            compressedDatas = compressedImages
            displayDatas = displayImages
            skipImageRequirement = false
        case .nonVisual:
            compressedDatas = []
            displayDatas = []
            skipImageRequirement = true
        }

        return PersistenceRequest(
            resultData: request.response.resultData,
            telemetry: request.telemetry,
            modelContext: request.modelContext,
            compressedDatas: compressedDatas,
            displayDatas: displayDatas,
            skipImageRequirement: skipImageRequirement,
            observationContextsJSON: request.response.observationContextsJSON,
            audioFilePaths: request.submissionProjection.audioFilePaths.isEmpty
                ? nil
                : request.submissionProjection.audioFilePaths,
            videoFilePaths: request.submissionProjection.videoFilePaths.isEmpty
                ? nil
                : request.submissionProjection.videoFilePaths,
            mediaTimeline: request.mediaTimeline,
            persistenceFence: request.persistenceFence
        )
    }
}
