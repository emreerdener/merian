import Testing

@testable import Merian

@Suite("Audio capture transition state")
struct AudioCaptureTransitionStateTests {
    @Test("A replacement transition fences its predecessor")
    func replacementFencesPredecessor() {
        var state = AudioCaptureTransitionState()

        let first = state.begin()
        let replacement = state.begin()

        #expect(!state.isCurrent(first))
        #expect(state.isCurrent(replacement))
    }

    @Test("Invalidation fences the current transition")
    func invalidationFencesCurrentTransition() {
        var state = AudioCaptureTransitionState()
        let transition = state.begin()

        state.invalidate()

        #expect(!state.isCurrent(transition))
    }
}
