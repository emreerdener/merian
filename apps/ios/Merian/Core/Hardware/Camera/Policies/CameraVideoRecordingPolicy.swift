@preconcurrency import AVFoundation
import Foundation

/// Video capture may reuse microphone access the user already granted while recording
/// audio or dictating, but it must never be the feature that asks for that permission.
enum CameraVideoAudioPermissionPolicy {
    static func shouldIncludeAudio(
        for permission: AVAudioApplication.recordPermission
    ) -> Bool {
        permission == .granted
    }
}

/// Pure, lock-independent correlation policy used by the recording state machine.
struct CameraVideoRecordingGenerationGate: Sendable {
    let generation: CameraVideoRecordingGeneration
    private(set) var timeoutActionID: UUID?
    private(set) var stopActionID: UUID?

    func matches(_ candidate: CameraVideoRecordingGeneration) -> Bool {
        generation == candidate
    }

    func matches(callbackURL: URL) -> Bool {
        generation.matches(callbackURL: callbackURL)
    }

    mutating func installTimeoutAction(_ action: CameraVideoRecordingScheduledAction) -> Bool {
        guard matches(action.generation) else { return false }
        timeoutActionID = action.id
        return true
    }

    mutating func installStopAction(_ action: CameraVideoRecordingScheduledAction) -> Bool {
        guard matches(action.generation) else { return false }
        stopActionID = action.id
        return true
    }

    func acceptsTimeoutAction(_ action: CameraVideoRecordingScheduledAction) -> Bool {
        matches(action.generation) && timeoutActionID == action.id
    }

    func acceptsStopAction(_ action: CameraVideoRecordingScheduledAction) -> Bool {
        matches(action.generation) && stopActionID == action.id
    }

    mutating func clearStopAction() {
        stopActionID = nil
    }
}
