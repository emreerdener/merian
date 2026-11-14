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

    struct PlaybackArtifact: Sendable {
        let playback: PreparedCaptureScanVideoPlayback
        var lease: CaptureScanTemporaryFileLease?
    }

    struct Dependencies: Sendable {
        var frames: @Sendable (CaptureScanVideoPreparationRequest) async throws -> [PreparedCaptureScanStill]
        var audio: @Sendable (URL) async -> CaptureScanTemporaryFileLease?
        var playback: @Sendable (URL) async throws -> PlaybackArtifact

        nonisolated static var live: Self {
            Self(
                frames: { try await prepareFrames($0) },
                audio: { await CaptureScanVideoAudioExtractor.extract(videoURL: $0) },
                playback: { try await preparePlaybackClip(videoURL: $0) }
            )
        }
    }

    nonisolated static func prepare(
        _ request: CaptureScanVideoPreparationRequest,
        dependencies: Dependencies = .live
    ) async throws -> PreparedCaptureScanVideo {
        let preparationStart = CFAbsoluteTimeGetCurrent()
        let artifacts = try await prepareArtifacts(request, dependencies: dependencies)
        let audioLease = artifacts.audio, playbackArtifact = artifacts.playback
        var acceptedAudioURL: URL?
        var acceptedPlaybackURL: URL?
        do {
            try Task.checkCancellation()
            if let audioLease {
                acceptedAudioURL = try await audioLease.relinquishOwnership()
            }
            if let lease = playbackArtifact.lease {
                acceptedPlaybackURL = try await lease.relinquishOwnership()
            }
            try Task.checkCancellation()
        } catch {
            for url in [acceptedAudioURL, acceptedPlaybackURL].compactMap({ $0 }) {
                do { try FileManager.default.removeItem(at: url) } catch { MerianLog.hardware.error("Accepted capture rollback cleanup failed: \(error, privacy: .private)") }
            }
            await audioLease?.discardReportingFailure()
            await playbackArtifact.lease?.discardReportingFailure()
            throw error
        }
        MerianLog.hardware.debug(
            "Video preparation completed: totalSeconds=\(CFAbsoluteTimeGetCurrent() - preparationStart, privacy: .public)"
        )
        return PreparedCaptureScanVideo(
            sampledFrames: artifacts.frames,
            audioFilePath: acceptedAudioURL?.lastPathComponent,
            playback: playbackArtifact.playback
        )
    }

    private enum Stage: Sendable {
        case frames([PreparedCaptureScanStill])
        case audio(CaptureScanTemporaryFileLease?)
        case playback(PlaybackArtifact)

        func discard() async {
            switch self {
            case .frames: break
            case .audio(let lease): await lease?.discardReportingFailure()
            case .playback(let artifact): await artifact.lease?.discardReportingFailure()
            }
        }
    }

    private struct Artifacts: Sendable {
        let frames: [PreparedCaptureScanStill]
        let audio: CaptureScanTemporaryFileLease?
        let playback: PlaybackArtifact
    }

    /// Collect every successful result, including results delivered after
    /// cancellation. Returning/throwing is an explicit cleanup boundary, not ARC.
    nonisolated private static func prepareArtifacts(
        _ request: CaptureScanVideoPreparationRequest, dependencies: Dependencies
    ) async throws -> Artifacts {
        try await withThrowingTaskGroup(of: Stage.self) { group in
            group.addTask {
                let frames = try await withTimeout(seconds: framePreparationTimeout,
                    message: "Preparing video frames timed out.",
                    operation: { try await dependencies.frames(request) })
                guard !frames.isEmpty else {
                    throw NSError(domain: "CaptureWorkspaceViewModel", code: -20,
                        userInfo: [NSLocalizedDescriptionKey: "Unable to sample frames from the recorded video."])
                }
                return .frames(frames)
            }
            group.addTask { .audio(await optionalAudio(videoURL: request.videoURL, dependencies: dependencies)) }
            group.addTask { .playback(try await dependencies.playback(request.videoURL)) }
            var results: [Stage] = []
            do {
                while let result = try await group.next() { results.append(result) }
                var frames: [PreparedCaptureScanStill]?, audio: CaptureScanTemporaryFileLease?, playback: PlaybackArtifact?
                for result in results {
                    switch result {
                    case .frames(let value): frames = value
                    case .audio(let value): audio = value
                    case .playback(let value): playback = value
                    }
                }
                try Task.checkCancellation()
                guard let frames, let playback else { throw CocoaError(.fileReadUnknown) }
                return Artifacts(frames: frames, audio: audio, playback: playback)
            } catch {
                group.cancelAll()
                // nextResult is nonthrowing, so one cancelled child cannot hide
                // a later successful child carrying a file that still needs us.
                while let late = await group.nextResult() {
                    if case .success(let result) = late { results.append(result) }
                }
                for result in results { await result.discard() }
                throw error
            }
        }
    }

    nonisolated private static func optionalAudio(
        videoURL: URL,
        dependencies: Dependencies
    ) async -> CaptureScanTemporaryFileLease? {
        try? await withTimeout(
            seconds: audioExtractionTimeout,
            message: "Extracting video audio timed out.",
            operation: { await dependencies.audio(videoURL) },
            discard: { await $0?.discardReportingFailure() }
        )
    }

    nonisolated private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        message: String,
        operation: @Sendable @escaping () async throws -> T,
        discard: @Sendable @escaping (T) async -> Void = { _ in }
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
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

            do {
                guard let result = try await group.next() else { throw CancellationError() }
                group.cancelAll()
                do { try Task.checkCancellation() } catch { await discard(result); throw error }
                return result
            } catch {
                group.cancelAll()
                // A timeout requests cancellation; it does not prove that the
                // worker stopped or that its late resource has been discarded.
                while let late = await group.nextResult() {
                    if case .success(let result) = late { await discard(result) }
                }
                throw error
            }
        }
    }

    #if DEBUG
    nonisolated static func qualifyLeaseTimeout(
        seconds: TimeInterval, operation: @Sendable @escaping () async throws -> CaptureScanTemporaryFileLease
    ) async throws -> CaptureScanTemporaryFileLease {
        try await withTimeout(seconds: seconds, message: "Qualification timeout", operation: operation,
            discard: { await $0.discardReportingFailure() })
    }
    #endif

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
                width: ImagePreparationPolicy.displayMaxDimension,
                height: ImagePreparationPolicy.displayMaxDimension
            )

            let sampleOffsets = CaptureScanVideoFrameSamplingPolicy
                .sampleOffsets(
                    duration: request.duration,
                    sampleCount: frameSampleCount
                )
            let times = sampleOffsets.map {
                CMTime(seconds: $0, preferredTimescale: 600)
            }
            let inferenceMaxSize = ImagePreparationPolicy.inferenceMaxDimension(
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
    ) async throws -> PlaybackArtifact {
        let originalSize = try fileSize(at: videoURL)
        let exportStart = CFAbsoluteTimeGetCurrent()
        var generatedLease: CaptureScanTemporaryFileLease?

        do {
            let compressedLease = try await withTimeout(
                seconds: playbackPreparationTimeout,
                message: "Preparing video playback timed out.",
                operation: { try await compressVideoForPlayback(videoURL: videoURL) },
                discard: { await $0.discardReportingFailure() }
            )
            generatedLease = compressedLease
            let compressedURL = compressedLease.fileURL
            let compressedSize = try fileSize(at: compressedURL)
            guard compressedSize > 0,
                  compressedSize <= ScanMediaPayloadPolicy.maxSavedVideoBytes else {
                try await compressedLease.discard()
                let sizeError = NSError(
                    domain: "CaptureWorkspaceViewModel",
                    code: -26,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Compressed video exceeds the upload budget."
                    ]
                )
                guard originalSize <= ScanMediaPayloadPolicy.maxSavedVideoBytes else {
                    throw sizeError
                }
                MerianLog.hardware.warning(
                    """
                    Video compression produced unusable output; staging original upload-safe clip. \
                    originalBytes=\(originalSize, privacy: .public), \
                    compressedBytes=\(compressedSize, privacy: .public)
                    """
                )
                return PlaybackArtifact(playback: PreparedCaptureScanVideoPlayback(
                    fileURL: videoURL,
                    isCompressed: false,
                    originalBytes: originalSize,
                    playbackBytes: originalSize,
                    preparationDuration:
                        CFAbsoluteTimeGetCurrent() - exportStart
                ))
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
               originalSize <= ScanMediaPayloadPolicy.maxSavedVideoBytes {
                try await compressedLease.discard()
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
                return PlaybackArtifact(playback: PreparedCaptureScanVideoPlayback(
                    fileURL: videoURL,
                    isCompressed: false,
                    originalBytes: originalSize,
                    playbackBytes: originalSize,
                    preparationDuration:
                        CFAbsoluteTimeGetCurrent() - exportStart
                ))
            }
            try Task.checkCancellation()
            return PlaybackArtifact(playback: PreparedCaptureScanVideoPlayback(
                fileURL: compressedURL,
                isCompressed: true,
                originalBytes: originalSize,
                playbackBytes: compressedSize,
                preparationDuration:
                    CFAbsoluteTimeGetCurrent() - exportStart
            ), lease: compressedLease)
        } catch is CancellationError {
            await generatedLease?.discardReportingFailure()
            throw CancellationError()
        } catch {
            await generatedLease?.discardReportingFailure()
            MerianLog.hardware.error(
                "Video compression failed: \(error, privacy: .private)"
            )
            guard originalSize <= ScanMediaPayloadPolicy.maxSavedVideoBytes else {
                MerianLog.hardware.error(
                    """
                    Video staging failed because neither compression nor the original clip fit the upload budget. \
                    originalBytes=\(originalSize, privacy: .public), \
                    maxBytes=\(ScanMediaPayloadPolicy.maxSavedVideoBytes, privacy: .public)
                    """
                )
                throw error
            }
            MerianLog.hardware.warning(
                """
                Video compression unavailable; staging original upload-safe clip. \
                originalBytes=\(originalSize, privacy: .public), \
                maxBytes=\(ScanMediaPayloadPolicy.maxSavedVideoBytes, privacy: .public), \
                source=original, \
                fallback=true
                """
            )
            return PlaybackArtifact(playback: PreparedCaptureScanVideoPlayback(
                fileURL: videoURL,
                isCompressed: false,
                originalBytes: originalSize,
                playbackBytes: originalSize,
                preparationDuration:
                    CFAbsoluteTimeGetCurrent() - exportStart
            ))
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

        let presetName = ScanMediaPayloadPolicy.videoPlaybackLongEdgeMaxPixels <= 1280
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
            ScanMediaPayloadPolicy.videoPlaybackExpectedMaxBytes
        )

        do {
            try await CaptureScanAssetExportSessionFinisher(exportSession).export(to: outputURL)
            try Task.checkCancellation()
            return outputLease
        } catch {
            await outputLease.discardReportingFailure()
            throw error
        }
    }

    nonisolated private static func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }
}
