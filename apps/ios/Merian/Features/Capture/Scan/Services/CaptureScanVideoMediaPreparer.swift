import AVFoundation
import Foundation

private actor CaptureScanAssetExportSessionFinisher {
    private let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }

    func export(to outputURL: URL) async throws {
        if #available(iOS 18.0, *) {
            try await session.export(to: outputURL, as: .mp4)
        } else {
            try await exportLegacy()
        }
    }

    private func exportLegacy() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.exportAsynchronously { [weak self] in
                    guard let self else {
                        continuation.resume(
                            throwing: CancellationError()
                        )
                        return
                    }
                    Task {
                        await self.resolveExport(
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

    private func resolveExport(
        continuation: CheckedContinuation<Void, Error>
    ) {
        switch session.status {
        case .completed:
            continuation.resume()
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        default:
            continuation.resume(throwing: session.error ?? NSError(
                domain: "CaptureWorkspaceViewModel",
                code: -27,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unable to export compressed video."
                ]
            ))
        }
    }

    private func cancel() {
        session.cancelExport()
    }
}

enum CaptureScanVideoMediaPreparer {
    private static let inferenceFrameSampleCount = 5
    private static let framePreparationTimeout: TimeInterval = 8
    private static let audioExtractionTimeout: TimeInterval = 5
    private static let playbackPreparationTimeout: TimeInterval = 10

    nonisolated static func prepare(
        _ request: CaptureScanVideoPreparationRequest
    ) async throws -> PreparedCaptureScanVideo {
        let sampledFrames = try await withTimeout(
            seconds: framePreparationTimeout,
            message: "Preparing video frames timed out."
        ) {
            try await prepareFrames(request)
        }
        guard !sampledFrames.isEmpty else {
            throw NSError(
                domain: "CaptureWorkspaceViewModel",
                code: -20,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unable to sample frames from the recorded video."
                ]
            )
        }
        try Task.checkCancellation()

        let audioLease: CaptureScanTemporaryFileLease? = try? await withTimeout(
            seconds: audioExtractionTimeout,
            message: "Extracting video audio timed out."
        ) {
            await CaptureScanVideoAudioExtractor.extract(
                videoURL: request.videoURL
            )
        }

        let playback = try await preparePlaybackClip(
            videoURL: request.videoURL
        )
        var acceptedAudioURL: URL?
        do {
            if let audioLease {
                acceptedAudioURL = try await audioLease.relinquishOwnership()
            }
            try Task.checkCancellation()
        } catch {
            if let acceptedAudioURL {
                try? FileManager.default.removeItem(at: acceptedAudioURL)
            }
            if playback.isCompressed {
                try? FileManager.default.removeItem(at: playback.fileURL)
            }
            throw error
        }
        return PreparedCaptureScanVideo(
            sampledFrames: sampledFrames,
            audioFilePath: acceptedAudioURL?.lastPathComponent,
            playback: playback
        )
    }

    nonisolated private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        message: String,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            defer { group.cancelAll() }
            try Task.checkCancellation()

            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(
                    nanoseconds: UInt64(
                        max(seconds, 0.1) * 1_000_000_000
                    )
                )
                throw NSError(
                    domain: "CaptureWorkspaceViewModel",
                    code: -29,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }
            try Task.checkCancellation()
            return result
        }
    }

    nonisolated private static func prepareFrames(
        _ request: CaptureScanVideoPreparationRequest
    ) async throws -> [PreparedCaptureScanStill] {
        let frameSampleCount = inferenceFrameSampleCount
        return try await DetachedWork.value(
            priority: .userInitiated,
            category: .imagePreparation
        ) {
            let asset = AVURLAsset(url: request.videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(
                width: MerianConfig.displayImageMaxSize,
                height: MerianConfig.displayImageMaxSize
            )

            let sampleOffsets = CaptureScanVideoFrameSamplingPolicy
                .sampleOffsets(
                    duration: request.duration,
                    sampleCount: frameSampleCount
                )
            let times = sampleOffsets.map {
                CMTime(seconds: $0, preferredTimescale: 600)
            }
            let inferenceMaxSize = MerianConfig.inferenceImageMaxSize(
                isProActive: request.isProActive
            )

            var preparedFrames: [PreparedCaptureScanStill] = []
            preparedFrames.reserveCapacity(times.count)

            for time in times {
                try Task.checkCancellation()
                autoreleasepool {
                    guard let frame = try? generator.copyCGImage(
                        at: time,
                        actualTime: nil
                    ) else {
                        MerianLog.hardware.warning(
                            "Video frame sampling skipped frame at \(time.seconds, privacy: .public)s."
                        )
                        return
                    }
                    let displayFrame = ImageCropProcessor.squareCrop(
                        frame,
                        verticalCenterFraction: request.composingCenter
                    ) ?? frame
                    guard let displayData = ImageCropProcessor.encode(
                        displayFrame
                    ), !displayData.isEmpty else {
                        MerianLog.hardware.warning(
                            "Video frame sampling skipped frame because display encoding failed."
                        )
                        return
                    }

                    let inferenceFrame = ImageDownsampler.downsample(
                        data: displayData,
                        maxSize: inferenceMaxSize
                    ) ?? displayFrame
                    let inferenceCropped = ImageCropProcessor.squareCrop(
                        inferenceFrame,
                        verticalCenterFraction: request.composingCenter
                    ) ?? inferenceFrame
                    guard let inferenceData = ImageCropProcessor.encode(
                        inferenceCropped
                    ), !inferenceData.isEmpty else {
                        MerianLog.hardware.warning(
                            "Video frame sampling skipped frame because inference encoding failed."
                        )
                        return
                    }

                    preparedFrames.append(PreparedCaptureScanStill(
                        inferenceData: inferenceData,
                        displayData: displayData,
                        previewCGImage: SendableCGImage(
                            image: displayFrame
                        )
                    ))
                }
            }
            try Task.checkCancellation()

            MerianLog.hardware.debug(
                "Video frame sampling prepared \(preparedFrames.count, privacy: .public)/\(times.count, privacy: .public) frames."
            )
            return preparedFrames
        }
    }

    nonisolated private static func preparePlaybackClip(
        videoURL: URL
    ) async throws -> PreparedCaptureScanVideoPlayback {
        let originalSize = try fileSize(at: videoURL)
        let exportStart = CFAbsoluteTimeGetCurrent()

        do {
            let compressedLease = try await withTimeout(
                seconds: playbackPreparationTimeout,
                message: "Preparing video playback timed out."
            ) {
                try await compressVideoForPlayback(videoURL: videoURL)
            }
            let compressedURL = compressedLease.fileURL
            let compressedSize = try fileSize(at: compressedURL)
            guard compressedSize > 0,
                  compressedSize <= MerianConfig.videoPayloadMaxBytes else {
                try? FileManager.default.removeItem(at: compressedURL)
                let sizeError = NSError(
                    domain: "CaptureWorkspaceViewModel",
                    code: -26,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Compressed video exceeds the upload budget."
                    ]
                )
                guard originalSize <= MerianConfig.videoPayloadMaxBytes else {
                    throw sizeError
                }
                MerianLog.hardware.warning(
                    """
                    Video compression produced unusable output; staging original upload-safe clip. \
                    originalBytes=\(originalSize, privacy: .public), \
                    compressedBytes=\(compressedSize, privacy: .public)
                    """
                )
                return PreparedCaptureScanVideoPlayback(
                    fileURL: videoURL,
                    isCompressed: false,
                    originalBytes: originalSize,
                    playbackBytes: originalSize,
                    preparationDuration:
                        CFAbsoluteTimeGetCurrent() - exportStart
                )
            }
            MerianLog.hardware.debug(
                """
                Video compression completed. \
                duration=\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - exportStart), privacy: .public)s, \
                originalBytes=\(originalSize, privacy: .public), \
                compressedBytes=\(compressedSize, privacy: .public), \
                compressionRatio=\(String(format: "%.3f", Double(compressedSize) / Double(max(originalSize, 1))), privacy: .public), \
                source=compressed, \
                fallback=false
                """
            )
            if compressedSize >= originalSize,
               originalSize <= MerianConfig.videoPayloadMaxBytes {
                try? FileManager.default.removeItem(at: compressedURL)
                MerianLog.hardware.warning(
                    """
                    Video compression was not smaller; staging original upload-safe clip. \
                    originalBytes=\(originalSize, privacy: .public), \
                    compressedBytes=\(compressedSize, privacy: .public), \
                    compressionRatio=\(String(format: "%.3f", Double(compressedSize) / Double(max(originalSize, 1))), privacy: .public), \
                    source=original, \
                    fallback=true
                    """
                )
                return PreparedCaptureScanVideoPlayback(
                    fileURL: videoURL,
                    isCompressed: false,
                    originalBytes: originalSize,
                    playbackBytes: originalSize,
                    preparationDuration:
                        CFAbsoluteTimeGetCurrent() - exportStart
                )
            }
            try Task.checkCancellation()
            let acceptedURL = try await compressedLease.relinquishOwnership()
            do {
                try Task.checkCancellation()
            } catch {
                try? FileManager.default.removeItem(at: acceptedURL)
                throw error
            }
            return PreparedCaptureScanVideoPlayback(
                fileURL: acceptedURL,
                isCompressed: true,
                originalBytes: originalSize,
                playbackBytes: compressedSize,
                preparationDuration:
                    CFAbsoluteTimeGetCurrent() - exportStart
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            MerianLog.hardware.error(
                "Video compression failed: \(error, privacy: .private)"
            )
            guard originalSize <= MerianConfig.videoPayloadMaxBytes else {
                MerianLog.hardware.error(
                    """
                    Video staging failed because neither compression nor the original clip fit the upload budget. \
                    originalBytes=\(originalSize, privacy: .public), \
                    maxBytes=\(MerianConfig.videoPayloadMaxBytes, privacy: .public)
                    """
                )
                throw error
            }
            MerianLog.hardware.warning(
                """
                Video compression unavailable; staging original upload-safe clip. \
                originalBytes=\(originalSize, privacy: .public), \
                maxBytes=\(MerianConfig.videoPayloadMaxBytes, privacy: .public), \
                source=original, \
                fallback=true
                """
            )
            return PreparedCaptureScanVideoPlayback(
                fileURL: videoURL,
                isCompressed: false,
                originalBytes: originalSize,
                playbackBytes: originalSize,
                preparationDuration:
                    CFAbsoluteTimeGetCurrent() - exportStart
            )
        }
    }

    nonisolated private static func compressVideoForPlayback(
        videoURL: URL
    ) async throws -> CaptureScanTemporaryFileLease {
        let asset = AVURLAsset(url: videoURL)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw NSError(
                domain: "CaptureWorkspaceViewModel",
                code: -27,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Recorded video has no video track."
                ]
            )
        }

        let presetName = MerianConfig.videoPlaybackLongEdgeMaxPixels <= 1280
            ? AVAssetExportPreset1280x720
            : AVAssetExportPresetHighestQuality
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: presetName
        ) else {
            throw NSError(
                domain: "CaptureWorkspaceViewModel",
                code: -28,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unable to prepare compressed video export."
                ]
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "\(UUID().uuidString.lowercased())_video_playback.mp4"
            )
        let outputLease = CaptureScanTemporaryFileLease(fileURL: outputURL)
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.fileLengthLimit = Int64(
            MerianConfig.videoPlaybackExpectedMaxBytes
        )

        try await CaptureScanAssetExportSessionFinisher(exportSession)
            .export(to: outputURL)
        try Task.checkCancellation()
        return outputLease
    }

    nonisolated private static func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }
}
