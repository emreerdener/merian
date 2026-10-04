import Foundation

/// Builds display solely from a validated immutable result. Imported V3 saved
/// identifications lack a complete result, so they deliberately return no display.
/// SavedIdentificationDisplayBaseline owns the separate device-local V3 cache.
enum ObservationHistoryDisplayProjection {
    /// Cached display is usable only when its provenance still matches evidence.
    static func restore(_ data: Data, matching result: ObservationHistoryPage.Result) throws -> AnalysisDisplaySnapshot {
        let display: AnalysisDisplaySnapshot
        let expected: Data?
        if result.version == 3 {
            display = try SavedIdentificationDisplayBaseline.restore(data, analysisID: result.analysisID)
            expected = try SavedIdentificationDisplayBaseline.capture(display, matching: result)
        } else {
            display = try AnalysisDisplaySnapshot.restore(data, analysisID: result.analysisID)
            expected = try snapshot(result)
        }
        guard expected == data else { throw ObservationHistoryError.resultConflict }
        return display
    }

    static func snapshot(_ result: ObservationHistoryPage.Result) throws -> Data? {
        guard result.version != 3 else { return nil }
        guard let envelope = try JSONSerialization.jsonObject(with: result.bytes) as? [String: Any],
              let payload = envelope["result"] as? [String: Any] else { throw ObservationHistoryError.invalidSnapshot }
        let response = try JSONDecoder().decode(EdgeResponse.self, from: JSONSerialization.data(withJSONObject: payload))
        let mapped = SpeciesData(fromEdgeResponse: response, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)
        let date = result.completedAt ?? Date(timeIntervalSince1970: 0)
        // No previous selection's dictionary ID or observation context is borrowed.
        let record = LocalScanRecordFactory.makeRecord(from: mapped, recordId: result.analysisID.uuidString,
            speciesId: "", timestamp: date, captureDate: date, capturedMediaJSON: nil,
            coverImagePath: nil, isLiveCapture: false, fieldNotes: nil)
        record.wikipediaOverview = mapped.wikipediaOverview
        record.candidatesData = try mapped.candidates.map { try JSONEncoder().encode($0) }
        record.petIdentificationData = try mapped.petIdentification.map { try JSONEncoder().encode($0) }
        return try AnalysisDisplaySnapshot(analysisID: result.analysisID, record: record).storedData()
    }
}
