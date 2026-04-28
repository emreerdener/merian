import SwiftData
import SwiftUI

// MARK: - Gamification Database Engine
extension ProfileDatabaseActor {
    func calculateAwards() -> [AwardPayload] {
        calculateAwardsProjection()
    }
}

// MARK: - Primary View
struct Achievements: View {
    let awards: [AwardPayload]
    @State private var sortOption: AwardSortOption = .smartSort
    
    private var sortedAwards: [AwardPayload] {
        switch sortOption {
        case .smartSort:
            return awards.sorted { a, b in
                // Heuristic priority scoring:
                // >= 3.0: Freshly Completed (Within last 7 days)
                // 2.01 - 2.99: In Progress (Mathematically scales by closeness to completion)
                // 1.0: Legacy Completed (Older than 7 days)
                // 0.0: Conceptually empty (0%)
                func smartScore(for award: AwardPayload) -> Double {
                    if award.isCompleted {
                        if let date = award.lastInteractionDate, Date().timeIntervalSince(date) < 86400 * 7 {
                            return 3.0 // Hero status! Recently accomplished!
                        }
                        return 1.0 // Sink legacy accomplishments below active goals
                    }
                    if award.progressFraction > 0 {
                        return 2.0 + award.progressFraction // Organical float "close to being done" (e.g. 2.9) to the top of the In-Progress pile!
                    }
                    return 0.0 // Empty goals sink completely to the bottom
                }
                
                let scoreA = smartScore(for: a)
                let scoreB = smartScore(for: b)
                
                // If mathematically tied across the exact same heuristic tier boundaries...
                if abs(scoreA - scoreB) < 0.001 {
                    // Tie-breaker 1: Explicitly float the most recently interacted award logically!
                    if let dateA = a.lastInteractionDate, let dateB = b.lastInteractionDate {
                        return dateA > dateB
                    }
                    if a.lastInteractionDate != nil { return true }
                    if b.lastInteractionDate != nil { return false }
                    
                    // Tie-breaker 2: Fallback to difficulty geometry mapping (Green -> Amber -> Crimson)
                    return a.difficultyLevel < b.difficultyLevel
                }
                // Primary evaluator: float highest priority scores dynamically!
                return scoreA > scoreB
            }
        case .completedFirst:
            return awards.sorted {
                if $0.isCompleted == $1.isCompleted { return $0.difficultyLevel < $1.difficultyLevel }
                return $0.isCompleted && !$1.isCompleted
            }
        case .uncompletedFirst:
            return awards.sorted {
                if $0.isCompleted == $1.isCompleted { return $0.difficultyLevel < $1.difficultyLevel }
                return !$0.isCompleted && $1.isCompleted
            }
        case .easiestFirst:
            return awards.sorted {
                if $0.difficultyLevel == $1.difficultyLevel { return $0.isCompleted && !$1.isCompleted }
                return $0.difficultyLevel < $1.difficultyLevel
            }
        case .hardestFirst:
            return awards.sorted {
                if $0.difficultyLevel == $1.difficultyLevel { return $0.isCompleted && !$1.isCompleted }
                return $0.difficultyLevel > $1.difficultyLevel
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Achievements")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Menu {
                    ForEach(AwardSortOption.allCases) { option in
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                sortOption = option
                            }
                        }) {
                            Label(option.rawValue, systemImage: option.iconName)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial) // Liquid Glass frost
                        }
                        .overlay {
                            Circle()
                                // Inner specular glow replicating premium iOS reflections
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                }
            }
            
            VStack(spacing: 12) {
                ForEach(sortedAwards) { award in
                    AchievementCard(award: award)
                }
            }
        }
    }
}
