import Foundation

/// Immutable account/funding effects carried only by a response whose scan
/// identity matches the caller's expected owner.
struct InferenceResponseSettlement: Sendable {
    let scanId: String
    let accountId: UUID
    let planUsed: String
    let creditConsumed: Bool
    let entitlementAfter: EntitlementStateSnapshot

    init?(scanId: String, metadata: ScanEntitlementMetadataDTO) {
        guard let accountId = UUID(uuidString: metadata.userID) else {
            return nil
        }
        self.scanId = scanId
        self.accountId = accountId
        planUsed = metadata.planUsed
        creditConsumed = metadata.creditConsumed
        entitlementAfter = EntitlementStateSnapshot(metadata.entitlementAfter)
    }
}

/// Decodes and maps one validated inference response without performing local
/// persistence or account-sensitive effects.
///
/// This service is stateless so foreground and background completion can share
/// response semantics without serializing on the persistence actor or on one
/// another.
struct InferenceResponsePreparationService: Sendable {
    struct PreparedResponse: Sendable {
        let mappedData: SpeciesData
        let planUsed: String?
        let fundingSettlement: InferenceResponseSettlement?
        let responseMatchesExpectedScanId: Bool
    }

    static let live = InferenceResponsePreparationService()

    func prepare(
        resultData: Data,
        telemetry: CaptureTelemetry?,
        audioFilePaths: [String]?,
        videoFilePaths: [String]?,
        expectedScanId: String?
    ) async throws -> PreparedResponse {
        try Task.checkCancellation()
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
        guard let responseScanId = parsedWrapper.data.scan_id else {
            throw MerianError.decodingFailed
        }
        let responseMatchesExpectedScanId = expectedScanId.map {
            responseScanId.caseInsensitiveCompare($0) == .orderedSame
        } ?? true

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
            planUsed: parsedWrapper.entitlement?.planUsed,
            fundingSettlement: responseMatchesExpectedScanId
                ? parsedWrapper.entitlement.flatMap {
                    InferenceResponseSettlement(
                        scanId: responseScanId,
                        metadata: $0
                    )
                }
                : nil,
            responseMatchesExpectedScanId: responseMatchesExpectedScanId
        )
    }
}
