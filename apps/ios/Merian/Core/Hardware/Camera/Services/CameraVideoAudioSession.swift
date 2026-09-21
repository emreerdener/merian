@preconcurrency import AVFoundation
import Foundation

/// Holds the process-wide audio lease for exactly one movie request, including
/// preparation and cleanup. Playback teardown cannot deactivate that lease.
@MainActor
final class CameraVideoAudioSession {
    struct Dependencies: Sendable {
        let coordinator: AudioSessionCoordinator
        let configureInput: @Sendable (_ includeAudio: Bool) async -> Void
    }

    private let dependencies: Dependencies
    private var isInUse = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    convenience init(
        sessionProvider: @escaping @Sendable () -> AVCaptureSession,
        queue: DispatchQueue
    ) {
        self.init(dependencies: Dependencies(
            coordinator: .shared,
            configureInput: { includeAudio in
                await Self.configureInput(
                    includeAudio,
                    sessionProvider: sessionProvider,
                    queue: queue
                )
            }
        ))
    }

    func withAudio<Result>(
        includeAudio: Bool,
        operation: @MainActor () async throws -> Result
    ) async throws -> Result {
        guard !isInUse else {
            throw NSError(
                domain: "CameraManager", code: -7,
                userInfo: [NSLocalizedDescriptionKey: "Video recording is already in progress."]
            )
        }
        isInUse = true
        defer { isInUse = false }
        var lease: AudioSessionCoordinator.Lease?
        do {
            try Task.checkCancellation()
            // Disable AVFoundation's independent shared-session configuration
            // before acquiring our lease, including for silent recordings.
            await dependencies.configureInput(false)
            if includeAudio {
                lease = try await dependencies.coordinator.activate(.videoRecording)
                try Task.checkCancellation()
                await dependencies.configureInput(true)
            }
            try Task.checkCancellation()
            let result = try await operation()
            await finish(lease: lease)
            return result
        } catch {
            await finish(lease: lease)
            throw error
        }
    }

    private func finish(lease: AudioSessionCoordinator.Lease?) async {
        // Detach the microphone before deactivation; an idle camera preview
        // must not retain a recording input or interfere with later playback.
        await dependencies.configureInput(false)
        await dependencies.coordinator.deactivate(ifCurrent: lease)
    }

    nonisolated private static func configureInput(
        _ includeAudio: Bool,
        sessionProvider: @escaping @Sendable () -> AVCaptureSession,
        queue: DispatchQueue
    ) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let session = sessionProvider()
                session.automaticallyConfiguresApplicationAudioSession = false
                let inputs = session.inputs.filter {
                    ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true
                }
                if !includeAudio, !inputs.isEmpty {
                    session.beginConfiguration()
                    inputs.forEach { session.removeInput($0) }
                    session.commitConfiguration()
                } else if inputs.isEmpty,
                          let device = AVCaptureDevice.default(for: .audio),
                          let input = try? AVCaptureDeviceInput(device: device),
                          session.canAddInput(input) {
                    session.beginConfiguration()
                    session.addInput(input)
                    session.commitConfiguration()
                }
                continuation.resume()
            }
        }
    }
}
