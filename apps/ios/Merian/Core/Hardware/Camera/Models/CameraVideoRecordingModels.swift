import Foundation

struct CameraVideoRecording: Sendable {
    let fileURL: URL
    let duration: TimeInterval
}

/// Stable identity for one logical recording and its AVFoundation callback URL.
struct CameraVideoRecordingGeneration: Equatable, Sendable {
    let id: UUID
    let outputURL: URL

    init(id: UUID, outputURL: URL) {
        self.id = id
        self.outputURL = outputURL.standardizedFileURL
    }

    func matches(callbackURL: URL) -> Bool {
        outputURL == callbackURL.standardizedFileURL
    }
}

/// Identifies one scheduled action within a recording generation.
///
/// Task cancellation is cooperative, so replacing a task requires a second
/// token in addition to the recording generation.
struct CameraVideoRecordingScheduledAction: Equatable, Sendable {
    let generation: CameraVideoRecordingGeneration
    let id: UUID
}
