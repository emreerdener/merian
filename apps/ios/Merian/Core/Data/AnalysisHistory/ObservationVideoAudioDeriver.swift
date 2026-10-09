import AVFoundation
import CryptoKit
import Foundation

/// Temporary audio only. No partial cohort may transfer into durable staging.
actor ObservationVideoAudioDerivation {
    nonisolated let source: ObservationVideoProvenance.Artifact
    nonisolated let audio: ObservationVideoProvenance.Audio
    nonisolated let file: URL
    private let use: ObservationRetainedVideoUse
    private let directory: URL

    init(source: ObservationVideoProvenance.Artifact, audio: ObservationVideoProvenance.Audio,
         file: URL, use: ObservationRetainedVideoUse, directory: URL) {
        self.source = source; self.audio = audio; self.file = file; self.use = use; self.directory = directory
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

enum ObservationVideoAudioError: Error {
    case busy, invalidSource, invalidPCM, sourceChanged, timedOut
}

/// Inert, bounded extraction from the exact retained clip. Nil means no track.
actor ObservationVideoAudioDeriver {
    private var occupied = false
    private let validateAfterWrite: @Sendable () async throws -> Void
    private let validateAfterBuffer: @Sendable (Int) async throws -> Void

    init(validateAfterWrite: @escaping @Sendable () async throws -> Void = {},
         validateAfterBuffer: @escaping @Sendable (Int) async throws -> Void = { _ in }) {
        self.validateAfterWrite = validateAfterWrite
        self.validateAfterBuffer = validateAfterBuffer
    }

    func derive(source: ObservationRetainedVideoClip, sourceMediaID: UUID, directory: URL) async throws -> ObservationVideoAudioDerivation? {
        guard !occupied else { throw ObservationVideoAudioError.busy }
        guard directory.isFileURL else { throw ObservationVideoAudioError.invalidSource }
        try Task.checkCancellation()
        occupied = true
        defer { occupied = false }
        let use = try await source.beginDerivation()
        let validate = validateAfterBuffer
        let afterWrite = validateAfterWrite
        let worker = Task.detached(priority: .utility) {
            try await Self.prepare(use: use, sourceMediaID: sourceMediaID, directory: directory, validate: validate, afterWrite: afterWrite)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }

    nonisolated static func prepare(use: ObservationRetainedVideoUse, sourceMediaID: UUID, directory: URL,
                                    validate: @Sendable (Int) async throws -> Void, afterWrite: @Sendable () async throws -> Void) async throws -> ObservationVideoAudioDerivation? {
        guard directory.isFileURL else { throw ObservationVideoAudioError.invalidSource }
        try Task.checkCancellation()
        let source = try use.artifact(mediaID: sourceMediaID)
        let asset = AVURLAsset(url: use.url, options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, (0.1...5).contains(duration.seconds) else { throw ObservationVideoAudioError.invalidSource }
        let durationTicks = ticks(duration)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        try Task.checkCancellation()
        guard tracks.count <= 1 else { throw ObservationVideoAudioError.invalidSource }
        guard let track = tracks.first else {
            guard try use.artifact(mediaID: sourceMediaID) == source else { throw ObservationVideoAudioError.sourceChanged }
            return nil
        }
        let reader = try AVAssetReader(asset: asset)
        defer { reader.cancelReading() }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { throw ObservationVideoAudioError.invalidPCM }
        reader.add(output)
        guard reader.startReading() else { throw ObservationVideoAudioError.invalidPCM }
        let deadline = ContinuousClock.now + .seconds(30)
        var pcm = Data()
        var timeline = ObservationVideoAudioTimeline()
        var buffers = 0
        while reader.status == .reading {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw ObservationVideoAudioError.timedOut }
            let found = try autoreleasepool { () throws -> Bool in
                guard let sample = output.copyNextSampleBuffer() else { return false }
                buffers += 1
                guard buffers <= 1024 else { throw ObservationVideoAudioError.invalidPCM }
                let size = CMSampleBufferGetNumSamples(sample)
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                guard size > 0, size <= 220_500,
                      let description = CMSampleBufferGetFormatDescription(sample),
                      let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
                      format.mFormatID == kAudioFormatLinearPCM, format.mSampleRate == 44_100,
                      format.mChannelsPerFrame == 1, format.mBitsPerChannel == 16,
                      format.mBytesPerFrame == 2, format.mFramesPerPacket == 1, format.mBytesPerPacket == 2,
                      format.mFormatFlags == kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                      let block = CMSampleBufferGetDataBuffer(sample), CMBlockBufferGetDataLength(block) == size * 2 else {
                    throw ObservationVideoAudioError.invalidPCM
                }
                try timeline.append(presentationTime: pts, sampleCount: size)
                var bytes = Data(count: size * 2)
                let status = bytes.withUnsafeMutableBytes { buffer in
                    guard let address = buffer.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
                    return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size * 2, destination: address)
                }
                guard status == kCMBlockBufferNoErr else { throw ObservationVideoAudioError.invalidPCM }
                pcm.append(bytes)
                return true
            }
            if !found { break }
            try await validate(buffers)
        }
        try Task.checkCancellation()
        guard reader.status == .completed else { throw ObservationVideoAudioError.invalidPCM }
        let interval = try timeline.interval(durationTicks: durationTicks)
        guard ContinuousClock.now < deadline else { throw ObservationVideoAudioError.timedOut }
        let bytes = wav(pcm)
        guard let inspection = ObservationAudioContainer.inspect(bytes), inspection.sampleCount == timeline.sampleCount else { throw ObservationVideoAudioError.invalidPCM }
        guard try use.artifact(mediaID: sourceMediaID) == source else { throw ObservationVideoAudioError.sourceChanged }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let owned = directory.appendingPathComponent("video-audio-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: owned) } }
        var id = UUID()
        while id == sourceMediaID { id = UUID() }
        let file = owned.appendingPathComponent("\(id.uuidString.lowercased()).wav")
        try bytes.write(to: file, options: .atomic)
        try await afterWrite()
        try Task.checkCancellation()
        guard try use.artifact(mediaID: sourceMediaID) == source else { throw ObservationVideoAudioError.sourceChanged }
        let audio = ObservationVideoProvenance.Audio(sourceMediaID: sourceMediaID, startTicks: interval.start, endTicks: interval.end,
                                                     sampleCount: inspection.sampleCount,
                                                     artifact: .init(mediaID: id, contentType: "audio/wav", byteCount: bytes.count, sha256: hash(bytes)))
        let result = ObservationVideoAudioDerivation(source: source, audio: audio, file: file, use: use, directory: owned)
        complete = true
        return result
    }

    private nonisolated static func ticks(_ time: CMTime) -> Int {
        Int(CMTimeConvertScale(time, timescale: 600, method: .roundHalfAwayFromZero).value)
    }

    private nonisolated static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

    /// Fixed compact PCM header; decoded sample bytes are not transcoded again.
    private nonisolated static func wav(_ pcm: Data) -> Data {
        var result = Data("RIFF".utf8)
        func word(_ value: UInt32) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        }
        word(UInt32(36 + pcm.count)); result.append(contentsOf: "WAVEfmt ".utf8)
        word(16); word(0x0001_0001); word(44_100); word(88_200); word(0x0010_0002)
        result.append(contentsOf: "data".utf8); word(UInt32(pcm.count)); result.append(pcm)
        return result
    }
}

/// Integer PCM timing checks, independent of codec insertion of decoded silence.
struct ObservationVideoAudioTimeline {
    private var start: CMTime?
    private var end: CMTime?
    private(set) var sampleCount = 0

    mutating func append(presentationTime: CMTime, sampleCount count: Int) throws {
        guard count > 0, count <= 220_500 - sampleCount,
              presentationTime.isNumeric, presentationTime >= .zero else { throw ObservationVideoAudioError.invalidPCM }
        if let end, CMTimeCompare(presentationTime, end) != 0 { throw ObservationVideoAudioError.invalidPCM }
        let next = CMTimeAdd(presentationTime, CMTime(value: Int64(count), timescale: 44_100))
        guard next.isNumeric else { throw ObservationVideoAudioError.invalidPCM }
        if start == nil { start = presentationTime }
        end = next
        sampleCount += count
    }

    func interval(durationTicks: Int) throws -> (start: Int, end: Int) {
        guard (60...3000).contains(durationTicks), let start, let end else { throw ObservationVideoAudioError.invalidPCM }
        let first = CMTimeConvertScale(start, timescale: 600, method: .roundHalfAwayFromZero)
        let last = CMTimeConvertScale(end, timescale: 600, method: .roundHalfAwayFromZero)
        guard first.isNumeric, last.isNumeric, first.value >= 0, last.value > first.value, last.value <= Int64(durationTicks),
              abs(sampleCount * 600 - Int(last.value - first.value) * 44_100) <= 44_100 else { throw ObservationVideoAudioError.invalidPCM }
        return (Int(first.value), Int(last.value))
    }
}
