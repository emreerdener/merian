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
        self.outputURL = Self.canonicalFileURL(outputURL)
    }

    func matches(callbackURL: URL) -> Bool {
        callbackURL.isFileURL && outputURL == Self.canonicalFileURL(callbackURL)
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        // The movie does not exist when the request is created. Resolve its
        // existing parent, since resolving a nonexistent leaf leaves aliases
        // such as /var versus /private/var intact on Apple platforms.
        let standardized = url.standardizedFileURL
        return standardized.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(standardized.lastPathComponent, isDirectory: false)
            .standardizedFileURL
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
