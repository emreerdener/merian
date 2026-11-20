import XCTest
@testable import Merian

@MainActor
final class ViewfinderHintPresentationTests: XCTestCase {
    func testFreeIntroductionFadesBeforeGuidanceAndNeverReplays() async {
        let clock = HintClock()
        let launch = ViewfinderHintLaunchState()
        let presentation = ViewfinderHintPresentation(sleep: clock.sleep)
        defer { presentation.hide(); clock.cancelAll() }
        let context = ViewfinderHintPresentation.Context(isVisible: true)
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .identify)
        XCTAssertFalse(presentation.allowsGuidance)
        let introduction = await clock.next()
        XCTAssertEqual(introduction.duration, .milliseconds(3500))
        introduction.resume()
        let fade = await clock.next()
        XCTAssertEqual(presentation.phase, .finished)
        XCTAssertFalse(presentation.allowsGuidance)
        XCTAssertEqual(fade.duration, .milliseconds(350))
        fade.resume()
        await drainTasks()
        XCTAssertTrue(presentation.allowsGuidance)
        presentation.hide()
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .finished)
        XCTAssertTrue(presentation.allowsGuidance)
    }

    func testProStartsWithIdentifyThenShowsTemporaryVideoHint() async {
        let clock = HintClock()
        let launch = ViewfinderHintLaunchState()
        let presentation = ViewfinderHintPresentation(sleep: clock.sleep)
        defer { presentation.hide(); clock.cancelAll() }
        presentation.update(.init(isVisible: true, canRecordVideo: true),
                            claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase.text, "Tap to identify")
        let introduction = await clock.next()
        introduction.resume()
        let video = await clock.next()
        XCTAssertEqual(presentation.phase.text, "Hold to record video")
        XCTAssertEqual(video.duration, .milliseconds(3500))
        XCTAssertFalse(presentation.allowsGuidance)
        video.resume()
        let fade = await clock.next()
        XCTAssertEqual(presentation.phase, .finished)
        fade.resume()
        await drainTasks()
        XCTAssertTrue(presentation.allowsGuidance)
    }

    func testCoveredCameraAndExistingDraftDoNotConsumeIntroduction() {
        let launch = ViewfinderHintLaunchState()
        let presentation = ViewfinderHintPresentation()
        defer { presentation.hide() }
        presentation.update(.init(), claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .finished)
        presentation.update(.init(isVisible: true, hasEmptyDraft: false),
                            claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .finished)
        presentation.update(.init(isVisible: true, keepsPromptVisible: true),
                            claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .identify)
    }

    func testViewRecreationSharesClaimButNewLaunchResetsIt() {
        let launch = ViewfinderHintLaunchState()
        let context = ViewfinderHintPresentation.Context(isVisible: true, keepsPromptVisible: true)
        let first = ViewfinderHintPresentation()
        first.update(context, claimIntroduction: launch.claimIntroduction)
        first.hide()
        let recreated = ViewfinderHintPresentation()
        recreated.update(context, claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(recreated.phase, .finished)
        let nextLaunch = ViewfinderHintLaunchState()
        recreated.update(context, claimIntroduction: nextLaunch.claimIntroduction)
        XCTAssertEqual(recreated.phase, .identify)
        recreated.hide()
    }

    func testCaptureOrLeavingCameraCancelsBothPhasesAndRejectsLateTimers() async {
        for videoPhase in [false, true] {
            for leavesCamera in [false, true] {
                let clock = HintClock()
                let launch = ViewfinderHintLaunchState()
                let presentation = ViewfinderHintPresentation(sleep: clock.sleep)
                var context = ViewfinderHintPresentation.Context(isVisible: true, canRecordVideo: true)
                presentation.update(context, claimIntroduction: launch.claimIntroduction)
                var timer = await clock.next()
                if videoPhase {
                    timer.resume()
                    timer = await clock.next()
                }
                context.isVisible = !leavesCamera
                context.isCapturing = !leavesCamera
                presentation.update(context, claimIntroduction: launch.claimIntroduction)
                XCTAssertEqual(presentation.phase, .finished)
                XCTAssertFalse(presentation.allowsGuidance)
                timer.resume() // Deliberately non-cooperative sleeper completes after cancellation.
                await drainTasks()
                XCTAssertEqual(presentation.phase, .finished)
                XCTAssertFalse(presentation.allowsGuidance)
                context.isVisible = true
                context.isCapturing = false
                presentation.update(context, claimIntroduction: launch.claimIntroduction)
                XCTAssertEqual(presentation.phase, .finished)
                presentation.hide()
                clock.cancelAll()
            }
        }
    }

    func testEntitlementIsEvaluatedAtTransitionAndRevocationDismissesVideo() async {
        let clock = HintClock()
        let launch = ViewfinderHintLaunchState()
        let presentation = ViewfinderHintPresentation(sleep: clock.sleep)
        defer { presentation.hide(); clock.cancelAll() }
        var context = ViewfinderHintPresentation.Context(isVisible: true)
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        let introduction = await clock.next()
        context.canRecordVideo = true
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        introduction.resume()
        let video = await clock.next()
        XCTAssertEqual(presentation.phase, .video)
        context.canRecordVideo = false
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        let fade = await clock.next()
        XCTAssertEqual(presentation.phase, .finished)
        video.resume()
        fade.resume()
        await drainTasks()
        context.canRecordVideo = true
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .finished)
    }

    func testRefinementHasOwnPromptAndOldIntroductionCannotReplaceIt() async {
        let clock = HintClock()
        let launch = ViewfinderHintLaunchState()
        let presentation = ViewfinderHintPresentation(sleep: clock.sleep)
        defer { presentation.hide(); clock.cancelAll() }
        var context = ViewfinderHintPresentation.Context(isVisible: true, canRecordVideo: true)
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        let introduction = await clock.next()
        context.isRefining = true
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        let refinement = await clock.next()
        XCTAssertEqual(presentation.phase.text, "Add another")
        introduction.resume()
        await drainTasks()
        XCTAssertEqual(presentation.phase, .refinement)
        refinement.resume()
        let fade = await clock.next()
        XCTAssertEqual(presentation.phase, .finished)
        fade.resume()
        await drainTasks()
        context.isRefining = false
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        context.isRefining = true
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .refinement)
        let secondRefinement = await clock.next()
        presentation.hide()
        secondRefinement.resume()
    }

    func testRefinementDoesNotConsumeFreshLaunchIntroduction() {
        let launch = ViewfinderHintLaunchState()
        let presentation = ViewfinderHintPresentation()
        defer { presentation.hide() }
        var context = ViewfinderHintPresentation.Context(isVisible: true, isRefining: true,
                                                        keepsPromptVisible: true)
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .refinement)
        context.isRefining = false
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .identify)
    }

    func testReturningToRefinementRestoresGuidanceWithoutReplayingPrompt() {
        let launch = ViewfinderHintLaunchState()
        let presentation = ViewfinderHintPresentation()
        var context = ViewfinderHintPresentation.Context(isVisible: true, isRefining: true,
                                                        keepsPromptVisible: true)
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .refinement)
        context.isVisible = false
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        context.isVisible = true
        presentation.update(context, claimIntroduction: launch.claimIntroduction)
        XCTAssertEqual(presentation.phase, .finished)
        XCTAssertTrue(presentation.allowsGuidance)
        presentation.hide()
    }

    private func drainTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

/// Non-cooperative by design: cancellation tests explicitly release obsolete sleeps.
@MainActor
private final class HintClock {
    final class Request {
        let duration: Duration
        private var continuation: CheckedContinuation<Void, any Error>?
        init(_ duration: Duration, _ continuation: CheckedContinuation<Void, any Error>) {
            self.duration = duration
            self.continuation = continuation
        }
        func resume() {
            continuation?.resume()
            continuation = nil
        }
        func cancel() {
            continuation?.resume(throwing: CancellationError())
            continuation = nil
        }
    }
    private var pending: [Request] = []
    private var all: [Request] = []
    private var waiter: CheckedContinuation<Request, Never>?

    func sleep(_ duration: Duration) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            let request = Request(duration, continuation)
            all.append(request)
            if let waiter {
                self.waiter = nil
                waiter.resume(returning: request)
            } else {
                pending.append(request)
            }
        }
    }
    func next() async -> Request {
        if !pending.isEmpty { return pending.removeFirst() }
        return await withCheckedContinuation { waiter = $0 }
    }
    func cancelAll() {
        all.forEach { $0.cancel() }
    }
}
