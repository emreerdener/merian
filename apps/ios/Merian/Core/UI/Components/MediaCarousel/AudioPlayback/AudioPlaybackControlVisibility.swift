import Observation
import SwiftUI

@MainActor
@Observable
final class AudioPlaybackControlVisibility {
    private(set) var isVisible = true

    @ObservationIgnored
    private var fadeTask: Task<Void, Never>?

    func showTemporarily(
        shouldAutoHide: @escaping @MainActor () -> Bool
    ) {
        fadeTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            isVisible = true
        }
        guard shouldAutoHide() else {
            fadeTask = nil
            return
        }

        fadeTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: AudioPlaybackControlPolicy
                    .autoHideDelayNanoseconds
            )
            guard !Task.isCancelled,
                  let self,
                  shouldAutoHide() else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.isVisible = false
            }
        }
    }

    func showPersistently() {
        cancelPendingFade()
        withAnimation(.easeInOut(duration: 0.18)) {
            isVisible = true
        }
    }

    func cancelPendingFade() {
        fadeTask?.cancel()
        fadeTask = nil
    }
}
