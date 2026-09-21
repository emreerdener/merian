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
                do {
                    lease = try await dependencies.coordinator.activate(.videoRecording)
                } catch {
                    try Task.checkCancellation()
                    let audioError = error as NSError
                    guard audioError.domain == NSOSStatusErrorDomain,
                          audioError.code == AVAudioSession.ErrorCode.insufficientPriority.rawValue else {
                        throw error
                    }
                    // Phone calls own the microphone at higher priority. The
                    // coordinator has already rolled back failed activation;
                    // continue through the existing microphone-free video path.
                    MerianLog.hardware.warning("Video microphone unavailable at current audio priority; recording without audio.")
                }
                if lease != nil {
                    try Task.checkCancellation()
                    await dependencies.configureInput(true)
                }
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

    nonisolated static func configureInput(
        _ includeAudio: Bool,
        sessionProvider: @escaping @Sendable () -> AVCaptureSession,
        queue: DispatchQueue,
        makeAudioInput: @escaping @Sendable () -> AVCaptureDeviceInput? = {
            guard let device = AVCaptureDevice.default(for: .audio) else { return nil }
            return try? AVCaptureDeviceInput(device: device)
        }
    ) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let session = sessionProvider()
                session.automaticallyConfiguresApplicationAudioSession = false
                let inputs = session.inputs.filter {
                    ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true
                }
                // Empty detach requests must stay inert: discovering an input
                // here attaches the microphone before the recording lease, or
                // even when permission policy selected a silent recording.
                if !includeAudio, !inputs.isEmpty {
                    session.beginConfiguration()
                    inputs.forEach { session.removeInput($0) }
                    session.commitConfiguration()
                } else if includeAudio, inputs.isEmpty,
                          let input = makeAudioInput(),
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
