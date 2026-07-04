import Foundation
import Observation

enum AchievementToastSource: Sendable, Equatable {
    case unlock
    case preview
}

struct AchievementToastItem: Identifiable, Sendable {
    let id: UUID
    let award: AwardPayload
    let source: AchievementToastSource
}

@MainActor
@Observable final class AchievementToastPresenter {
    static let shared = AchievementToastPresenter()

    private(set) var activeUnlock: AchievementToastItem?
    @ObservationIgnored private var queuedUnlocks: [AchievementToastItem] = []

    var queuedUnlockCount: Int {
        queuedUnlocks.count
    }

    init() {}

    func enqueueAchievementUnlock(_ award: AwardPayload) {
        enqueue(award, source: .unlock)
    }

    #if DEBUG
    func previewAchievementUnlock(_ award: AwardPayload) {
        enqueue(award, source: .preview)
    }

    func resetForTesting() {
        activeUnlock = nil
        queuedUnlocks.removeAll()
    }
    #endif

    func dismissActiveUnlock(id: UUID? = nil) {
        if let id, activeUnlock?.id != id { return }

        activeUnlock = nil
        presentNextUnlockIfNeeded()
    }

    private func enqueue(_ award: AwardPayload, source: AchievementToastSource) {
        let item = AchievementToastItem(id: UUID(), award: award, source: source)

        if activeUnlock == nil {
            activeUnlock = item
        } else {
            queuedUnlocks.append(item)
        }
    }

    private func presentNextUnlockIfNeeded() {
        guard activeUnlock == nil, !queuedUnlocks.isEmpty else { return }

        activeUnlock = queuedUnlocks.removeFirst()
    }
}
