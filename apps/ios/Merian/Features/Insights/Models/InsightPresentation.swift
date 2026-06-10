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
