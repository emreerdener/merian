@preconcurrency import AVFoundation
import Foundation

/// Owns one bioacoustic recording engine, its input tap, WAV, DSP stream, and
/// recording-specific audio-session lease.
@MainActor
final class AudioRecordingEngineController {
    typealias EvaluationHandler =
        @MainActor @Sendable ([AudioRecordingColumnEvaluation]) -> Void

    struct Engine: Sendable {
        let readInputFormat: @Sendable () -> AudioRecordingInputFormat
        let reset: @Sendable () -> Void
        let installTap:
            @Sendable (
                URL,
                AsyncStream<AVAudioPCMBuffer>.Continuation
            ) throws -> Void
        let prepare: @Sendable () -> Void
        let start: @Sendable () throws -> Void
        let pause: @Sendable () -> Void
        let removeTap: @Sendable () -> Void
        let stop: @Sendable () -> Void

        static func live(
            startEngine: @escaping @Sendable (AVAudioEngine) throws -> Void
        ) -> Self {
            let engine = AVAudioEngine()
            return Self(
                readInputFormat: {
                    AudioRecordingInputFormat(
                        engine.inputNode.outputFormat(forBus: 0)
                    )
                },
                reset: {
                    engine.reset()
                },
                installTap: { fileURL, continuation in
                    let inputNode = engine.inputNode
                    let inputFormat = inputNode.outputFormat(forBus: 0)
                    let input = AudioRecordingInputFormat(inputFormat)
                    guard input.isUsable,
                          let outputFormat = AudioRecordingWAVFormatPolicy
                              .makeFormat(
                                  sampleRate: input.sampleRate,
                                  channelCount: input.channelCount
                              ) else {
                        throw AudioCaptureError.hardwareSampleRateZero
                    }
                    let file = try AVAudioFile(
                        forWriting: fileURL,
                        settings: outputFormat.settings
                    )

                    inputNode.removeTap(onBus: 0)
                    inputNode.installTap(
                        onBus: 0,
                        bufferSize: 4096,
                        format: inputFormat
                    ) { buffer, _ in
                        try? file.write(from: buffer)
                        guard let retainedBuffer =
                            AudioRecordingEngineController.copyPCMBuffer(
                                buffer
                            ) else { return }
                        continuation.yield(retainedBuffer)
                    }
                },
                prepare: {
                    engine.prepare()
                },
                start: {
                    try startEngine(engine)
                },
                pause: {
                    engine.pause()
                },
                removeTap: {
                    engine.inputNode.removeTap(onBus: 0)
                },
                stop: {
                    engine.stop()
                }
            )
        }

        #if DEBUG
        static var debugNoop: Self {
            Self(
                readInputFormat: {
                    AudioRecordingInputFormat(
                        sampleRate: 48_000,
                        channelCount: 1
                    )
                },
                reset: {},
                installTap: { _, _ in },
                prepare: {},
                start: {},
                pause: {},
                removeTap: {},
                stop: {}
            )
        }
        #endif
    }

    struct Dependencies: Sendable {
        let makeEngine: @MainActor @Sendable () -> Engine
        let activateSession:
            @Sendable (_ preferredSampleRate: Double?) async throws
                -> AudioSessionCoordinator.Lease
        let deactivateSession:
            @Sendable (AudioSessionCoordinator.Lease) async -> Void
        let waitForInputRouteRecovery: @Sendable () async throws -> Void
        let makeFileURL: @Sendable () -> URL
        let deleteFile: @Sendable (URL) -> Void

        init(
            makeEngine: @escaping @MainActor @Sendable () -> Engine,
            activateSession: @escaping @Sendable (
                _ preferredSampleRate: Double?
            ) async throws -> AudioSessionCoordinator.Lease,
            deactivateSession: @escaping @Sendable (
                AudioSessionCoordinator.Lease
            ) async -> Void,
            waitForInputRouteRecovery: @escaping @Sendable () async throws
                -> Void,
            makeFileURL: @escaping @Sendable () -> URL,
            deleteFile: @escaping @Sendable (URL) -> Void
        ) {
            self.makeEngine = makeEngine
            self.activateSession = activateSession
            self.deactivateSession = deactivateSession
            self.waitForInputRouteRecovery = waitForInputRouteRecovery
            self.makeFileURL = makeFileURL
            self.deleteFile = deleteFile
        }

        init(
            activateSession: @escaping @Sendable (
                _ preferredSampleRate: Double?
            ) async throws -> AudioSessionCoordinator.Lease,
            deactivateSession: @escaping @Sendable (
                AudioSessionCoordinator.Lease?
            ) async -> Void,
            startEngine: @escaping @Sendable (AVAudioEngine) throws -> Void
        ) {
            self.init(
                makeEngine: {
                    Engine.live(startEngine: startEngine)
                },
                activateSession: activateSession,
                deactivateSession: { lease in
                    await deactivateSession(lease)
                },
                waitForInputRouteRecovery: {
                    try await Task.sleep(nanoseconds: 75_000_000)
                },
                makeFileURL: {
                    FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(UUID().uuidString).wav")
                },
                deleteFile: { url in
                    try? FileManager.default.removeItem(at: url)
                }
            )
        }

        static let live = Self(
            activateSession: { preferredSampleRate in
                try await AudioSessionCoordinator.shared.activate(
                    .recordMeasurement(
                        preferredSampleRate: preferredSampleRate
                    )
                )
            },
            deactivateSession: { lease in
                await AudioSessionCoordinator.shared.deactivate(
                    ifCurrent: lease
                )
            },
            startEngine: { engine in
                try engine.start()
            }
        )
    }

    private struct ActiveRecording {
        let id: UUID
        let engine: Engine
        let fileURL: URL
        let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
        let dspTask: Task<Void, Never>?
        var lease: AudioSessionCoordinator.Lease?
    }

    nonisolated private static let inputFormatRecoveryAttempts = 4

    private let dependencies: Dependencies
    private let spectrogram = SpectrogramActor()
    private var activeRecording: ActiveRecording?
    private var pendingOperation: UUID?
    private var setupTask: Task<Void, Error>?

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func start(
        preferredSampleRate: Double?,
        onEvaluations: @escaping EvaluationHandler
    ) async throws -> String {
        guard activeRecording == nil else { throw CancellationError() }

        let recordingID = UUID()
        let operation = UUID()
        let engine = dependencies.makeEngine()
        let fileURL = dependencies.makeFileURL()
        let (stream, continuation) = AsyncStream.makeStream(
            of: AVAudioPCMBuffer.self,
            bufferingPolicy: .bufferingNewest(2)
        )
        let dspTask = makeDSPTask(
            stream: stream,
            recordingID: recordingID,
            onEvaluations: onEvaluations
        )
        activeRecording = ActiveRecording(
            id: recordingID,
            engine: engine,
            fileURL: fileURL,
            continuation: continuation,
            dspTask: dspTask
        )
        pendingOperation = operation

        let dependencies = self.dependencies
        let task = Task.detached { [weak self] in
            let lease = try await dependencies.activateSession(
                preferredSampleRate
            )
            guard !Task.isCancelled else {
                await dependencies.deactivateSession(lease)
                throw CancellationError()
            }
            let installed = await self?.install(
                lease: lease,
                recordingID: recordingID,
                operation: operation
            ) ?? false
            guard installed else {
                await dependencies.deactivateSession(lease)
                throw CancellationError()
            }
            try Task.checkCancellation()
            try await Self.prepareAndStart(
                engine: engine,
                fileURL: fileURL,
                continuation: continuation,
                waitForInputRouteRecovery:
                    dependencies.waitForInputRouteRecovery
            )
        }
        setupTask = task

        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            setupTask = nil
            tearDownIfCurrent(recordingID, deleteFile: true)
            throw error
        }
        setupTask = nil

        guard !Task.isCancelled,
              isCurrent(recordingID, operation: operation) else {
            tearDownIfCurrent(recordingID, deleteFile: true)
            throw CancellationError()
        }
        pendingOperation = nil
        return fileURL.lastPathComponent
    }

    func resume(preferredSampleRate: Double?) async throws {
        guard setupTask == nil,
              pendingOperation == nil,
              let recording = activeRecording else {
            throw CancellationError()
        }
        let operation = UUID()
        pendingOperation = operation

        let lease: AudioSessionCoordinator.Lease
        do {
            lease = try await dependencies.activateSession(
                preferredSampleRate
            )
        } catch {
            if pendingOperation == operation {
                pendingOperation = nil
            }
            throw error
        }
        guard !Task.isCancelled,
              install(
                  lease: lease,
                  recordingID: recording.id,
                  operation: operation
              ) else {
            await dependencies.deactivateSession(lease)
            throw CancellationError()
        }

        do {
            try recording.engine.start()
        } catch {
            pendingOperation = nil
            tearDownIfCurrent(recording.id, deleteFile: true)
            throw error
        }
        guard isCurrent(recording.id, operation: operation) else {
            recording.engine.pause()
            throw CancellationError()
        }
        pendingOperation = nil
    }

    func pause() {
        guard setupTask == nil, let recording = activeRecording else { return }
        invalidatePendingOperation()
        recording.engine.pause()
    }

    @discardableResult
    func finishRecording() -> String? {
        guard setupTask == nil else { return nil }
        return tearDown(deleteFile: false)?.lastPathComponent
    }

    @discardableResult
    func cancelRecording() -> String? {
        guard setupTask == nil else {
            invalidatePendingOperation()
            return nil
        }
        return tearDown(deleteFile: true)?.lastPathComponent
    }

    func invalidatePendingOperation() {
        pendingOperation = nil
        setupTask?.cancel()
    }

    func resetAnalysis() {
        Task { await spectrogram.reset() }
    }

    private func install(
        lease: AudioSessionCoordinator.Lease,
        recordingID: UUID,
        operation: UUID
    ) -> Bool {
        guard var recording = activeRecording,
              recording.id == recordingID,
              pendingOperation == operation else {
            return false
        }
        recording.lease = lease
        activeRecording = recording
        return true
    }

    private func isCurrent(_ recordingID: UUID, operation: UUID) -> Bool {
        activeRecording?.id == recordingID
            && pendingOperation == operation
    }

    private func makeDSPTask(
        stream: AsyncStream<AVAudioPCMBuffer>,
        recordingID: UUID,
        onEvaluations: @escaping EvaluationHandler
    ) -> Task<Void, Never> {
        let spectrogram = self.spectrogram
        let publish: EvaluationHandler = { [weak self] evaluations in
            guard self?.activeRecording?.id == recordingID else { return }
            onEvaluations(evaluations)
        }
        return Task.detached {
            for await buffer in stream {
                if Task.isCancelled { break }
                let columns = await spectrogram.processColumns(buffer: buffer)
                guard !columns.isEmpty else { continue }

                var evaluations: [AudioRecordingColumnEvaluation] = []
                evaluations.reserveCapacity(columns.count)
                for column in columns {
                    evaluations.append(
                        AudioRecordingColumnEvaluation(
                            column: column,
                            snrLevel: await spectrogram.snrLevel(from: column)
                        )
                    )
                }
                await publish(evaluations)
            }
        }
    }

    private func tearDownIfCurrent(
        _ recordingID: UUID,
        deleteFile: Bool
    ) {
        guard activeRecording?.id == recordingID else { return }
        _ = tearDown(deleteFile: deleteFile)
    }

    private func tearDown(deleteFile: Bool) -> URL? {
        guard let recording = activeRecording else { return nil }
        activeRecording = nil
        pendingOperation = nil
        setupTask?.cancel()
        setupTask = nil
        recording.continuation?.finish()
        recording.engine.removeTap()
        recording.engine.stop()
        recording.dspTask?.cancel()
        deactivate(recording.lease)
        if deleteFile {
            dependencies.deleteFile(recording.fileURL)
        }
        return recording.fileURL
    }

    private func deactivate(_ lease: AudioSessionCoordinator.Lease?) {
        guard let lease else { return }
        let deactivateSession = dependencies.deactivateSession
        Task {
            await deactivateSession(lease)
        }
    }

    nonisolated private static func prepareAndStart(
        engine: Engine,
        fileURL: URL,
        continuation: AsyncStream<AVAudioPCMBuffer>.Continuation,
        waitForInputRouteRecovery: @Sendable () async throws -> Void
    ) async throws {
        var inputFormat = engine.readInputFormat()
        if !inputFormat.isUsable {
            for _ in 0..<inputFormatRecoveryAttempts {
                try Task.checkCancellation()
                try await waitForInputRouteRecovery()
                engine.reset()
                inputFormat = engine.readInputFormat()
                if inputFormat.isUsable { break }
            }
        }
        guard inputFormat.isUsable else {
            throw AudioCaptureError.hardwareSampleRateZero
        }

        try engine.installTap(fileURL, continuation)
        try Task.checkCancellation()
        engine.prepare()
        try engine.start()
    }

    nonisolated private static func copyPCMBuffer(
        _ buffer: AVAudioPCMBuffer
    ) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else { return nil }
        copy.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(
            buffer.mutableAudioBufferList
        )
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(
            copy.mutableAudioBufferList
        )
        guard sourceBuffers.count == destinationBuffers.count else { return nil }

        for index in 0..<sourceBuffers.count {
            let sourceBuffer = sourceBuffers[index]
            guard let sourceData = sourceBuffer.mData,
                  let destinationData = destinationBuffers[index].mData else {
                return nil
            }
            memcpy(
                destinationData,
                sourceData,
                Int(sourceBuffer.mDataByteSize)
            )
            destinationBuffers[index].mDataByteSize = sourceBuffer.mDataByteSize
        }
        return copy
    }

    #if DEBUG
    var debugHasActiveEngine: Bool { activeRecording != nil }
    var debugHasDSPTask: Bool { activeRecording?.dspTask != nil }

    func debugStageStartup(
        fileURL: URL,
        dspTask: Task<Void, Never>?
    ) {
        activeRecording = ActiveRecording(
            id: UUID(),
            engine: .debugNoop,
            fileURL: fileURL,
            continuation: nil,
            dspTask: dspTask
        )
    }

    func debugStagePausedRecording() {
        activeRecording = ActiveRecording(
            id: UUID(),
            engine: dependencies.makeEngine(),
            fileURL: dependencies.makeFileURL(),
            continuation: nil,
            dspTask: nil
        )
    }
    #endif
}
