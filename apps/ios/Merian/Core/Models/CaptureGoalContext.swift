import Foundation
import Observation

/// The product surface that contributed a goal to the capture experience.
///
/// Capture intentionally treats this as display and routing metadata. Source
/// features remain responsible for eligibility, ordering, and completion.
enum CaptureGoalSourceKind: String, Codable, Equatable, Sendable {
    case fieldTrip = "field_trip"
}

struct CaptureGoalSource: Codable, Equatable, Sendable {
    let kind: CaptureGoalSourceKind
    let id: String
    let title: String
}

struct CaptureGoalProgress: Codable, Equatable, Sendable {
    let completedCount: Int
    let targetCount: Int
}

enum CaptureGoalArtwork: Codable, Equatable, Sendable {
    case bundledImage(name: String)
    case systemSymbol(name: String)
}

/// A typed hand-off from Capture to the feature that owns the goal details.
/// Adding another goal source requires an explicit route case and compiler-
/// checked handling at the Explore boundary.
enum CaptureGoalDestination: Codable, Equatable, Sendable {
    case fieldTrip(templateId: String, checklistItemId: String)
    case fieldTripChallenge(challengeId: String)
}

/// The small, source-agnostic read model consumed by capture surfaces.
struct CaptureGoal: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let source: CaptureGoalSource
    let prompt: String
    let progress: CaptureGoalProgress
    let artwork: CaptureGoalArtwork
    let destination: CaptureGoalDestination
}

/// Provider boundary between Capture and goal-producing features.
/// Providers return goals in presentation order; Capture never reimplements
/// source eligibility, entitlement, or ranking rules.
protocol CaptureGoalContextProviding: Sendable {
    func fetchCaptureGoals() async throws -> [CaptureGoal]
}

@MainActor
@Observable
final class ActiveCaptureGoalStore {
    typealias FetchContext = @Sendable () async throws -> [CaptureGoal]

    private struct CacheEnvelope: Codable {
        let goals: [CaptureGoal]
        let selectedGoalId: String?
        let refreshedAt: Date
    }

    static let freshnessInterval: TimeInterval = 5 * 60

    private(set) var goals: [CaptureGoal] = []
    private(set) var selectedGoalId: String?
    private(set) var isLoading = false
    private(set) var accountId: String?
    private(set) var lastSuccessfulRefreshAt: Date?

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let fetchContext: FetchContext
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var needsFollowupRefresh = false

    var selectedGoal: CaptureGoal? {
        guard !goals.isEmpty else { return nil }
        return goals.first(where: { $0.id == selectedGoalId }) ?? goals.first
    }

    init(
        userDefaults: UserDefaults = .standard,
        fetchContext: @escaping FetchContext
    ) {
        self.userDefaults = userDefaults
        self.fetchContext = fetchContext
    }

    convenience init(
        userDefaults: UserDefaults = .standard,
        provider: any CaptureGoalContextProviding
    ) {
        self.init(userDefaults: userDefaults) {
            try await provider.fetchCaptureGoals()
        }
    }

    func activate(accountId newAccountId: String?) {
        let normalized = newAccountId?.lowercased()
        guard normalized != accountId else { return }

        accountId = normalized
        refreshGeneration += 1
        isLoading = false
        needsFollowupRefresh = false
        goals = []
        selectedGoalId = nil
        lastSuccessfulRefreshAt = nil

        guard let normalized,
              let data = userDefaults.data(forKey: cacheKey(accountId: normalized)),
              let cached = try? JSONDecoder().decode(CacheEnvelope.self, from: data) else {
            return
        }

        goals = cached.goals
        selectedGoalId = cached.selectedGoalId
        lastSuccessfulRefreshAt = cached.refreshedAt
        normalizeSelection()
    }

    func refresh(accountId: String?, force: Bool = false, now: Date = Date()) async {
        activate(accountId: accountId)
        guard let requestedAccountId = self.accountId else { return }
        if isLoading {
            needsFollowupRefresh = needsFollowupRefresh || force
            return
        }
        if !force,
           let lastSuccessfulRefreshAt,
           now.timeIntervalSince(lastSuccessfulRefreshAt) < Self.freshnessInterval {
            return
        }

        isLoading = true
        let requestedGeneration = refreshGeneration
        defer {
            finishRefresh(
                accountId: requestedAccountId,
                generation: requestedGeneration
            )
        }

        let oldGoals = goals
        let oldSelection = selectedGoalId
        let oldIndex = oldSelection.flatMap { selection in
            oldGoals.firstIndex(where: { $0.id == selection })
        }

        do {
            let refreshedGoals = try await fetchContext()
            guard self.accountId == requestedAccountId else { return }

            goals = refreshedGoals
            if let oldSelection,
               refreshedGoals.contains(where: { $0.id == oldSelection }) {
                selectedGoalId = oldSelection
            } else if let oldIndex, !refreshedGoals.isEmpty {
                selectedGoalId = nextSurvivingSelection(
                    after: oldIndex,
                    oldGoals: oldGoals,
                    refreshedGoals: refreshedGoals
                )
            } else {
                selectedGoalId = refreshedGoals.first?.id
            }
            lastSuccessfulRefreshAt = now
            persist()
        } catch {
            // Capture remains usable and the last successful context stays visible.
        }
    }

    func refreshIfStale(accountId: String?, now: Date = Date()) async {
        await refresh(accountId: accountId, force: false, now: now)
    }

    func selectNext() {
        moveSelection(by: 1)
    }

    func selectPrevious() {
        moveSelection(by: -1)
    }

    private func moveSelection(by offset: Int) {
        guard !goals.isEmpty else { return }
        let currentIndex = goals.firstIndex(where: { $0.id == selectedGoalId }) ?? 0
        let nextIndex = (currentIndex + offset + goals.count) % goals.count
        selectedGoalId = goals[nextIndex].id
        persist()
    }

    private func normalizeSelection() {
        guard !goals.isEmpty else {
            selectedGoalId = nil
            return
        }
        if !goals.contains(where: { $0.id == selectedGoalId }) {
            selectedGoalId = goals.first?.id
        }
    }

    private func nextSurvivingSelection(
        after oldIndex: Int,
        oldGoals: [CaptureGoal],
        refreshedGoals: [CaptureGoal]
    ) -> String? {
        let refreshedIds = Set(refreshedGoals.map(\.id))
        if !oldGoals.isEmpty {
            for offset in 1...oldGoals.count {
                let candidate = oldGoals[(oldIndex + offset) % oldGoals.count].id
                if refreshedIds.contains(candidate) {
                    return candidate
                }
            }
        }
        return refreshedGoals.first?.id
    }

    private func finishRefresh(accountId: String, generation: Int) {
        guard self.accountId == accountId,
              refreshGeneration == generation else {
            return
        }
        isLoading = false
        guard needsFollowupRefresh else { return }
        needsFollowupRefresh = false
        Task {
            await refresh(accountId: accountId, force: true)
        }
    }

    private func persist() {
        guard let accountId,
              let lastSuccessfulRefreshAt,
              let data = try? JSONEncoder().encode(CacheEnvelope(
                goals: goals,
                selectedGoalId: selectedGoalId,
                refreshedAt: lastSuccessfulRefreshAt
              )) else {
            return
        }
        userDefaults.set(data, forKey: cacheKey(accountId: accountId))
    }

    private func cacheKey(accountId: String) -> String {
        UserDefaultsKeys.captureGoalContextPrefix + accountId
    }
}
