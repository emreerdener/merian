import Foundation

/// Explicit export fields: no owner IDs, location, field notes, or raw context.
struct DiscoveryShareSummary: Sendable, Equatable {
    var reasoning: String?
    var confidence: Double?
    var scanDate: Date?

    func text(commonName: String, scientificName: String) -> String {
        var sections = ["\(commonName) (\(scientificName))", "Identified with Naturebook"]
        if let scanDate {
            sections.append("Scan date: \(scanDate.formatted(date: .abbreviated, time: .omitted))")
        }
        if let confidence, confidence.isFinite, (0...1).contains(confidence) {
            sections.append("AI confidence: \(Int((confidence * 100).rounded()))%")
        }
        if let reasoning = reasoning?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reasoning.isEmpty {
            sections.append("AI identification reasoning:\n\(reasoning)")
        }
        return sections.joined(separator: "\n\n")
    }
}
