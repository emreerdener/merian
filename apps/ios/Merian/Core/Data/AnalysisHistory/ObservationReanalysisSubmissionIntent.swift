import Foundation

/// Explicit submission survived verified file preparation. This is not a recipient or inference admission.
struct ObservationReanalysisSubmissionIntent: Equatable, Sendable {
    let preparation: ObservationReanalysisPreparationIntent
    var draft: ObservationReanalysisDraft { preparation.draft }

    func storedData() throws -> Data {
        guard preparation.action == .submit else { throw MerianError.invalidResponse }
        guard var row = try JSONSerialization.jsonObject(with: preparation.storedData()) as? [String: Any] else { throw MerianError.invalidResponse }
        row["version"] = 5; row["phase"] = "admission_pending"
        return try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576,
              var row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = row["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 5,
              row["phase"] as? String == "admission_pending" else { throw MerianError.invalidResponse }
        row["version"] = 4; row["phase"] = "files_pending"
        return try Self(preparation: .decode(JSONSerialization.data(withJSONObject: row)))
    }
}
