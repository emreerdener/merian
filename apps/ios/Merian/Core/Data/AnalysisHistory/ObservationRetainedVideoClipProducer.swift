import AVFoundation
import Foundation
import os

enum ObservationRetainedVideoClipError: Error {
    case busy, invalidSource, unsupportedProfile, failed, timedOut, oversized
    case readerFailure(Int), writerFailure(Int), incompleteStream
}

/// Temporary ownership only. Durable history staging must explicitly take ownership.
actor ObservationRetainedVideoClip {
    nonisolated let url: URL
    private let ownedDirectory: URL
    private enum Ownership: Equatable { case owned, deriving(UUID), transferred }
    private nonisolated let ownership = OSAllocatedUnfairLock(initialState: Ownership.owned)

    init(url: URL, ownedDirectory: URL) {
        self.url = url
        self.ownedDirectory = ownedDirectory
    }

    /// Transfers the file and its containing operation directory to the caller.
    func relinquishOwnership() throws -> URL {
        try Task.checkCancellation()
        try ownership.withLock { state in
            guard state == .owned else { throw ObservationRetainedVideoClipError.busy }
            state = .transferred
        }
        return url
    }

    func beginDerivation() throws -> ObservationRetainedVideoUse {
        try Task.checkCancellation()
        let id = UUID()
        try ownership.withLock { state in
            guard state == .owned else { throw ObservationRetainedVideoClipError.busy }
            state = .deriving(id)
        }
        return ObservationRetainedVideoUse(source: self, id: id)
    }

    fileprivate nonisolated func endDerivation(_ id: UUID) {
        ownership.withLock { state in
            if state == .deriving(id) { state = .owned }
        }
    }

    deinit {
        if ownership.withLock({ $0 != .transferred }) { try? FileManager.default.removeItem(at: ownedDirectory) }
    }
}

/// The token keeps the clip alive and releases its exclusive use synchronously on drop.
final class ObservationRetainedVideoUse: Sendable {
    let url: URL
    private let source: ObservationRetainedVideoClip
    private let id: UUID

    fileprivate init(source: ObservationRetainedVideoClip, id: UUID) {
        self.source = source; self.id = id; url = source.url
    }

    deinit { source.endDerivation(id) }
}

/// Inert preparation boundary: never installed into legacy capture or history admission.
/// One instance admits one transcode at a time; no source buffers escape the worker.
actor ObservationRetainedVideoClipProducer {
    private var occupied = false
    private let validateAfterFirstAppend: @Sendable () async throws -> Void

    init(validateAfterFirstAppend: @escaping @Sendable () async throws -> Void = {}) {
        self.validateAfterFirstAppend = validateAfterFirstAppend
    }

    func prepare(source: URL, directory: URL) async throws -> ObservationRetainedVideoClip {
        guard !occupied else { throw ObservationRetainedVideoClipError.busy }
        try Task.checkCancellation()
        occupied = true
        defer { occupied = false }
        let validation = validateAfterFirstAppend
        // Always join, including cancellation. The slot cannot reopen while a
        // prior worker still owns an encoder or an unaccepted output lease.
        let worker = Task.detached(priority: .utility) {
            try await Self.transcode(source: source, directory: directory, validation: validation)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    private nonisolated static func transcode(
        source: URL, directory: URL, validation: @Sendable () async throws -> Void
    ) async throws -> ObservationRetainedVideoClip {
        try Task.checkCancellation()
        guard source.isFileURL, directory.isFileURL else { throw ObservationRetainedVideoClipError.invalidSource }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= ScanMediaPayloadPolicy.maxSavedVideoBytes else {
            throw ObservationRetainedVideoClipError.invalidSource
        }
        let asset = AVURLAsset(url: source, options: [
            AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue
        ])
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard duration.isNumeric, duration.seconds >= 0.1, duration.seconds <= 5,
              videoTracks.count == 1, audioTracks.count <= 1,
              let track = videoTracks.first else { throw ObservationRetainedVideoClipError.unsupportedProfile }
        let dimensions = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        for dimension in [dimensions.width, dimensions.height] {
            guard dimension.isFinite, dimension >= 2, dimension <= 2048,
                  dimension.rounded() == dimension, Int(dimension) % 2 == 0 else {
                throw ObservationRetainedVideoClipError.unsupportedProfile
            }
        }
        guard supportsTransform(transform) else {
            throw ObservationRetainedVideoClipError.unsupportedProfile
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ownedDirectory = directory.appendingPathComponent("retained-video-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: false)
        var completed = false
        defer {
            if !completed { try? FileManager.default.removeItem(at: ownedDirectory) }
        }
        let url = ownedDirectory.appendingPathComponent("retained.mp4")
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.metadata = []
        writer.shouldOptimizeForNetworkUse = true
        writer.movieTimeScale = 600
        defer {
            if reader.status == .reading { reader.cancelReading() }
            if writer.status == .writing { writer.cancelWriting() }
        }
        let videoOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        videoOutput.alwaysCopiesSampleData = true
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dimensions.width), AVVideoHeightKey: Int(dimensions.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ])
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        var pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = [(videoOutput, videoInput)]
        if let audio = audioTracks.first {
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
            ])
            output.alwaysCopiesSampleData = true
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ])
            input.expectsMediaDataInRealTime = false
            pairs.append((output, input))
        }
        for (output, input) in pairs {
            guard reader.canAdd(output), writer.canAdd(input) else { throw ObservationRetainedVideoClipError.unsupportedProfile }
            reader.add(output)
            writer.add(input)
        }
        guard writer.startWriting() else { throw ObservationRetainedVideoClipError.writerFailure((writer.error as NSError?)?.code ?? 0) }
        guard reader.startReading() else { throw ObservationRetainedVideoClipError.readerFailure((reader.error as NSError?)?.code ?? 0) }
        writer.startSession(atSourceTime: .zero)
        let deadline = ContinuousClock.now + .seconds(30)
        var finished = Set<Int>()
        var counts = [Int](repeating: 0, count: pairs.count)
        var validated = false
        while finished.count < pairs.count {
            try checkProgress(deadline: deadline, url: url)
            guard writer.status == .writing else {
                throw ObservationRetainedVideoClipError.writerFailure((writer.error as NSError?)?.code ?? 0)
            }
            guard reader.status != .failed, reader.status != .cancelled else {
                throw ObservationRetainedVideoClipError.readerFailure((reader.error as NSError?)?.code ?? 0)
            }
            var progressed = false
            for (index, pair) in pairs.enumerated() where !finished.contains(index) && pair.1.isReadyForMoreMediaData {
                try autoreleasepool {
                    guard let buffer = pair.0.copyNextSampleBuffer() else {
                        pair.1.markAsFinished()
                        finished.insert(index)
                        return
                    }
                    counts[index] += 1
                    guard counts[index] <= (index == 0 ? 600 : 1024) else {
                        throw ObservationRetainedVideoClipError.oversized
                    }
                    guard pair.1.append(buffer) else {
                        throw ObservationRetainedVideoClipError.writerFailure((writer.error as NSError?)?.code ?? 0)
                    }
                }
                progressed = true
            }
            if !validated, counts.contains(where: { $0 > 0 }) {
                validated = true
                try await validation()
                try checkProgress(deadline: deadline, url: url)
            }
            if !progressed { try await Task.sleep(for: .milliseconds(5)) }
        }
        guard reader.status == .completed, counts.allSatisfy({ $0 > 0 }) else { throw ObservationRetainedVideoClipError.incompleteStream }
        writer.endSession(atSourceTime: duration)
        let finalization = RetainedVideoFinalization()
        writer.finishWriting { Task { await finalization.finish() } }
        while !(await finalization.isFinished) {
            try checkProgress(deadline: deadline, url: url)
            try await Task.sleep(for: .milliseconds(5))
        }
        guard writer.status == .completed else { throw ObservationRetainedVideoClipError.writerFailure((writer.error as NSError?)?.code ?? 0) }
        try checkProgress(deadline: deadline, url: url)
        guard try currentFileSize(url) > 0 else {
            throw ObservationRetainedVideoClipError.failed
        }
        // AVFoundation may leave sandbox scratch siblings even after completion.
        // This directory is exclusively ours; transfer only the finalized clip.
        for entry in try FileManager.default.contentsOfDirectory(at: ownedDirectory, includingPropertiesForKeys: nil)
            where entry.lastPathComponent != url.lastPathComponent {
            try FileManager.default.removeItem(at: entry)
        }
        try Task.checkCancellation()
        completed = true
        return ObservationRetainedVideoClip(url: url, ownedDirectory: ownedDirectory)
    }

    nonisolated static func supportsTransform(_ transform: CGAffineTransform) -> Bool {
        let components: [CGFloat] = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
        guard components.allSatisfy(\.isFinite) else { return false }
        for component in components.prefix(4) {
            guard component == -1 || component == 0 || component == 1 else { return false }
        }
        let determinant = transform.a * transform.d - transform.b * transform.c
        let firstLength = transform.a * transform.a + transform.b * transform.b
        let secondLength = transform.c * transform.c + transform.d * transform.d
        return abs(determinant) == 1 && firstLength == 1 && secondLength == 1
            && abs(transform.tx) <= 2048 && abs(transform.ty) <= 2048
    }

    private nonisolated static func currentFileSize(_ url: URL) throws -> Int {
        // URL resource values are cached; a growing writer output needs a fresh stat.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else { throw ObservationRetainedVideoClipError.failed }
        return size.intValue
    }

    private nonisolated static func checkProgress(deadline: ContinuousClock.Instant, url: URL) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw ObservationRetainedVideoClipError.timedOut }
        let size = try currentFileSize(url)
        guard size <= ScanMediaPayloadPolicy.maxSavedVideoBytes else { throw ObservationRetainedVideoClipError.oversized }
    }
}

private actor RetainedVideoFinalization {
    private(set) var isFinished = false
    func finish() { isFinished = true }
}
