import Foundation

/// Coordinates response preparation and SwiftData finalization for one
/// completed background inference task.
///
/// The service owns the cross-domain workflow. Response preparation stays with
/// `InferenceResponsePreparationService`, while every model read and write
/// stays with the injected `BackgroundDatabaseActor`.
struct BackgroundInferenceFinalizationService: Sendable {
    struct DecodeRequest: Sendable {
        let resultData: Data
        let telemetry: CaptureTelemetry?
        let audioFilePaths: [String]?
        let videoFilePaths: [String]?
    }

    struct Dependencies: Sendable {
        let decodeResponse: @Sendable (
            DecodeRequest
        ) async throws -> InferenceResponsePreparationService.PreparedResponse
    }

    static let live = BackgroundInferenceFinalizationService(
        dependencies: Dependencies { request in
            try await InferenceResponsePreparationService.live.prepare(
                resultData: request.resultData,
                telemetry: request.telemetry,
                audioFilePaths: request.audioFilePaths,
                videoFilePaths: request.videoFilePaths
            )
        }
    )

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func processAndCleanupOfflineScan(
        resultData: Data,
        originalImagePaths: [String],
        scanId: String,
        originalTimestamp: Date,
        telemetry: CaptureTelemetry? = nil,
        observationContextsJSON: [String]? = nil,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        capturedMediaJSON: String? = nil,
        expectedGeneration: UUID? = nil,
        persistenceActor: BackgroundDatabaseActor
    ) async -> OfflineScanProcessingResult {
        await ScanInferencePersistenceCoordinator.shared.acquire(
            scanId: scanId
        )
        let result = await processAssumingPersistenceLock(
            resultData: resultData,
            originalImagePaths: originalImagePaths,
            scanId: scanId,
            originalTimestamp: originalTimestamp,
            telemetry: telemetry,
            observationContextsJSON: observationContextsJSON,
            audioFilePaths: audioFilePaths,
            videoFilePaths: videoFilePaths,
            capturedMediaJSON: capturedMediaJSON,
            expectedGeneration: expectedGeneration,
            persistenceActor: persistenceActor
        )
        await ScanInferencePersistenceCoordinator.shared.release(
            scanId: scanId
        )
        return result
    }

    private func processAssumingPersistenceLock(
        resultData: Data,
        originalImagePaths: [String],
        scanId: String,
        originalTimestamp: Date,
        telemetry: CaptureTelemetry?,
        observationContextsJSON: [String]?,
        audioFilePaths: [String]?,
        videoFilePaths: [String]?,
        capturedMediaJSON: String?,
        expectedGeneration: UUID?,
        persistenceActor: BackgroundDatabaseActor
    ) async -> OfflineScanProcessingResult {
        guard !Task.isCancelled else { return .notProcessed }
        if let expectedGeneration,
           !(await persistenceActor
               .validateOrAdoptInferenceGenerationAssumingPersistenceLock(
                   scanId: scanId,
                   expectedGeneration: expectedGeneration
               )) {
            MerianLog.data.debug(
                "Background inference finalization rejected a durable generation mismatch scanId=\(scanId, privacy: .public)"
            )
            return .notProcessed
        }

        let mappedData: SpeciesData
        do {
            mappedData = try await dependencies.decodeResponse(DecodeRequest(
                resultData: resultData,
                telemetry: telemetry,
                audioFilePaths: audioFilePaths,
                videoFilePaths: videoFilePaths
            )).mappedData
        } catch {
            MerianLog.data.debug(
                "Background inference finalization could not decode a usable response scanId=\(scanId, privacy: .public) error=\(error, privacy: .private)"
            )
            return .notProcessed
        }

        guard !Task.isCancelled else { return .notProcessed }
        if expectedGeneration != nil,
           mappedData.scanId?.caseInsensitiveCompare(scanId) != .orderedSame {
            MerianLog.data.debug(
                "Background inference finalization rejected a response scan ID mismatch scanId=\(scanId, privacy: .public)"
            )
            return .notProcessed
        }

        return await persistenceActor
            .persistOfflineScanResultAssumingPersistenceLock(
                mappedData: mappedData,
                originalImagePaths: originalImagePaths,
                scanId: scanId,
                originalTimestamp: originalTimestamp,
                observationContextsJSON: observationContextsJSON,
                audioFilePaths: audioFilePaths,
                videoFilePaths: videoFilePaths,
                capturedMediaJSON: capturedMediaJSON
            )
    }
}
