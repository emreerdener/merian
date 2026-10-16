import Foundation

/// Builds display solely from a validated immutable result. Imported V3 saved
/// identifications lack a complete result, so they deliberately return no display.
/// SavedIdentificationDisplayBaseline owns the separate device-local V3 cache.
enum ObservationHistoryDisplayProjection {
    /// Cached display is usable only when its provenance still matches evidence.
    static func restore(_ data: Data, matching result: ObservationHistoryPage.Result) throws -> AnalysisDisplaySnapshot {
        if result.version == 3 {
            let display = try SavedIdentificationDisplayBaseline.restore(data, analysisID: result.analysisID)
            guard try SavedIdentificationDisplayBaseline.capture(display, matching: result) == data else {
                throw ObservationHistoryError.resultConflict
            }
            return display
        }
        // Earlier caches embedded unsorted JSON bytes. Key order/whitespace in those
        // two payloads cannot invalidate otherwise identical immutable evidence.
        _ = try AnalysisDisplaySnapshot.restore(data, analysisID: result.analysisID)
        guard let expected = try snapshot(result), try comparable(data) == comparable(expected) else {
            throw ObservationHistoryError.resultConflict
        }
        // Render only the trusted rederivation, never reparsed legacy nested bytes.
        return try AnalysisDisplaySnapshot.restore(expected, analysisID: result.analysisID)
    }

    private static func comparable(_ data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ObservationHistoryError.invalidSnapshot
        }
        for key in ["candidatesData", "petIdentificationData"] {
            if object[key] is NSNull { continue }
            guard let encoded = object[key] as? String, let nested = Data(base64Encoded: encoded) else {
                throw ObservationHistoryError.invalidSnapshot
            }
            let value = try JSONSerialization.jsonObject(with: nested)
            object[key] = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).base64EncodedString()
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        record.candidatesData = try mapped.candidates.map { try encoder.encode($0) }
        record.petIdentificationData = try mapped.petIdentification.map { try encoder.encode($0) }
        return try AnalysisDisplaySnapshot(analysisID: result.analysisID, record: record).storedData()
    }
}
