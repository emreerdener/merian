import Foundation
import Observation

/// Freezes one set of suggested questions for this presentation's lifetime.
@MainActor
@Observable
final class FieldChatPromptRevealModel {
    private(set) var displayedPrompts: [String]?
    @ObservationIgnored private var candidates: [String] = []
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var reachedDeadline = false

    var isRevealed: Bool { displayedPrompts != nil }

    func update(candidates: [String], isLoading: Bool, isVisible: Bool) {
        guard !isRevealed else { return }
        self.candidates = Array(candidates.prefix(3))
        self.isVisible = isVisible
        if !isLoading || reachedDeadline { revealIfPossible() }
    }

    func waitForFallback(
        wait: @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(4)) }
    ) async {
        guard !isRevealed else { return }
        do {
            try await wait()
        } catch {
            return
        }
        guard !Task.isCancelled, !isRevealed else { return }
        reachedDeadline = true
        revealIfPossible()
    }

    private func revealIfPossible() {
        guard !isRevealed, isVisible, !candidates.isEmpty else { return }
        displayedPrompts = candidates
    }
}
