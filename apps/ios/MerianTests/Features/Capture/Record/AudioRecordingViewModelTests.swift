import Testing

@testable import Merian

@Suite("AudioRecordingViewModel")
@MainActor
struct AudioRecordingViewModelTests {
    @Test("Automatic and selected artwork advances keep feedback distinct")
    func artworkAdvanceFeedback() {
        var selectionFeedbackCount = 0
        let viewModel = makeViewModel(
            idleArtworkSelectionFeedback: {
                selectionFeedbackCount += 1
            }
        )

        viewModel.advanceIdleArtworkAfterTimer()
        #expect(viewModel.idleArtworkIndex == 1)
        #expect(selectionFeedbackCount == 0)

        viewModel.advanceIdleArtworkAfterSelection()
        #expect(viewModel.idleArtworkIndex == 2)
        #expect(selectionFeedbackCount == 1)
    }

    @Test("Scrubbing normalizes seeks and emits boundary feedback once")
    func scrubInteraction() {
        var seeks: [Double] = []
        var beginFeedbackCount = 0
        var commitFeedbackCount = 0
        let viewModel = makeViewModel(
            seekPlayback: { seeks.append($0) },
            scrubBeginFeedback: { beginFeedbackCount += 1 },
            scrubCommitFeedback: { commitFeedbackCount += 1 }
        )

        viewModel.updateScrubbing(locationX: -20, width: 100)
        viewModel.updateScrubbing(locationX: 50, width: 100)
        viewModel.updateScrubbing(locationX: 140, width: 100)

        #expect(viewModel.isScrubbing)
        #expect(seeks == [0, 0.5, 1])
        #expect(beginFeedbackCount == 1)
        #expect(commitFeedbackCount == 0)

        viewModel.finishScrubbing()
        viewModel.finishScrubbing()

        #expect(!viewModel.isScrubbing)
        #expect(commitFeedbackCount == 1)
    }

    @Test("Invalid scrub geometry resolves to the start")
    func invalidScrubGeometry() {
        var seeks: [Double] = []
        let viewModel = makeViewModel(
            seekPlayback: { seeks.append($0) }
        )

        viewModel.updateScrubbing(locationX: 25, width: 0)

        #expect(seeks == [0])
    }

    private func makeViewModel(
        seekPlayback: @escaping @MainActor (Double) -> Void = { _ in },
        idleArtworkSelectionFeedback: @escaping @MainActor () -> Void = {},
        scrubBeginFeedback: @escaping @MainActor () -> Void = {},
        scrubCommitFeedback: @escaping @MainActor () -> Void = {}
    ) -> AudioRecordingViewModel {
        AudioRecordingViewModel(
            dependencies: .init(
                seekPlayback: seekPlayback,
                idleArtworkSelectionFeedback:
                    idleArtworkSelectionFeedback,
                scrubBeginFeedback: scrubBeginFeedback,
                scrubCommitFeedback: scrubCommitFeedback
            )
        )
    }
}
