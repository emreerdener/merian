import Foundation
import Testing

@testable import Merian

@Suite("DescribeInputViewModel")
@MainActor
struct DescribeInputViewModelTests {
    @Test("A newer description fences a stale subject inference")
    func newerDescriptionFencesStaleInference() async {
        let waiter = SubjectInferenceWaiter()
        var inferredSubjects: [String] = []
        let viewModel = makeViewModel(
            waitForSubjectInference: {
                await waiter.wait()
            }
        )

        viewModel.descriptionDidChange(
            text: "hawk",
            isReanalysis: false,
            isFunnelActive: false,
            shouldApplySubject: { true },
            onDescriptionEmptied: {},
            onSubjectInferred: { inferredSubjects.append($0) }
        )
        await waitUntil { waiter.waitCount == 1 }

        viewModel.descriptionDidChange(
            text: "beetle",
            isReanalysis: false,
            isFunnelActive: false,
            shouldApplySubject: { true },
            onDescriptionEmptied: {},
            onSubjectInferred: { inferredSubjects.append($0) }
        )
        await waitUntil { waiter.waitCount == 2 }

        waiter.resumeWait(at: 0)
        await Task.yield()
        #expect(inferredSubjects.isEmpty)

        waiter.resumeWait(at: 1)
        await waitUntil { inferredSubjects == ["subj_insec"] }
        #expect(viewModel.pendingSubjectInferenceText == nil)
    }

    @Test("Manual funnel selection prevents a pending inferred subject")
    func manualFunnelSelectionPreventsInference() async {
        let waiter = SubjectInferenceWaiter()
        var canApply = true
        var inferredSubjects: [String] = []
        let viewModel = makeViewModel(
            waitForSubjectInference: {
                await waiter.wait()
            }
        )

        viewModel.descriptionDidChange(
            text: "hawk",
            isReanalysis: false,
            isFunnelActive: false,
            shouldApplySubject: { canApply },
            onDescriptionEmptied: {},
            onSubjectInferred: { inferredSubjects.append($0) }
        )
        await waitUntil { waiter.waitCount == 1 }
        canApply = false
        waiter.resumeWait(at: 0)
        await Task.yield()

        #expect(inferredSubjects.isEmpty)
        #expect(viewModel.pendingSubjectInferenceText == nil)
    }

    @Test("Changing prompt flow fences pending standard inference")
    func promptFlowChangeFencesPendingInference() async {
        let waiter = SubjectInferenceWaiter()
        var inferredSubjects: [String] = []
        let viewModel = makeViewModel(
            waitForSubjectInference: {
                await waiter.wait()
            }
        )

        viewModel.descriptionDidChange(
            text: "hawk",
            isReanalysis: false,
            isFunnelActive: false,
            shouldApplySubject: { true },
            onDescriptionEmptied: {},
            onSubjectInferred: { inferredSubjects.append($0) }
        )
        await waitUntil { waiter.waitCount == 1 }

        viewModel.promptFlowDidChange()
        waiter.resumeWait(at: 0)
        await Task.yield()

        #expect(inferredSubjects.isEmpty)
        #expect(viewModel.pendingSubjectInferenceText == nil)
    }

    @Test("Empty standard text resets prompts without scheduling inference")
    func emptyDescriptionResetsPrompts() {
        var resetCount = 0
        let viewModel = makeViewModel()

        viewModel.descriptionDidChange(
            text: " \n ",
            isReanalysis: false,
            isFunnelActive: false,
            shouldApplySubject: { true },
            onDescriptionEmptied: { resetCount += 1 },
            onSubjectInferred: { _ in }
        )

        #expect(resetCount == 1)
        #expect(viewModel.pendingSubjectInferenceText == nil)
    }

    @Test("Reanalysis never schedules standard subject inference")
    func reanalysisSkipsSubjectInference() {
        var resetCount = 0
        let viewModel = makeViewModel()

        viewModel.descriptionDidChange(
            text: "hawk",
            isReanalysis: true,
            isFunnelActive: false,
            shouldApplySubject: { true },
            onDescriptionEmptied: { resetCount += 1 },
            onSubjectInferred: { _ in }
        )

        #expect(resetCount == 0)
        #expect(viewModel.pendingSubjectInferenceText == nil)
    }

    @Test("A stale transcription cannot mutate a replacement session")
    func staleTranscriptionIsSessionFenced() async {
        var resultSinks: [DescribeInputViewModel.DictationResultSink] = []
        var stopCount = 0
        var requestEndCount = 0
        var composedTexts: [String] = []
        let viewModel = makeViewModel(
            startDictation: {
                resultSinks.append($0)
                return true
            },
            stopDictation: { stopCount += 1 }
        )

        viewModel.dictationRequestDidChange(
            isRequested: true,
            baseText: "first",
            onTranscript: { composedTexts.append($0) },
            onRequestEnded: { requestEndCount += 1 }
        )
        await waitUntil { resultSinks.count == 1 }

        viewModel.stopAll(
            isRequested: true,
            isRecording: true,
            isStarting: false,
            onRequestEnded: { requestEndCount += 1 }
        )
        viewModel.dictationRequestDidChange(
            isRequested: true,
            baseText: "second",
            onTranscript: { composedTexts.append($0) },
            onRequestEnded: { requestEndCount += 1 }
        )
        await waitUntil { resultSinks.count == 2 }

        resultSinks[0].yield("old result")
        resultSinks[1].yield("new result")

        #expect(composedTexts == ["second new result"])
        #expect(stopCount == 1)
        #expect(requestEndCount == 1)
        #expect(viewModel.isDictationSessionActive)
    }

    @Test("Replacement dictation waits for canceled startup teardown")
    func replacementWaitsForCanceledStartup() async {
        let startupWaiter = DictationStartupWaiter()
        var composedTexts: [String] = []
        var stopCount = 0
        let viewModel = makeViewModel(
            startDictation: { resultSink in
                await startupWaiter.start(resultSink)
                return true
            },
            stopDictation: { stopCount += 1 }
        )

        viewModel.dictationRequestDidChange(
            isRequested: true,
            baseText: "first",
            onTranscript: { composedTexts.append($0) },
            onRequestEnded: {}
        )
        await waitUntil { startupWaiter.waitCount == 1 }

        viewModel.stopAll(
            isRequested: true,
            isRecording: false,
            isStarting: true,
            onRequestEnded: {}
        )
        viewModel.dictationRequestDidChange(
            isRequested: true,
            baseText: "second",
            onTranscript: { composedTexts.append($0) },
            onRequestEnded: {}
        )

        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(startupWaiter.waitCount == 1)
        #expect(
            stopCount == 0,
            "Detached startup must finish before shared audio teardown"
        )

        startupWaiter.resumeStart(at: 0)
        await waitUntil { startupWaiter.waitCount == 2 }
        #expect(
            stopCount == 1,
            "A canceled startup that reports success must be cleaned up"
        )

        startupWaiter.resultSinks[0].yield("stale result")
        startupWaiter.resultSinks[1].yield("new result")
        startupWaiter.resumeStart(at: 1)

        #expect(composedTexts == ["second new result"])
        #expect(viewModel.isDictationSessionActive)
    }

    @Test("Overlapping dictation requests share one active session")
    func overlappingRequestsDoNotStartTwice() async {
        var startCount = 0
        let viewModel = makeViewModel(
            startDictation: { _ in
                startCount += 1
                return true
            }
        )

        for _ in 0..<2 {
            viewModel.dictationRequestDidChange(
                isRequested: true,
                baseText: "",
                onTranscript: { _ in },
                onRequestEnded: {}
            )
        }
        await waitUntil { startCount == 1 }

        #expect(startCount == 1)
        #expect(viewModel.isDictationSessionActive)
    }

    @Test("Startup failure ends only its current request")
    func startupFailureEndsRequest() async {
        var requestEndCount = 0
        let viewModel = makeViewModel(
            startDictation: { _ in throw TestFailure.expected }
        )

        viewModel.dictationRequestDidChange(
            isRequested: true,
            baseText: "",
            onTranscript: { _ in },
            onRequestEnded: { requestEndCount += 1 }
        )
        await waitUntil { requestEndCount == 1 }

        #expect(!viewModel.isDictationSessionActive)
    }

    @Test("A busy speech owner ends an unstarted request")
    func inactiveStartupEndsRequest() async {
        var requestEndCount = 0
        let viewModel = makeViewModel(
            startDictation: { _ in false }
        )

        viewModel.dictationRequestDidChange(
            isRequested: true,
            baseText: "",
            onTranscript: { _ in },
            onRequestEnded: { requestEndCount += 1 }
        )
        await waitUntil { requestEndCount == 1 }

        #expect(!viewModel.isDictationSessionActive)
    }

    private func makeViewModel(
        startDictation: @escaping @MainActor (
            DescribeInputViewModel.DictationResultSink
        ) async throws -> Bool = { _ in true },
        stopDictation: @escaping @MainActor () -> Void = {},
        waitForSubjectInference: @escaping @MainActor () async throws -> Void = {},
        inferSubjectId: @escaping @MainActor (String) -> String? = {
            SubjectKeywordMatcher.infer(from: $0)
        }
    ) -> DescribeInputViewModel {
        DescribeInputViewModel(
            dependencies: .init(
                startDictation: startDictation,
                stopDictation: stopDictation,
                waitForSubjectInference: waitForSubjectInference,
                inferSubjectId: inferSubjectId
            )
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        #expect(condition())
    }
}

@MainActor
private final class SubjectInferenceWaiter {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var waitCount: Int { continuations.count }

    func wait() async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeWait(at index: Int) {
        continuations[index].resume()
    }
}

@MainActor
private final class DictationStartupWaiter {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var resultSinks: [DescribeInputViewModel.DictationResultSink] = []

    var waitCount: Int { continuations.count }

    func start(_ resultSink: DescribeInputViewModel.DictationResultSink) async {
        resultSinks.append(resultSink)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeStart(at index: Int) {
        continuations[index].resume()
    }
}

private enum TestFailure: Error {
    case expected
}
