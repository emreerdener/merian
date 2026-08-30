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
        videoURL: URL
    ) async -> CaptureScanTemporaryFileLease? {
        do {
            return try await DetachedWork.value(
                priority: .utility,
                category: .backgroundDatabaseMutation
            ) {
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
                let outputURL = URL.documentsDirectory
                    .appendingPathComponent(outputName)
                let outputLease = CaptureScanTemporaryFileLease(
                    fileURL: outputURL
                )

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

                    let writer = try AVAssetWriter(
                        outputURL: outputURL,
                        fileType: .wav
                    )
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
                            defer {
                                _ = CMSampleBufferInvalidate(sampleBuffer)
                            }

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
                    guard InferenceAudioPreparer.isEdgeCompatibleWAV(
                        at: outputURL
                    ) else {
                        try? FileManager.default.removeItem(at: outputURL)
                        MerianLog.hardware.warning(
                            "Video audio extraction produced a WAV variant the edge parser cannot use; continuing without video audio."
                        )
                        return nil
                    }

                    return outputLease
                } catch is CancellationError {
                    return nil
                } catch {
                    MerianLog.hardware.error(
                        "Video audio extraction failed: \(error, privacy: .private)"
                    )
                    return nil
                }
            }
        } catch is CancellationError {
            return nil
        } catch {
            MerianLog.hardware.error(
                "Video audio extraction task failed: \(error, privacy: .private)"
            )
            return nil
        }
    }

}
