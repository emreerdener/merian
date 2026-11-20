#if DEBUG
import AVFoundation
import Foundation
import SwiftData
import UIKit

/// Small synthetic inputs for ordinary initial-submission UI qualification.
/// These are not camera, codec-limit, provider or resource fixtures.
@MainActor enum InitialMediaHistoryUIInput {
    static let note = ObservationContext(freeText: "  Calling e\u{301} 🐾\n")

    static func photo() throws -> StagedImage {
        guard UITestSeedCoordinator.initialMediaHistoryEnabled else { throw MerianError.invalidResponse }
        // Prepared-input seam only: production camera/codec preparation is not
        // qualified by these bounded synthetic JPEG representations.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format)
        let image = renderer.image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let display = renderer.image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        guard let inferenceBytes = image.jpegData(compressionQuality: 0.8),
              let displayBytes = display.jpegData(compressionQuality: 0.8) else { throw MerianError.invalidResponse }
        return StagedImage(compressedData: inferenceBytes, displayData: displayBytes,
            uiImage: display, original: IdentifiableImage(image: image))
    }

    static func audio(in root: URL) async throws -> URL {
        guard UITestSeedCoordinator.initialMediaHistoryEnabled else { throw MerianError.invalidResponse }
        let input = root.appendingPathComponent("input.wav")
        try UITestSeedCoordinator.queuedAudioHandoffWAVData().write(to: input, options: .atomic)
        let bytes = try await CaptureAudioInputPreparer(directory: root.appendingPathComponent("conversion"))
            .prepare(input)
        let output = root.appendingPathComponent("prepared.wav")
        try bytes.write(to: output, options: .atomic)
        return output
    }

    static func video(in root: URL, progress: (String) -> Void) async throws -> URL {
        guard UITestSeedCoordinator.initialMediaHistoryEnabled else { throw MerianError.invalidResponse }
        let silent = root.appendingPathComponent("silent.mp4"), audio = root.appendingPathComponent("tone.m4a")
        let output = root.appendingPathComponent("input.mp4")
        progress("video input: silent encoder")
        try await writeSilentVideo(silent)
        progress("video input: audio write")
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: audio, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000])
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 48_000),
                  let samples = buffer.floatChannelData else { throw MerianError.invalidResponse }
            buffer.frameLength = 48_000
            for frame in 0..<48_000 { samples[0][frame] = Float(sin(2 * .pi * 880 * Double(frame) / 48_000) * 0.2) }
            try file.write(from: buffer)
        }
        progress("video input: audio write completed")
        // Reproduce the original temporary-asset expression using these same
        // synthetic inputs. Preserve the observation separately from success.
        try await recordTemporaryAssetProbe(silent: silent, audio: audio, root: root)
        let composition = AVMutableComposition()
        let assets = [AVURLAsset(url: silent), AVURLAsset(url: audio)]
        // AVAssetTrack.asset is weak. Keep both source assets alive through
        // insertion and the final awaited export, independently of ARC timing.
        defer { withExtendedLifetime(assets) {} }
        for (asset, media) in zip(assets, [AVMediaType.video, .audio]) {
            progress(media == .video ? "video input: loading video track" : "video input: loading audio track")
            let tracks = try await asset.loadTracks(withMediaType: media)
            guard tracks.count == 1, let source = tracks.first, source.asset === asset,
                  let track = composition.addMutableTrack(withMediaType: media, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw MerianError.invalidResponse
            }
            progress(media == .video ? "video input: inserting video track" : "video input: inserting audio track")
            try track.insertTimeRange(.init(start: .zero, duration: CMTime(value: 1, timescale: 1)), of: source, at: .zero)
        }
        progress("video input: constructing exporter")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw MerianError.invalidResponse
        }
        progress("video input: exporting")
        if #available(iOS 18.0, *) {
            try await exporter.export(to: output, as: .mp4)
        } else {
            exporter.outputURL = output; exporter.outputFileType = .mp4
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in exporter.exportAsynchronously { continuation.resume() } }
            } onCancel: { exporter.cancelExport() }
            guard exporter.status == .completed else { throw MerianError.invalidResponse }
        }
        try Task.checkCancellation()
        progress("video input: export completed")
        return output
    }

    private static func recordTemporaryAssetProbe(silent: URL, audio: URL, root: URL) async throws {
        let composition = AVMutableComposition()
        var stage = "video load", parents: [Bool] = [], outcome = "insertion completed", domain = "none", code = 0
        do {
            for (url, media) in [(silent, AVMediaType.video), (audio, .audio)] {
                stage = media == .video ? "video load" : "audio load"
                guard let source = try await AVURLAsset(url: url).loadTracks(withMediaType: media).first,
                      let track = composition.addMutableTrack(withMediaType: media, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw MerianError.invalidResponse
                }
                parents.append(source.asset != nil)
                stage = media == .video ? "video insertion" : "audio insertion"
                try track.insertTimeRange(.init(start: .zero, duration: CMTime(value: 1, timescale: 1)), of: source, at: .zero)
            }
        } catch {
            outcome = "threw"
            let error = error as NSError
            domain = [AVFoundationErrorDomain, NSOSStatusErrorDomain, NSCocoaErrorDomain].contains(error.domain) ? error.domain : "other"
            code = error.code
        }
        let file = root.appendingPathComponent("temporary-asset-probe.json")
        guard file.resolvingSymlinksInPath() == file.standardizedFileURL else { throw MerianError.invalidResponse }
        let data = try JSONSerialization.data(withJSONObject: ["stage": stage, "outcome": outcome,
            "sourceAssetPresent": parents, "errorDomain": domain, "errorCode": code] as [String: Any], options: [.sortedKeys])
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private static func writeSilentVideo(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        guard writer.canAdd(input) else { throw MerianError.invalidResponse }
        writer.add(input)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        guard writer.startWriting() else { throw MerianError.invalidResponse }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess,
              let pixels = buffer else { throw MerianError.invalidResponse }
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) { memset(base, 0, CVPixelBufferGetDataSize(pixels)) }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        for frame in 0..<30 {
            let deadline = ContinuousClock.now + .seconds(5)
            while !input.isReadyForMoreMediaData && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
            try Task.checkCancellation()
            guard input.isReadyForMoreMediaData,
                  adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw MerianError.invalidResponse }
        }
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1)); input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw MerianError.invalidResponse }
    }

    static func workspace(_ di: AppDIContainer) -> CaptureWorkspaceViewModel {
        let base = CaptureWorkspaceDependencies.live(diContainer: di)
        let submission = CaptureSubmissionDependencies(
            context: .init(lastKnownLocation: { nil }, fetchDeferredContext: { _ in EnvironmentContext(location: nil) }),
            admission: .init(isOnline: { false }, canStartLocally: { _ in true }, preview: { _ in .unavailable }),
            deferredContext: .init(persistLocally: { _, _ in }, endpoint: .init(update: { _, _ in }), waitBeforeRetry: {}))
        return CaptureWorkspaceViewModel(diContainer: di, dependencies: .init(
            scan: base.scan, submission: submission, controls: base.controls,
            navigation: base.navigation, stagingToolbar: base.stagingToolbar,
            prepareImage: { _ in nil }, prepareHistoricalAudio: { _ in nil },
            externalImageImports: base.externalImageImports, downloadRefinementImage: { _ in nil },
            prewarmConnections: {}, sharedExplorePostId: { _ in nil }, captureGoalAccountId: { _ in nil },
            requestNotificationAuthorization: { _ in },
            feedback: .init(selection: { _ in }, sheet: { _ in }, medium: {}, error: {})), prewarmHeadersOnInit: false)
    }
}
#endif
