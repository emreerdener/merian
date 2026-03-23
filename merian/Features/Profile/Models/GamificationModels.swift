import Foundation

// MARK: - Gamification Payloads
public struct AwardPayload: Sendable, Identifiable {
    public let id = UUID()
    public let title: String
    public let type: String
    public let currentCount: Int
    public let targetCount: Int
    public let lastInteractionDate: Date?
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
