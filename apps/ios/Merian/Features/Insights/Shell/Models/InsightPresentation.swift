import Foundation

enum InsightPresentationStyle {
    case sheet
    case embeddedInScansLibrary

    var isEmbedded: Bool {
        self == .embeddedInScansLibrary
    }
}

struct ScanInsightRoute: Identifiable, Hashable {
    let scanId: String

    var id: String { scanId }
}

/// A card-specific route that opens the owning experience at its Goals overview.
/// Unlike Capture goal destinations, this intentionally carries no checklist-item
/// focus, so a completed Insight contribution never opens directly into Tips.
enum InsightFieldTripOverviewDestination: Equatable, Hashable {
    case standardOuting(templateId: String)
    case event(challengeId: String)

    init?(contribution: FieldTripScanContribution) {
        guard let destination = contribution.destination else { return nil }

        switch (contribution.sourceKind, destination) {
        case (.standardOuting, .fieldTrip(let templateId, _)):
            self = .standardOuting(templateId: templateId)
        case (.event, .fieldTripChallenge(let challengeId)):
            self = .event(challengeId: challengeId)
        case (.standardOuting, _), (.event, _):
            return nil
        }
    }
}
