import Testing

@testable import Merian

@Suite("SpeechManager lifecycle")
@MainActor
struct SpeechManagerTests {
    @Test("A final transcript accompanied by an error is retained but cannot authorize submission")
    func finalResultWithErrorRetainsTextAndRejectsSubmission() async {
        let manager = SpeechManager()
        let id = manager.debugBeginRecognition()
        var text = "partial"
        let finish = Task { await manager.finishDictation() }
        for _ in 0..<100 where !manager.debugIsFinalizing { await Task.yield() }
        manager.debugReceiveRecognition(session: id, text: "latest", isFinal: true, failed: true) { text = $0 }
        #expect(await finish.value == false)
        #expect(text == "latest")
        #expect(!manager.isRecording)
    }

    @Test("Finalization delivers final text before allowing submission")
    func finalTextPrecedesCompletion() async {
        let manager = SpeechManager()
        let id = manager.debugBeginRecognition()
        var text = "partial"
        let finish = Task { await manager.finishDictation() }
        for _ in 0..<100 where !manager.debugIsFinalizing { await Task.yield() }
        #expect(manager.debugIsFinalizing)
        manager.debugReceiveRecognition(session: id, text: "complete", isFinal: true) { text = $0 }
        #expect(await finish.value)
        #expect(text == "complete")
        #expect(!manager.isRecording)
        #expect(!manager.debugHasAudioEngine)
    }

    @Test("Old recognition cannot mutate or stop a replacement session")
    func staleRecognitionCannotStopReplacement() {
        let manager = SpeechManager()
        let old = manager.debugBeginRecognition()
        let current = manager.debugBeginRecognition()
        var delivered = false
        manager.debugReceiveRecognition(session: old, text: "stale", isFinal: true) { _ in delivered = true }
        #expect(!delivered)
        #expect(manager.isRecording)
        manager.debugReceiveRecognition(session: current, text: "current", isFinal: true) { _ in delivered = true }
        #expect(delivered)
        #expect(!manager.isRecording)
    }

    @Test("Error and duplicate terminal callbacks settle finalization only once")
    func errorRejectsFinalization() async {
        let manager = SpeechManager()
        let id = manager.debugBeginRecognition()
        let finish = Task { await manager.finishDictation() }
        for _ in 0..<100 where !manager.debugIsFinalizing { await Task.yield() }
        manager.debugReceiveRecognition(session: id, text: nil, failed: true) { _ in }
        manager.debugReceiveRecognition(session: id, text: "late", isFinal: true) { _ in
            Issue.record("Terminal session must reject late text")
        }
        #expect(await finish.value == false)
    }

    @Test("Timeout and cancellation retain a failed outcome without microphone setup")
    func finalizationTimeoutAndCancellation() async {
        let manager = SpeechManager()
        _ = manager.debugBeginRecognition()
        #expect(await manager.finishDictation(timeout: .zero) == false)
        #expect(!manager.isRecording)
        _ = manager.debugBeginRecognition()
        let finish = Task { await manager.finishDictation() }
        for _ in 0..<100 where !manager.debugIsFinalizing { await Task.yield() }
        finish.cancel()
        #expect(await finish.value == false)
        #expect(!manager.debugHasAudioEngine)
    }

    @Test("Stopping before first dictation does not initialize microphone input")
    func stoppingBeforeFirstDictationDoesNotInitializeInput() {
        let manager = SpeechManager()

        #expect(manager.debugHasAudioEngine == false)
        manager.stopDictation()
        #expect(
            manager.debugHasAudioEngine == false,
            "Cleanup before the first user action must not initialize audio input"
        )
    }

    @Test("Cancelled startup resets dictation state")
    func cancelledStartupResetsDictationState() {
        let manager = SpeechManager()
        manager.audioLevel = 0.75
        manager.isRecording = true

        manager.debugHandleStartupCancellation()

        #expect(manager.audioLevel == 0.0)
        #expect(manager.isRecording == false)
    }
}
