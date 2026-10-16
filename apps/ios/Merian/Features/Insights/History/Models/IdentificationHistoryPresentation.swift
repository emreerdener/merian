import Foundation

struct IdentificationHistoryRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let scientificName: String?
    let completedAt: Date?
    let confidence: String?
    let review: String
    let isImported: Bool
}

struct IdentificationHistoryDetail {
    let row: IdentificationHistoryRow
    let reasoning: String?
    let alternatives: [String]
    let evidenceDescription: String?
    let photoIDs: [UUID]
    let canRestore: Bool
    let isCached: Bool
    var reviewTicket: ObservationAnalysisReviewTicket?
    var restoreUnavailableReason: String?
}

struct IdentificationHistoryPage {
    let rows: [IdentificationHistoryRow]
    let nextBeforeOrdinal: Int?
    let context: ObservationHistoryListingService.Context
}

/// History displays each result's own evidence and review. It never borrows the
/// selected scan's title, confidence, photos or confirmation for another row.
enum IdentificationHistoryPresentation {
    static func row(_ entry: ObservationHistoryListingService.Entry) throws -> IdentificationHistoryRow {
        let envelope = try JSONSerialization.jsonObject(with: entry.result.bytes) as? [String: Any]
        let saved = envelope?["result"] as? [String: Any]
        let display = entry.display
        let scientific = entry.authority?.speciesReview?.identity?.scientificName ?? entry.authority?.aiReview?.community?.scientific_name ?? display?.scientificName
        let common: String?
        if let identity = entry.authority?.speciesReview?.identity {
            common = identity.commonName ?? (identity.scientificName == display?.scientificName ? display?.commonName : nil)
        } else if let community = entry.authority?.aiReview?.community {
            common = community.common_name
        } else { common = display?.commonName }
        let biological = display?.isBiological ?? (saved?["is_biological_subject"] as? Bool ?? true)
        let title = nonempty(common) ?? nonempty(scientific) ?? (biological ? "Saved identification" : "Non-biological result")
        let confidence = ConfidenceBadgePresentation.resolve(confidenceScore: display?.confidenceScore,
            inferenceTier: display?.inferenceTier,
            provenance: display?.identificationProvenanceData.map(IdentificationResultProvenance.init(storedData:)),
            hasUserOverride: false, isUserConfirmed: false, analyzingPhrase: nil)
        return IdentificationHistoryRow(id: entry.result.analysisID, title: String(title.prefix(200)),
            scientificName: scientific.map { String($0.prefix(200)) }, completedAt: entry.result.completedAt,
            confidence: confidence.isVisible ? confidence.label : nil, review: review(entry.authority, biological: biological),
            isImported: entry.result.version == 3)
    }

    static func detail(_ entry: ObservationHistoryListingService.Entry, context: ObservationHistoryListingService.Context, cached: Bool) throws -> IdentificationHistoryDetail {
        let envelope = try JSONSerialization.jsonObject(with: entry.result.bytes) as? [String: Any]
        let evidence = envelope?["evidence_manifest"] as? [String: Any]
        let descriptions = (evidence?["captured_media"] as? [[String: Any]] ?? []).compactMap {
            (($0["description"] as? [String: Any])?["_0"] as? [String: Any])?["freeText"] as? String
        }
        // Imported saved results retain bounded legacy JSON, whose optional
        // candidates may predate the current schema. They cannot block preview.
        let alternatives = entry.display?.candidatesData.flatMap {
            try? JSONDecoder().decode([IdentificationCandidate].self, from: $0)
        } ?? []
        let row = try row(entry)
        return IdentificationHistoryDetail(row: row, reasoning: entry.display?.aiReasoning.map { String($0.prefix(8_000)) },
            alternatives: alternatives.prefix(10).map { String(($0.commonName ?? $0.scientificName).prefix(200)) },
            evidenceDescription: descriptions.isEmpty ? nil : String(descriptions.joined(separator: "\n").prefix(4_000)),
            photoIDs: entry.result.photos.map(\.mediaID),
            canRestore: entry.display != nil && entry.authority != nil && row.id != context.selected && context.pendingOperation == nil,
            isCached: cached)
    }

    private static func nonempty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
    private static func review(_ authority: ObservationHistoryAuthority?, biological: Bool) -> String {
        guard let authority else { return "Review not checked" }
        if authority.aiReview?.state == .aiRejected { return "Marked incorrect" }
        if authority.aiReview?.state == .awaitingAcceptance { return "Awaiting acceptance" }
        if authority.aiReview?.community != nil { return "Community identification" }
        if !biological { return "Non-biological" }
        if authority.speciesReview?.identity != nil, authority.confirmed == true { return "Confirmed species" }
        if authority.confirmed == true { return "Saved review" }
        return "Not confirmed"
    }
}
