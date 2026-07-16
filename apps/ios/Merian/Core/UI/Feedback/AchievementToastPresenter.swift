import Foundation
import Observation

enum MilestoneToastSource: Sendable, Equatable {
    case unlock
    case preview
}

struct DictionaryMilestonePayload: Sendable, Equatable {
    let title: String
    let subtitle: String
    let imageName: String

    static let newToMerian = DictionaryMilestonePayload(
        title: "New to Naturebook",
        subtitle: "Added to the species dictionary",
        imageName: "star"
    )
}

enum MilestoneToastPayload: Sendable {
    case achievement(AwardPayload)
    case dictionary(DictionaryMilestonePayload)
}

struct MilestoneToastItem: Identifiable, Sendable {
    let id: UUID
    let payload: MilestoneToastPayload
    let source: MilestoneToastSource

    var award: AwardPayload? {
        guard case let .achievement(award) = payload else { return nil }
        return award
    }
}

@MainActor
@Observable final class MilestoneToastPresenter {
    static let shared = MilestoneToastPresenter()

    private(set) var activeItem: MilestoneToastItem?
    @ObservationIgnored private var queuedItems: [MilestoneToastItem] = []

    var queuedItemCount: Int {
        queuedItems.count
    }

    var activeUnlock: MilestoneToastItem? {
        activeItem
    }

    var queuedUnlockCount: Int {
        queuedItemCount
    }

    init() {}

    func enqueueAchievementUnlock(_ award: AwardPayload) {
        enqueue(.achievement(award), source: .unlock)
    }

    func enqueueNewToMerianMilestone() {
        enqueue(.dictionary(.newToMerian), source: .unlock)
    }

    #if DEBUG
    func previewAchievementUnlock(_ award: AwardPayload) {
        enqueue(.achievement(award), source: .preview)
    }

    func previewNewToMerianMilestone() {
        enqueue(.dictionary(.newToMerian), source: .preview)
    }

    func resetForTesting() {
        activeItem = nil
        queuedItems.removeAll()
    }
    #endif

    func dismissActiveItem(id: UUID? = nil) {
        if let id, activeItem?.id != id { return }

        activeItem = nil
        presentNextItemIfNeeded()
    }

    func dismissActiveUnlock(id: UUID? = nil) {
        dismissActiveItem(id: id)
    }

    private func enqueue(_ payload: MilestoneToastPayload, source: MilestoneToastSource) {
        let item = MilestoneToastItem(id: UUID(), payload: payload, source: source)

        if activeItem == nil {
            activeItem = item
        } else {
            queuedItems.append(item)
        }
    }

    private func presentNextItemIfNeeded() {
        guard activeItem == nil, !queuedItems.isEmpty else { return }

        activeItem = queuedItems.removeFirst()
    }
}

typealias AchievementToastPresenter = MilestoneToastPresenter
typealias AchievementToastItem = MilestoneToastItem
