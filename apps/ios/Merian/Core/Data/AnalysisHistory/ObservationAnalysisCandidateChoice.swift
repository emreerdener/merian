import CoreFoundation
import Foundation

/// Presentation data paired with its original immutable array position before any swipe or filtering.
struct ObservationAnalysisCandidateChoice: Equatable, Sendable, Identifiable {
    let reference: ObservationAnalysisCandidateReference
    let display: IdentificationCandidate
    var id: Int { reference.ordinal }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.reference == rhs.reference && lhs.display.confidenceScore == rhs.display.confidenceScore
            && lhs.display.commonName == rhs.display.commonName && lhs.display.distinguishingFeature == rhs.display.distinguishingFeature
    }
    static func extract(result: [String: Any], version: Int, analysisID: UUID) -> [Self] {
        guard (1...2).contains(version), let primary = result["primary_identification"] as? [String: Any],
              primary["resolution"] as? String == "species", let raw = result["candidates"] as? [[String: Any]],
              (1...2).contains(raw.count), raw.allSatisfy({ $0["taxon_rank"] as? String == "species" }) else { return [] }
        return raw.enumerated().compactMap { ordinal, candidate in
            guard let name = candidate["scientific_name"] as? String,
                  let reference = try? ObservationAnalysisCandidateReference(analysisID: analysisID, ordinal: ordinal, scientificName: name),
                  let score = candidate["confidence_score"] as? NSNumber, CFGetTypeID(score) != CFBooleanGetTypeID(),
                  score.doubleValue.isFinite, (0...1).contains(score.doubleValue) else { return nil }
            return Self(reference: reference, display: .init(scientificName: name, commonName: candidate["common_name"] as? String,
                confidenceScore: score.doubleValue, distinguishingFeature: candidate["distinguishing_feature"] as? String))
        }
    }
}
