import Foundation

/// Bounded private manifest decoder. Original JSON bytes are retained without assigning a request or digest.
struct ObservationVideoManifest: Equatable, Sendable {
    let provenance: ObservationVideoProvenance
    let descriptions: [String]
    let originalBytes: Data

    init(data: Data, observationID: UUID, analysisID: UUID) throws {
        guard !data.isEmpty, data.count <= 1_044_480 else { throw ObservationHistoryError.invalidSnapshot }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys: ["schema_version", "provenance", "descriptions"])
        guard try ObservationVideoProvenance.number(row["schema_version"], 4...4) == 4,
              let texts = row["descriptions"] as? [String], texts.count <= 64 else { throw ObservationHistoryError.invalidSnapshot }
        var units = 0
        for text in texts {
            guard ObservationHistoryAudioReference.hasDescriptionContent(text), text.unicodeScalars.count <= 8192,
                  text.utf16.count <= 16384, text.utf16.count <= 32000 - units else { throw ObservationHistoryError.invalidSnapshot }
            units += text.utf16.count
        }
        provenance = try ObservationVideoProvenance.decode(row["provenance"], observationID: observationID, analysisID: analysisID)
        descriptions = texts
        originalBytes = data
    }
}
