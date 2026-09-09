import Foundation

/// Decodes and maps one validated inference response without performing local
/// persistence.
///
/// This service is stateless so foreground and background completion can share
/// response semantics without serializing on the persistence actor or on one
/// another.
struct InferenceResponsePreparationService: Sendable {
    struct PreparedResponse: Sendable {
        let mappedData: SpeciesData
        let planUsed: String?
    }

    static let live = InferenceResponsePreparationService()

    func prepare(
        resultData: Data,
        telemetry: CaptureTelemetry?,
        audioFilePaths: [String]?,
        videoFilePaths: [String]?
    ) async throws -> PreparedResponse {
        let parseStartedAt = CFAbsoluteTimeGetCurrent()
        let parsedWrapper: EdgeResponseWrapper
        do {
            parsedWrapper = try JSONDecoder().decode(
                EdgeResponseWrapper.self,
                from: resultData
            )
        } catch let error as DecodingError {
            MerianLog.general.debug(
                "AI JSON decoding error: \(error.localizedDescription, privacy: .private)"
            )
            throw MerianError.decodingFailed
        }
        guard IdentifySuccessEnvelopeValidator.isUsable(parsedWrapper) else {
            MerianLog.general.debug(
                "AI response decoded but failed the client success boundary."
            )
            throw MerianError.decodingFailed
        }

        await reconcileEntitlement(from: parsedWrapper)

        var mappedData = SpeciesData(
            fromEdgeResponse: parsedWrapper.data,
            locationName: telemetry?.locationName,
            weatherCondition: telemetry?.weatherCondition,
            weatherTemperatureF: telemetry?.weatherTemperatureF,
            gpsElevation: telemetry?.gpsElevation,
            gpsLatitude: telemetry?.gpsLatitude,
            gpsLongitude: telemetry?.gpsLongitude
        )
        mappedData.zoomFactor = telemetry?.zoomFactor.map { Double($0) }
        mappedData.audioFilePaths = audioFilePaths
        mappedData.videoFilePaths = videoFilePaths
        MerianLog.general.debug(
            "[⏱ BENCH] Response parsing: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - parseStartedAt), privacy: .public)s bytes=\(resultData.count, privacy: .public)"
        )

        try Task.checkCancellation()
        return PreparedResponse(
            mappedData: mappedData,
            planUsed: parsedWrapper.entitlement?.planUsed
        )
    }

    private func reconcileEntitlement(
        from parsedWrapper: EdgeResponseWrapper
    ) async {
        guard let metadata = parsedWrapper.entitlement else { return }
        await MainActor.run {
            _ = EntitlementManager.shared.apply(metadata)
            guard let scanId = parsedWrapper.data.scan_id else { return }
            UsageManager.shared.reconcileServerPlanUsed(
                metadata.planUsed,
                scanId: scanId
            )
            EntitlementManager.shared.recordCompletedFunding(
                planUsed: metadata.planUsed,
                creditConsumed: metadata.creditConsumed,
                scanId: scanId
            )
            Task { @MainActor in
                await OfflineQueueManager.shared
                    .reconcileDeferredFundingReservations()
                OfflineQueueManager.shared.syncPendingScans()
                OfflineQueueManager.shared.replayInferenceForUploadedScans()
            }
        }
    }
}
