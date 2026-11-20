import AVFoundation
import Foundation

private actor CaptureScanAssetWriterFinisher {
    private let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }

    func finish() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writer.finishWriting { [weak self] in
                    guard let self else {
                        continuation.resume(
                            throwing: CancellationError()
                        )
                        return
                    }
                    Task {
                        await self.resolveFinish(
                            continuation: continuation
                        )
                    }
                }
            }
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    private func resolveFinish(
        continuation: CheckedContinuation<Void, Error>
    ) {
        switch writer.status {
        case .completed:
            continuation.resume()
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        default:
            continuation.resume(throwing: writer.error ?? NSError(
                domain: "CaptureWorkspaceViewModel",
                code: -21,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unable to finish writing media."
                ]
            ))
        }
    }

    private func cancel() {
        writer.cancelWriting()
    }
}

enum CaptureScanVideoAudioExtractor {
    nonisolated static func extract(
        videoURL: URL,
        outputDirectory: URL = .documentsDirectory
    ) async -> CaptureScanTemporaryFileLease? {
        await withArtifacts { artifacts in
            try await extractWorker(videoURL: videoURL, outputDirectory: outputDirectory, artifacts: artifacts)
        }
    }

    nonisolated private static func extractWorker(
        videoURL: URL, outputDirectory: URL, artifacts: AudioArtifacts
    ) async throws -> CaptureScanTemporaryFileLease? {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: videoURL)
        guard let audioTrack = try await asset.loadTracks(
            withMediaType: .audio
        ).first else {
            return nil
        }
        try Task.checkCancellation()

        let outputName =
            "\(UUID().uuidString.lowercased())-video-audio.wav"
        let outputURL = outputDirectory
            .appendingPathComponent(outputName)
        let outputLease = CaptureScanTemporaryFileLease(
            fileURL: outputURL
        )
        await artifacts.insert(outputLease)

        do {
            if FileManager.default.fileExists(
                atPath: outputURL.path
            ) {
                try FileManager.default.removeItem(at: outputURL)
            }

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let reader = try AVAssetReader(asset: asset)
            let trackOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: audioSettings
            )
            trackOutput.alwaysCopiesSampleData = true
            guard reader.canAdd(trackOutput) else { return nil }
            reader.add(trackOutput)
            defer { if reader.status == .reading { reader.cancelReading() } }

            let writer = try AVAssetWriter(
                outputURL: outputURL,
                fileType: .wav
            )
            // cancelWriting synchronously stops an unfinished writer
            // before the outer owner discards registered artifacts.
            defer { if writer.status == .writing { writer.cancelWriting() } }
            let writerInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioSettings
            )
            writerInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(writerInput) else { return nil }
            writer.add(writerInput)

            guard reader.startReading() else {
                throw reader.error ?? NSError(
                    domain: "CaptureWorkspaceViewModel",
                    code: -22,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Unable to read video audio."
                    ]
                )
            }
            guard writer.startWriting() else {
                throw writer.error ?? NSError(
                    domain: "CaptureWorkspaceViewModel",
                    code: -23,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Unable to write video audio."
                    ]
                )
            }
            writer.startSession(atSourceTime: .zero)

            while reader.status == .reading {
                if Task.isCancelled {
                    reader.cancelReading()
                    writer.cancelWriting()
                    throw CancellationError()
                }
                guard writerInput.isReadyForMoreMediaData else {
                    try await Task.sleep(for: .milliseconds(5))
                    continue
                }
                var reachedEndOfStream = false
                let appendError = autoreleasepool { () -> Error? in
                    guard let sampleBuffer = trackOutput
                        .copyNextSampleBuffer() else {
                        reachedEndOfStream = true
                        return nil
                    }
                    // The writer may retain this buffer after append.
                    // ARC releases our reference; invalidation would
                    // destroy samples still being encoded by the writer.
                    guard writerInput.append(sampleBuffer) else {
                        reader.cancelReading()
                        return writer.error ?? NSError(
                            domain: "CaptureWorkspaceViewModel",
                            code: -24,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Unable to append video audio."
                            ]
                        )
                    }
                    return nil
                }
                if let appendError {
                    throw appendError
                }
                if reachedEndOfStream {
                    break
                }
            }
            writerInput.markAsFinished()

            guard reader.status == .completed else {
                writer.cancelWriting()
                throw reader.error ?? NSError(
                    domain: "CaptureWorkspaceViewModel",
                    code: -25,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Unable to finish reading video audio."
                    ]
                )
            }

            try await CaptureScanAssetWriterFinisher(writer).finish()
            try Task.checkCancellation()

            let attributes = try FileManager.default
                .attributesOfItem(atPath: outputURL.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0
            else {
                try? FileManager.default.removeItem(at: outputURL)
                return nil
            }
            if InferenceAudioPreparer.isCanonicalPreparedWAV(
                at: outputURL
            ) {
                return outputLease
            }

            // AVAssetWriter can emit WAVE_EXTENSIBLE even for Int16
            // PCM. Normalize through the shared bounded converter;
            // the original export stays leased until conversion ends.
            let canonicalURL = try await InferenceAudioPreparer
                .prepareLocalFile(
                    at: outputURL,
                    outputDirectory: outputDirectory
                )
            let canonicalLease = CaptureScanTemporaryFileLease(
                fileURL: canonicalURL
            )
            await artifacts.insert(canonicalLease)
            try Task.checkCancellation()
            return canonicalLease
        } catch is CancellationError {
            return nil
        } catch {
            MerianLog.hardware.error(
                "Video audio extraction failed: \(error, privacy: .private)"
            )
            return nil
        }
    }

    /// The same owner is used by the live extractor and deterministic late-output tests.
    nonisolated private static func withArtifacts(
        operation: @Sendable @escaping (AudioArtifacts) async throws -> CaptureScanTemporaryFileLease?
    ) async -> CaptureScanTemporaryFileLease? {
        let artifacts = AudioArtifacts()
        // Observe actual worker completion before applying caller cancellation.
        let worker = Task.detached(priority: .utility) { try await operation(artifacts) }
        do {
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            let accepted = Task.isCancelled ? nil : result
            await artifacts.discardAll(except: accepted)
            return accepted
        } catch {
            await artifacts.discardAll(except: nil)
            if !(error is CancellationError) {
                MerianLog.hardware.error(
                    "Video audio extraction task failed: \(error, privacy: .private)"
                )
            }
            return nil
        }
    }

    #if DEBUG
    nonisolated static func qualifyArtifactLifecycle(
        operation: @Sendable @escaping (
            @Sendable (URL) async -> CaptureScanTemporaryFileLease
        ) async throws -> CaptureScanTemporaryFileLease?
    ) async -> CaptureScanTemporaryFileLease? {
        await withArtifacts { artifacts in
            try await operation { url in
                let lease = CaptureScanTemporaryFileLease(fileURL: url)
                await artifacts.insert(lease)
                return lease
            }
        }
    }
    #endif

    private actor AudioArtifacts {
        private var leases: [CaptureScanTemporaryFileLease] = []
        func insert(_ lease: CaptureScanTemporaryFileLease) { leases.append(lease) }
        func discardAll(except accepted: CaptureScanTemporaryFileLease?) async {
            for lease in leases where lease !== accepted { await lease.discardReportingFailure() }
            leases.removeAll()
        }
    }
}
