import Foundation

// MARK: - Gamification Payloads
public struct AwardPayload: Sendable, Identifiable {
    public let title: String
    public let type: String
    public let currentCount: Int
    public let targetCount: Int
    public let lastInteractionDate: Date?

    public var id: String { type }
}

public struct AchievementContribution: Sendable, Identifiable, Hashable {
    public let id: String
    public let scientificName: String
    public let timestamp: Date
    public let reasonText: String
}

public struct AchievementDetailPayload: Sendable, Identifiable {
    public let award: AwardPayload
    public let contributions: [AchievementContribution]

    public var id: String { award.id }
}

extension AwardPayload {
    var difficultyLevel: Int {
        switch type.lowercased() {
        case "first_scan": return 0
        case "conservationist": return 2
        case "alpine", "frost_walker": return 2
        case "perfect_lens", "guardian", "nocturnal", "toxicologist": return 1
        case "fungi": return targetCount >= 10 ? 2 : 1
        case "insecta": return targetCount >= 10 ? 1 : 0
        case "explorer":
            if targetCount >= 50 { return 2 }
            if targetCount >= 20 { return 1 }
            return 0
        case "plantae", "urban":
            if targetCount >= 50 { return 2 }
            if targetCount >= 20 { return 1 }
            return 0
        default:
            return targetCount > 5 ? 1 : 0
        }
    }
    
    var difficultyString: String {
        switch difficultyLevel {
        case 2: return "Hard"
        case 1: return "Medium"
        default: return "Easy"
        }
    }
    
    var isCompleted: Bool {
        currentCount >= targetCount
    }
    
    var progressFraction: Double {
        min(Double(currentCount) / Double(targetCount), 1.0)
    }
}

// MARK: - Sorting UI State
enum AwardSortOption: String, CaseIterable, Identifiable {
    case smartSort = "Smart sort"
    case completedFirst = "Completed first"
    case uncompletedFirst = "Incomplete first"
    case easiestFirst = "Easiest first"
    case hardestFirst = "Hardest first"
    
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .smartSort: return "sparkles"
        case .completedFirst: return "checkmark.circle.fill"
        case .uncompletedFirst: return "circle.dashed"
        case .easiestFirst: return "arrow.down.right.circle"
        case .hardestFirst: return "arrow.up.right.circle"
        }
    }
}

// MARK: - Personas
public enum UserPersona: CaseIterable, Equatable {
    case observer
    case explorer
    case naturalist
    case scholar
    case apexObserver
    
    public init(speciesCount: Int) {
        switch speciesCount {
        case 0: self = .observer
        case 1..<10: self = .explorer
        case 10..<50: self = .naturalist
        case 50..<100: self = .scholar
        default: self = .apexObserver
        }
    }
    
    public var title: String {
        switch self {
        case .observer: return "The Observer"
        case .explorer: return "Casual Explorer"
        case .naturalist: return "Dedicated Naturalist"
        case .scholar: return "Verified Scholar"
        case .apexObserver: return "Apex Observer"
        }
    }
    
    public var description: String {
        switch self {
        case .observer: return "The viewfinder is ready. Step outside to log your first scan."
        case .explorer: return "Starting your collection. Learning the language of local flora and fauna."
        case .naturalist: return "Mapping local biodiversity and building a vibrant library."
        case .scholar: return "Curating a museum-grade archive of the natural world."
        case .apexObserver: return "An absolute authority on the ecosystem. Your collection is a masterpiece."
        }
    }
    
    public var imageName: String {
        switch self {
        case .observer: return "persona_observer"
        case .explorer: return "persona_explorer"
        case .naturalist: return "persona_naturalist"
        case .scholar: return "persona_scholar"
        case .apexObserver: return "persona_apex_observer"
        }
    }
}
