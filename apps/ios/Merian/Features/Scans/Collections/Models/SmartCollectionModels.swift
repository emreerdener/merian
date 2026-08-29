import Foundation

struct SmartCollectionDefinition: Identifiable, Equatable {
    enum Rule: Equatable {
        case featured
        case needsReview
        case recentFinds
        case shared
        case location(String)
        case taxonomy(SearchCategoryBucket)
        case invasive
        case hazards
    }

    let id: String
    let title: String
    let iconName: String
    let rule: Rule
    let rank: Int
}

struct SmartCollectionSnapshot: Identifiable {
    let definition: SmartCollectionDefinition
    let scans: [LocalScanRecord]
    let coverScan: LocalScanRecord?

    var id: String { definition.id }
    var title: String { definition.title }
    var iconName: String { definition.iconName }
    var count: Int { scans.count }
    var newestScanDate: Date { scans.map(\.timestamp).max() ?? .distantPast }
    var isHideable: Bool { definition.rule != .needsReview }

    var isPinnedRow: Bool {
        definition.rule == .needsReview
    }

    var defaultCollectionAssetName: String {
        switch definition.rule {
        case .needsReview:
            return "review"
        default:
            return iconName
        }
    }
}
