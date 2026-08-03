import AVFoundation
import SwiftUI

private struct PreparedCameraCapture: Sendable {
    let inferenceData: Data
    let displayData: Data
    let previewCGImage: SendableCGImage
    let focusRegion: NormalizedImageFocusRegion?

    init(
        inferenceData: Data,
        displayData: Data,
        previewCGImage: SendableCGImage,
        focusRegion: NormalizedImageFocusRegion? = nil
    ) {
        self.inferenceData = inferenceData
        self.displayData = displayData
        self.previewCGImage = previewCGImage
        self.focusRegion = focusRegion
    }
}

private struct PreparedVideoPlaybackClip: Sendable {
    let fileURL: URL
    let isCompressed: Bool
    let originalBytes: Int
    let playbackBytes: Int
    let preparationDuration: TimeInterval

    var sourceDescription: String {
        isCompressed ? "compressed" : "original"
    }

    var compressionRatio: Double {
        guard originalBytes > 0 else { return 1.0 }
        return Double(playbackBytes) / Double(originalBytes)
    }
}

private actor AssetWriterFinisher {
    private let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }

    func finish() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writer.finishWriting { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    Task {
                        await self.resolveFinish(continuation: continuation)
                    }
                }
            }
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    private func resolveFinish(continuation: CheckedContinuation<Void, Error>) {
        switch writer.status {
        case .completed:
            continuation.resume()
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        default:
            continuation.resume(throwing: writer.error ?? NSError(
                domain: "CaptureWorkspaceViewModel",
                code: -21,
                userInfo: [NSLocalizedDescriptionKey: "Unable to finish writing media."]
            ))
        }
    }

    private func cancel() {
        writer.cancelWriting()
    }
}

private actor AssetExportSessionFinisher {
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
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    Task {
                        await self.resolveExport(continuation: continuation)
                    }
                }
            }
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    private func resolveExport(continuation: CheckedContinuation<Void, Error>) {
        switch session.status {
        case .completed:
            continuation.resume()
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        default:
            continuation.resume(throwing: session.error ?? NSError(
                domain: "CaptureWorkspaceViewModel",
                code: -27,
                userInfo: [NSLocalizedDescriptionKey: "Unable to export compressed video."]
            ))
        }
    }

    private func cancel() {
        session.cancelExport()
    }
}

extension CaptureWorkspaceViewModel {
    static let videoMaxDuration: TimeInterval = 5
    nonisolated private static let videoInferenceFrameSampleCount = 5
    nonisolated private static let videoFramePreparationTimeout: TimeInterval = 8
    nonisolated private static let videoAudioExtractionTimeout: TimeInterval = 5
    nonisolated private static let videoPlaybackPreparationTimeout: TimeInterval = 10
    nonisolated private static let videoStagingFailureMessage = "Video couldn't be staged. Please try recording again."

    nonisolated private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        message: String,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            defer { group.cancelAll() }

            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(seconds, 0.1) * 1_000_000_000))
                throw NSError(
                    domain: "CaptureWorkspaceViewModel",
                    code: -29,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }

    nonisolated private static func prepareCameraCapture(
        captureData: Data,
        composingCenter: CGFloat,
        isProActive: Bool
    ) async throws -> PreparedCameraCapture? {
        try await DetachedWork.value(
            priority: .userInitiated,
            category: .imagePreparation
        ) {
            let inferencePrepared: (data: Data, preview: SendableCGImage)? = autoreleasepool {
                let inferenceMaxSize = MerianConfig.inferenceImageMaxSize(isProActive: isProActive)
                guard let safeCGImage = ImageDownsampler.downsample(data: captureData, maxSize: inferenceMaxSize) else {
                    return nil
                }

                let croppedCGImage = ImageCropProcessor.squareCrop(
                    safeCGImage,
                    verticalCenterFraction: composingCenter
                ) ?? safeCGImage

                guard let finalSafeData = ImageCropProcessor.encode(croppedCGImage),
                      !finalSafeData.isEmpty else {
                    return nil
                }

                return (finalSafeData, SendableCGImage(image: safeCGImage))
            }
            guard let inferencePrepared else { return nil }

            async let focusRegion = ImageFocusRegionDetector.detect(in: inferencePrepared.data)

            let displaySafeData: Data = autoreleasepool {
                    guard let displayCGImage = ImageDownsampler.downsample(
                        data: captureData,
                        maxSize: MerianConfig.displayImageMaxSize
                    ) else {
                        return inferencePrepared.data
                    }
                    let croppedDisplayCGImage = ImageCropProcessor.squareCrop(
                        displayCGImage,
                        verticalCenterFraction: composingCenter
                    ) ?? displayCGImage
                    return ImageCropProcessor.encode(croppedDisplayCGImage) ?? inferencePrepared.data
            }

            return await PreparedCameraCapture(
                inferenceData: inferencePrepared.data,
                displayData: displaySafeData,
                previewCGImage: inferencePrepared.preview,
                focusRegion: focusRegion
            )
        }
    }

    nonisolated private static func prepareVideoFrames(
        videoURL: URL,
        duration: TimeInterval,
        composingCenter: CGFloat,
        isProActive: Bool
    ) async throws -> [PreparedCameraCapture] {
        let frameSampleCount = Self.videoInferenceFrameSampleCount
        return try await DetachedWork.value(
            priority: .userInitiated,
            category: .imagePreparation
        ) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(
                width: MerianConfig.displayImageMaxSize,
                height: MerianConfig.displayImageMaxSize
            )

            let resolvedDuration = max(duration, 0.1)
            let normalizedSamplePositions: [Double]
            if frameSampleCount <= 1 {
                normalizedSamplePositions = [0.5]
            } else {
                let step = 0.8 / Double(frameSampleCount - 1)
                normalizedSamplePositions = (0..<frameSampleCount).map { 0.1 + Double($0) * step }
            }
            let sampleOffsets = normalizedSamplePositions.map {
                min(max(resolvedDuration * $0, 0.05), max(resolvedDuration - 0.05, 0.05))
            }
            let times = sampleOffsets.map { CMTime(seconds: $0, preferredTimescale: 600) }
            let inferenceMaxSize = MerianConfig.inferenceImageMaxSize(isProActive: isProActive)

            var preparedFrames: [PreparedCameraCapture] = []
            preparedFrames.reserveCapacity(times.count)

            for time in times {
                autoreleasepool {
                    guard let frame = try? generator.copyCGImage(at: time, actualTime: nil) else {
                        MerianLog.hardware.warning(
                            "Video frame sampling skipped frame at \(time.seconds, privacy: .public)s."
                        )
                        return
                    }
                    let displayFrame = ImageCropProcessor.squareCrop(
                        frame,
                        verticalCenterFraction: composingCenter
                    ) ?? frame
                    guard let displayData = ImageCropProcessor.encode(displayFrame),
                          !displayData.isEmpty else {
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
                        verticalCenterFraction: composingCenter
                    ) ?? inferenceFrame
                    guard let inferenceData = ImageCropProcessor.encode(inferenceCropped),
                          !inferenceData.isEmpty else {
                        MerianLog.hardware.warning(
                            "Video frame sampling skipped frame because inference encoding failed."
                        )
                        return
                    }

                    preparedFrames.append(PreparedCameraCapture(
                        inferenceData: inferenceData,
                        displayData: displayData,
                        previewCGImage: SendableCGImage(image: displayFrame)
                    ))
                }
            }

            MerianLog.hardware.debug(
                "Video frame sampling prepared \(preparedFrames.count, privacy: .public)/\(times.count, privacy: .public) frames."
            )
            return preparedFrames
        }
    }

    nonisolated private static func prepareVideoPlaybackClip(
        videoURL: URL
    ) async throws -> PreparedVideoPlaybackClip {
        let originalSize = try fileSize(at: videoURL)
        let exportStart = CFAbsoluteTimeGetCurrent()

        do {
            let compressedURL = try await withTimeout(
                seconds: Self.videoPlaybackPreparationTimeout,
                message: "Preparing video playback timed out."
            ) {
                try await compressVideoForPlayback(videoURL: videoURL)
            }
            let compressedSize = try fileSize(at: compressedURL)
            guard compressedSize > 0, compressedSize <= MerianConfig.videoPayloadMaxBytes else {
                try? FileManager.default.removeItem(at: compressedURL)
                let sizeError = NSError(
                    domain: "CaptureWorkspaceViewModel",
                    code: -26,
                    userInfo: [NSLocalizedDescriptionKey: "Compressed video exceeds the upload budget."]
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
                return PreparedVideoPlaybackClip(
                    fileURL: videoURL,
                    isCompressed: false,
                    originalBytes: originalSize,
                    playbackBytes: originalSize,
                    preparationDuration: CFAbsoluteTimeGetCurrent() - exportStart
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
            if compressedSize >= originalSize, originalSize <= MerianConfig.videoPayloadMaxBytes {
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
                return PreparedVideoPlaybackClip(
                    fileURL: videoURL,
                    isCompressed: false,
                    originalBytes: originalSize,
                    playbackBytes: originalSize,
                    preparationDuration: CFAbsoluteTimeGetCurrent() - exportStart
                )
            }
            return PreparedVideoPlaybackClip(
                fileURL: compressedURL,
                isCompressed: true,
                originalBytes: originalSize,
                playbackBytes: compressedSize,
                preparationDuration: CFAbsoluteTimeGetCurrent() - exportStart
            )
        } catch {
            MerianLog.hardware.error("Video compression failed: \(error, privacy: .private)")
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
            return PreparedVideoPlaybackClip(
                fileURL: videoURL,
                isCompressed: false,
                originalBytes: originalSize,
                playbackBytes: originalSize,
                preparationDuration: CFAbsoluteTimeGetCurrent() - exportStart
            )
        }
    }

    nonisolated private static func compressVideoForPlayback(videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw NSError(
                domain: "CaptureWorkspaceViewModel",
                code: -27,
                userInfo: [NSLocalizedDescriptionKey: "Recorded video has no video track."]
            )
        }

        let presetName = MerianConfig.videoPlaybackLongEdgeMaxPixels <= 1280
            ? AVAssetExportPreset1280x720
            : AVAssetExportPresetHighestQuality
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw NSError(
                domain: "CaptureWorkspaceViewModel",
                code: -28,
                userInfo: [NSLocalizedDescriptionKey: "Unable to prepare compressed video export."]
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString.lowercased())_video_playback.mp4")
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.fileLengthLimit = Int64(MerianConfig.videoPlaybackExpectedMaxBytes)

        do {
            try await AssetExportSessionFinisher(exportSession).export(to: outputURL)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    nonisolated private static func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    nonisolated private static func isEdgeCompatibleWAV(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count >= 44 else {
            return false
        }

        let bytes = [UInt8](data)
        func hasTag(_ tag: String, at offset: Int) -> Bool {
            let tagBytes = Array(tag.utf8)
            guard tagBytes.count == 4, offset + 4 <= bytes.count else {
                return false
            }
            return bytes[offset] == tagBytes[0]
                && bytes[offset + 1] == tagBytes[1]
                && bytes[offset + 2] == tagBytes[2]
                && bytes[offset + 3] == tagBytes[3]
        }
        func uint16LE(at offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        func uint32LE(at offset: Int) -> UInt32 {
            UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        }

        guard hasTag("RIFF", at: 0), hasTag("WAVE", at: 8) else {
            return false
        }

        var offset = 12
        var audioFormat: UInt16 = 0
        var channelCount: UInt16 = 0
        var sampleRate: UInt32 = 0
        var bitsPerSample: UInt16 = 0
        var dataLength: UInt32 = 0

        while offset + 8 <= bytes.count {
            let chunkSize = Int(uint32LE(at: offset + 4))
            guard chunkSize >= 0, offset + 8 + chunkSize <= bytes.count else {
                return false
            }
            if hasTag("fmt ", at: offset), chunkSize >= 16 {
                audioFormat = uint16LE(at: offset + 8)
                channelCount = uint16LE(at: offset + 10)
                sampleRate = uint32LE(at: offset + 12)
                bitsPerSample = uint16LE(at: offset + 22)
            } else if hasTag("data", at: offset) {
                dataLength = UInt32(chunkSize)
                break
            }
            offset += 8 + chunkSize + (chunkSize.isMultiple(of: 2) ? 0 : 1)
        }

        let supportedFormat = (audioFormat == 1 && bitsPerSample == 16)
            || (audioFormat == 3 && bitsPerSample == 32)
        return supportedFormat
            && channelCount > 0
            && sampleRate > 0
            && dataLength > 0
    }

    nonisolated private static func extractVideoAudioTrack(videoURL: URL) async -> String? {
        do {
            return try await DetachedWork.value(
                priority: .utility,
                category: .backgroundDatabaseMutation
            ) {
                let asset = AVURLAsset(url: videoURL)
                guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                    return nil
                }

                let outputName = "\(UUID().uuidString.lowercased())-video-audio.wav"
                let outputURL = URL.documentsDirectory.appendingPathComponent(outputName)

                do {
                    if FileManager.default.fileExists(atPath: outputURL.path) {
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

                    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
                    let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                    writerInput.expectsMediaDataInRealTime = false
                    guard writer.canAdd(writerInput) else { return nil }
                    writer.add(writerInput)

                    guard reader.startReading() else {
                        throw reader.error ?? NSError(
                            domain: "CaptureWorkspaceViewModel",
                            code: -22,
                            userInfo: [NSLocalizedDescriptionKey: "Unable to read video audio."]
                        )
                    }
                    guard writer.startWriting() else {
                        throw writer.error ?? NSError(
                            domain: "CaptureWorkspaceViewModel",
                            code: -23,
                            userInfo: [NSLocalizedDescriptionKey: "Unable to write video audio."]
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
                            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else {
                                reachedEndOfStream = true
                                return nil
                            }
                            defer { _ = CMSampleBufferInvalidate(sampleBuffer) }

                            guard writerInput.append(sampleBuffer) else {
                                reader.cancelReading()
                                return writer.error ?? NSError(
                                    domain: "CaptureWorkspaceViewModel",
                                    code: -24,
                                    userInfo: [NSLocalizedDescriptionKey: "Unable to append video audio."]
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
                            userInfo: [NSLocalizedDescriptionKey: "Unable to finish reading video audio."]
                        )
                    }

                    try await AssetWriterFinisher(writer).finish()

                    let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                    guard (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
                        try? FileManager.default.removeItem(at: outputURL)
                        return nil
                    }
                    guard isEdgeCompatibleWAV(at: outputURL) else {
                        try? FileManager.default.removeItem(at: outputURL)
                        MerianLog.hardware.warning(
                            "Video audio extraction produced a WAV variant the edge parser cannot use; continuing without video audio."
                        )
                        return nil
                    }

                    return outputName
                } catch {
                    try? FileManager.default.removeItem(at: outputURL)
                    MerianLog.hardware.error("Video audio extraction failed: \(error, privacy: .private)")
                    return nil
                }
            }
        } catch {
            MerianLog.hardware.error("Video audio extraction task failed: \(error, privacy: .private)")
            return nil
        }
    }
    
    // MARK: - UI Coordination
    
    func triggerFlash() {
        flashOpacity = 1.0
        withAnimation(.easeOut(duration: 0.15)) {
            flashOpacity = 0.0
        }
    }
    
    func handleFocusTap(devicePoint: CGPoint) {
        diContainer.cameraManager.setFocusPoint(devicePoint)
        diContainer.hapticManager.triggerSelectionPulse()
    }
    
    // MARK: - Shutter Pipeline
    
    func executeCapture(emitHaptic: Bool = true) {
        // 1. Concurrency Guards
        // Prevent accidental hardware captures while a modal, sheet, or crop view is actively presented
        guard activeSheet == nil,
              !isCapturing,
              hasAvailableStagedCaptureSlot,
              imageToCrop == nil else { return }
              
        isCapturing = true
              
        // 2. Authorization Hooks
        if diContainer.usageManager.canPerformScan(isProActive: diContainer.revenueCatManager.canStartProScan) {
            if emitHaptic {
                // Instant tactile UI response mirroring the Apple Camera app.
                diContainer.hapticManager.triggerHeavyImpact(intensity: 1.0, source: "capture.photo.hardware")
            }
            
            triggerFlash()
            
            Task {
                do {
                    // 3. Hardware Interfacing
                    // Securing the optical frame and geographical context precisely at shutter click
                    async let shutterLocation = diContainer.environmentContextManager.requestCurrentLocation()
                    let composingCenter = composingZoneVerticalCenter
                    let captureData = try await diContainer.cameraManager.captureImage()
                    let resolvedShutterLocation = await shutterLocation
                    let instantLocation = resolvedShutterLocation ?? diContainer.environmentContextManager.lastKnownLocation
                    
                    // Actively push the original 12MP buffer down natively into the user's Camera Roll securely without blocking UI sweeps natively
                    Task {
                        await AppDIContainer.shared.photoLibraryManager.saveImageToLibrary(imageData: captureData, location: instantLocation)
                    }
                    // 4. Detached Memory Pipeline
                    // Downsamples the 12MP buffer globally off the UI thread to massively drop the footprint
                    // Instantly executes native `generateAutoCenterCrop` natively isolating UIImage and CGImage pointers 
                    // cleanly inside the background securely, exporting solely safe raw `.Data` out bypassing JetSam limits globally
                    
                    let preparedCapture = try await Self.prepareCameraCapture(
                        captureData: captureData,
                        composingCenter: composingCenter,
                        isProActive: diContainer.revenueCatManager.canStartProScan
                    )

                    if let preparedCapture {
                        // 5. Environmental Pre-Fetching
                        // Maps historical location caching before pushing to identity pipeline
                        let task = Task {
                            return await AppDIContainer.shared.environmentContextManager.fetchDeferredContext(preLockedLocation: instantLocation)
                        }

                        // 6. MainActor Routing
                        // Injecting the raw safe bytes bounds back strictly on the UI thread
                        await MainActor.run {
                            self.preFetchTask = task
                            let backgroundRawImage = UIImage(cgImage: preparedCapture.previewCGImage.image, scale: 1.0, orientation: .up)
                            let identifiable = IdentifiableImage(image: backgroundRawImage, environmentContext: nil, isFromGallery: false)
                            self.stagedCapture.images.append(StagedImage(
                                compressedData: preparedCapture.inferenceData,
                                displayData: preparedCapture.displayData,
                                uiImage: backgroundRawImage,
                                original: identifiable,
                                focusRegion: preparedCapture.focusRegion
                            ))
                        }
                    }
                } catch {
                    MerianLog.hardware.error("Hardware shutter failure: \(error, privacy: .private)")
                }
                
                await MainActor.run {
                    self.isCapturing = false
                }
            }
        } else {
            AppTelemetry.trackPaywallImpression()
            self.activeSheet = .paywall
            self.isCapturing = false
        }
    }

    func startVideoCapture() {
        guard activeSheet == nil,
              !isCapturing,
              !isVideoRecording,
              hasAvailableStagedCaptureSlot,
              imageToCrop == nil else { return }
        guard diContainer.revenueCatManager.canStartProScan else { return }

        isCapturing = true
        videoRecordingProgress = 0

        videoRecordingTask?.cancel()
        videoRecordingTask = Task { [weak self] in
            guard let self else { return }
            var recordedFileURL: URL?
            var cameraRollSaveTask: Task<Void, Never>?
            defer {
                self.finishVideoCaptureUI(resetProgress: true)
            }

            do {
                async let shutterLocation = diContainer.environmentContextManager.requestCurrentLocation()
                let composingCenter = composingZoneVerticalCenter
                let recording = try await diContainer.cameraManager.recordVideo(
                    maxDuration: Self.videoMaxDuration,
                    onStarted: { [weak self] in
                        guard let self, self.isCapturing else { return }
                        self.isVideoRecording = true
                        self.videoRecordingProgress = 0
                        self.diContainer.hapticManager.triggerHeavyImpact(
                            intensity: 1.0,
                            source: CaptureButtonHapticSource.videoStart.rawValue
                        )
                        self.startVideoRecordingProgressTimer()
                    }
                )
                recordedFileURL = recording.fileURL
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: recording.fileURL)
                    throw CancellationError()
                }
                await MainActor.run {
                    self.diContainer.hapticManager.triggerHeavyImpact(
                        intensity: 1.0,
                        source: "capture.video.completed"
                    )
                }
                let resolvedShutterLocation = await shutterLocation
                let instantLocation = resolvedShutterLocation ?? diContainer.environmentContextManager.lastKnownLocation
                cameraRollSaveTask = Task { @MainActor in
                    await self.diContainer.photoLibraryManager.saveVideoToLibrary(
                        fileURL: recording.fileURL,
                        location: instantLocation
                    )
                }
                let isProActive = diContainer.revenueCatManager.canStartProScan
                let preparedFrames = try await Self.withTimeout(
                    seconds: Self.videoFramePreparationTimeout,
                    message: "Preparing video frames timed out."
                ) {
                    try await Self.prepareVideoFrames(
                        videoURL: recording.fileURL,
                        duration: recording.duration,
                        composingCenter: composingCenter,
                        isProActive: isProActive
                    )
                }
                guard !preparedFrames.isEmpty else {
                    throw NSError(
                        domain: "CaptureWorkspaceViewModel",
                        code: -20,
                        userInfo: [NSLocalizedDescriptionKey: "Unable to sample frames from the recorded video."]
                    )
                }
                let extractedAudioFilePath = try? await Self.withTimeout(
                    seconds: Self.videoAudioExtractionTimeout,
                    message: "Extracting video audio timed out."
                ) {
                    await Self.extractVideoAudioTrack(videoURL: recording.fileURL)
                }
                let playbackClip = try await Self.prepareVideoPlaybackClip(videoURL: recording.fileURL)

                let task = Task {
                    await AppDIContainer.shared.environmentContextManager.fetchDeferredContext(preLockedLocation: instantLocation)
                }

                await MainActor.run {
                    self.preFetchTask = task
                    let stagedFrames = preparedFrames.map { frame in
                        let previewImage = UIImage(cgImage: frame.previewCGImage.image, scale: 1.0, orientation: .up)
                        return StagedImage(
                            compressedData: frame.inferenceData,
                            displayData: frame.displayData,
                            uiImage: previewImage,
                            original: IdentifiableImage(image: previewImage, environmentContext: nil, isFromGallery: false)
                        )
                    }
                    self.stagedCapture.videos.append(StagedVideo(
                        filePath: playbackClip.fileURL.path,
                        sampledImages: stagedFrames,
                        audioFilePath: extractedAudioFilePath
                    ))
                    MerianLog.hardware.debug(
                        """
                        Video staged: frames=\(stagedFrames.count, privacy: .public), \
                        file=\(playbackClip.fileURL.lastPathComponent, privacy: .public), \
                        source=\(playbackClip.sourceDescription, privacy: .public), \
                        originalBytes=\(playbackClip.originalBytes, privacy: .public), \
                        playbackBytes=\(playbackClip.playbackBytes, privacy: .public), \
                        compressionRatio=\(String(format: "%.3f", playbackClip.compressionRatio), privacy: .public), \
                        preparationDuration=\(String(format: "%.3f", playbackClip.preparationDuration), privacy: .public)s, \
                        fallback=\(!playbackClip.isCompressed, privacy: .public).
                        """
                    )
                    AppDIContainer.shared.hapticManager.triggerSuccessPulse()
                }
                await cameraRollSaveTask?.value
                if playbackClip.isCompressed {
                    try? FileManager.default.removeItem(at: recording.fileURL)
                }
            } catch is CancellationError {
                await cameraRollSaveTask?.value
                if let recordedFileURL {
                    try? FileManager.default.removeItem(at: recordedFileURL)
                }
                diContainer.cameraManager.cancelVideoRecording()
            } catch {
                await cameraRollSaveTask?.value
                if let recordedFileURL {
                    try? FileManager.default.removeItem(at: recordedFileURL)
                }
                MerianLog.hardware.error("Video shutter failure: \(error, privacy: .private)")
                await MainActor.run {
                    self.offlineToastMessage = Self.videoStagingFailureMessage
                    AppDIContainer.shared.hapticManager.triggerErrorThump()
                }
            }
        }
    }

    func stopVideoCapture() {
        guard isVideoRecording else { return }
        diContainer.cameraManager.stopVideoRecording()
    }

    func cancelVideoCapture() {
        guard isVideoRecording || isCapturing else { return }
        videoRecordingTask?.cancel()
        videoRecordingTask = nil
        diContainer.cameraManager.cancelVideoRecording()
        finishVideoCaptureUI(resetProgress: true)
    }

    private func startVideoRecordingProgressTimer() {
        videoRecordingProgressTask?.cancel()
        videoRecordingProgressTask = Task { @MainActor in
            let tickNanoseconds: UInt64 = 50_000_000
            let tickDuration = 0.05
            var elapsed: TimeInterval = 0

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickNanoseconds)
                guard !Task.isCancelled else { return }
                elapsed += tickDuration
                videoRecordingProgress = min(1, elapsed / Self.videoMaxDuration)

                if elapsed >= Self.videoMaxDuration {
                    return
                }
            }
        }
    }

    private func stopVideoRecordingProgressTimer(reset: Bool) {
        videoRecordingProgressTask?.cancel()
        videoRecordingProgressTask = nil
        if reset {
            videoRecordingProgress = 0
        }
    }

    private func finishVideoCaptureUI(resetProgress: Bool) {
        stopVideoRecordingProgressTimer(reset: resetProgress)
        isCapturing = false
        isVideoRecording = false
        videoRecordingTask = nil
    }
}
