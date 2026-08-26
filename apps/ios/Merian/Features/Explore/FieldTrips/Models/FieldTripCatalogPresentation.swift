import Foundation

enum FieldTripDifficulty: String, CaseIterable, Identifiable {
    case starter
    case easy
    case moderate
    case hard

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    init?(apiValue: String) {
        self.init(
            rawValue: apiValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        )
    }
}

enum FieldTripDifficultyFilter: String, CaseIterable, Identifiable {
    case all
    case starter
    case easy
    case moderate
    case hard

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var difficulty: FieldTripDifficulty? {
        guard self != .all else { return nil }
        return FieldTripDifficulty(rawValue: rawValue)
    }
}

enum FieldTripCatalogState: String, CaseIterable, Identifiable {
    case completed
    case inProgress
    case incomplete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completed:
            "Completed"
        case .inProgress:
            "In progress"
        case .incomplete:
            "Incomplete"
        }
    }
}

enum FieldTripStateFilter: String, CaseIterable, Identifiable {
    case all
    case completed
    case inProgress
    case incomplete

    var id: String { rawValue }

    var title: String {
        state?.title ?? "All statuses"
    }

    var state: FieldTripCatalogState? {
        guard self != .all else { return nil }
        return FieldTripCatalogState(rawValue: rawValue)
    }
}

struct FieldTripCatalogFilters: Equatable {
    var difficulty: FieldTripDifficultyFilter = .all
    var state: FieldTripStateFilter = .all

    var activeFilterCount: Int {
        (difficulty == .all ? 0 : 1) + (state == .all ? 0 : 1)
    }

    var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    mutating func reset() {
        difficulty = .all
        state = .all
    }
}

extension FieldTripTemplate {
    var resolvedDifficulty: FieldTripDifficulty? {
        FieldTripDifficulty(apiValue: difficulty)
    }

    var catalogState: FieldTripCatalogState {
        guard let viewerProgress else { return .incomplete }
        return viewerProgress.isComplete ? .completed : .inProgress
    }

    var difficultyTitle: String {
        if let resolvedDifficulty {
            return resolvedDifficulty.title
        }

        let normalized = difficulty
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        return normalized.isEmpty ? "Unknown" : normalized.capitalized
    }
}

extension Array where Element == FieldTripTemplate {
    func filtering(by difficulty: FieldTripDifficulty?) -> [FieldTripTemplate] {
        guard let difficulty else { return self }
        return filter { $0.resolvedDifficulty == difficulty }
    }

    func filtering(by filters: FieldTripCatalogFilters) -> [FieldTripTemplate] {
        filter { template in
            let matchesDifficulty = filters.difficulty.difficulty.map {
                template.resolvedDifficulty == $0
            } ?? true
            let matchesState = filters.state.state.map {
                template.catalogState == $0
            } ?? true
            return matchesDifficulty && matchesState
        }
    }
}

enum FieldTripDetailPrimaryAction: Equatable {
    case unlock
    case start
    case resume
    case publish
    case scan
}

enum FieldTripDetailLifecyclePresentation {
    static func primaryAction(
        for template: FieldTripTemplate,
        sharingEnabled: Bool = FieldTripSharingAvailability.isEnabled
    ) -> FieldTripDetailPrimaryAction? {
        guard template.viewerHasAccess else { return .unlock }
        if template.isStopped { return .resume }
        guard let progress = template.viewerProgress else { return .start }
        guard !progress.isComplete else {
            return sharingEnabled ? .publish : nil
        }
        return .scan
    }

    static func canStop(_ template: FieldTripTemplate) -> Bool {
        guard let progress = template.activeProgress else { return false }
        return !progress.isComplete
    }

    static func canReset(_ template: FieldTripTemplate) -> Bool {
        guard let progress = template.viewerProgress else { return false }
        return !progress.isComplete && progress.publicationId == nil
    }

    static func showsOptionsMenu(_ template: FieldTripTemplate) -> Bool {
        canStop(template) || canReset(template)
    }
}
