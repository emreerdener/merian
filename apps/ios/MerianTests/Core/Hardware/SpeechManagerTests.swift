import Testing

@testable import Merian

@Suite("SpeechManager lifecycle")
@MainActor
struct SpeechManagerTests {
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
