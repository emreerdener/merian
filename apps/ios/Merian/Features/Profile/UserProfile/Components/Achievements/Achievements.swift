import SwiftData
import SwiftUI

// MARK: - Primary View
struct Achievements: View {
    @Environment(\.modelContext) private var modelContext

    let awards: [AwardPayload]
    var allowsDetailPresentation = true
    private let dependencies: AchievementDetailDependencies

    @State private var sortOption: AwardSortOption = .smartSort
    @State private var selectedAward: AwardPayload?

    init(
        awards: [AwardPayload],
        allowsDetailPresentation: Bool = true,
        dependencies: AchievementDetailDependencies? = nil
    ) {
        self.awards = awards
        self.allowsDetailPresentation = allowsDetailPresentation
        self.dependencies = dependencies ?? .live
    }

    private var sortedAwards: [AwardPayload] {
        switch sortOption {
        case .smartSort:
            return awards.sorted { a, b in
                func smartScore(for award: AwardPayload) -> Double {
                    if award.isCompleted {
                        if let date = award.lastInteractionDate, Date().timeIntervalSince(date) < 86400 * 7 {
                            return 3.0
                        }
                        return 1.0
                    }
                    if award.progressFraction > 0 {
                        return 2.0 + award.progressFraction
                    }
                    return 0.0
                }

                let scoreA = smartScore(for: a)
                let scoreB = smartScore(for: b)

                if abs(scoreA - scoreB) < 0.001 {
                    if let dateA = a.lastInteractionDate, let dateB = b.lastInteractionDate {
                        return dateA > dateB
                    }
                    if a.lastInteractionDate != nil { return true }
                    if b.lastInteractionDate != nil { return false }
                    return a.difficultyLevel < b.difficultyLevel
                }

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

    // MARK: - Achievements View
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Achievements Header
            HStack(alignment: .center) {
                Text("Achievements")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Spacer()

                Menu {
                    Picker(
                        "Sort achievements",
                        selection: Binding(
                            get: { sortOption },
                            set: { option in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    sortOption = option
                                }
                            }
                        )
                    ) {
                        ForEach(AwardSortOption.allCases) { option in
                            Label(option.rawValue, systemImage: option.iconName)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.75))

                        Text(sortOption.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                }
                .animation(.none, value: sortOption)
                .accessibilityLabel("Sorted by \(sortOption.rawValue)")
            }
            .padding(.top, 16)

            // Achievements List
            VStack(spacing: 12) {
                ForEach(sortedAwards) { award in
                    if allowsDetailPresentation {
                        Button {
                            if award.isCompleted, let destination = award.destination {
                                dependencies.openGoalDestination(destination)
                            } else {
                                selectedAward = award
                            }
                        } label: {
                            AchievementCard(award: award)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("AchievementCard_\(award.type.rawValue)")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(award.cardAccessibilityLabel)
                        .accessibilityHint(award.cardAccessibilityHint)
                    } else {
                        AchievementCard(award: award)
                            .accessibilityIdentifier("AchievementCard_\(award.type.rawValue)")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(award.cardAccessibilityLabel)
                            .accessibilityHint("Public achievement progress. Qualifying scans are private.")
                    }
                }
            }
        }
        .sheet(item: $selectedAward) { award in
            AchievementDetailSheet(
                award: award,
                modelContainer: modelContext.container,
                dependencies: dependencies
            )
        }
    }
}
