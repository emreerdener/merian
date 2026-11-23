import AudioToolbox
import AVFoundation

/// Companion sample zero is the original audio track's timeRange.start.
/// Empty edits become bounded silence; decoded sample timestamps retain gaps.
enum CaptureScanVideoAudioTimeline {
    private static let rate = 44_100.0
    private static let chunkFrames = 4_096

    nonisolated static func write(asset: AVAsset, output: MediaProducerOutput) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw InferenceAudioPreparationError.invalidAudio
        }
        let range = try await track.load(.timeRange)
        let duration = try await asset.load(.duration)
        let end = CMTimeMinimum(range.end, duration)
        let seconds = (end - range.start).seconds
        let maximumFrames = (ScanMediaPayloadPolicy.maxInferenceAudioBytes - 4_096) / 2
        guard range.start.isNumeric, range.start >= .zero, range.duration.isNumeric,
              range.duration > .zero, range.end.isNumeric, duration.isNumeric, duration > .zero,
              seconds.isFinite, seconds > 0 else { throw InferenceAudioPreparationError.invalidAudio }
        guard ceil(seconds * rate) <= Double(maximumFrames) else {
            throw InferenceAudioPreparationError.payloadTooLarge
        }
        let frameLimit = Int((seconds * rate).rounded())
        guard frameLimit > 0 else { throw InferenceAudioPreparationError.invalidAudio }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: range.start, end: end)
        let source = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        source.alwaysCopiesSampleData = true
        guard reader.canAdd(source) else { throw InferenceAudioPreparationError.invalidAudio }
        reader.add(source)
        defer { if reader.status == .reading { reader.cancelReading() } }

        var format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var destination: ExtAudioFileRef?
        guard ExtAudioFileCreateWithURL(output.outputURL as CFURL, kAudioFileWAVEType,
            &format, nil, AudioFileFlags.eraseFile.rawValue, &destination) == noErr,
              let destination else { throw InferenceAudioPreparationError.invalidAudio }
        var closed = false
        defer { if !closed { ExtAudioFileDispose(destination) } }
        try await output.pinCreatedOutput()
        guard ExtAudioFileSetProperty(destination, kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &format) == noErr,
              reader.startReading() else { throw InferenceAudioPreparationError.invalidAudio }

        var written = 0
        var receivedSamples = false
        while let sample = source.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let start = try frameOffset(CMSampleBufferGetPresentationTimeStamp(sample),
                origin: range.start, frameLimit: frameLimit)
            guard CMSampleBufferDataIsReady(sample),
                  let description = CMSampleBufferGetFormatDescription(sample),
                  let actual = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                  actual.pointee.mFormatID == kAudioFormatLinearPCM,
                  actual.pointee.mFormatFlags == (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked),
                  actual.pointee.mSampleRate == rate, actual.pointee.mChannelsPerFrame == 1,
                  actual.pointee.mBytesPerFrame == 2, actual.pointee.mBitsPerChannel == 16,
                  actual.pointee.mFramesPerPacket == 1, actual.pointee.mBytesPerPacket == 2,
                  let bytes = CMSampleBufferGetDataBuffer(sample) else {
                throw InferenceAudioPreparationError.invalidAudio
            }
            // One-frame timestamp rounding is harmless; arbitrary overlapping edits
            // must fail rather than silently concatenate or rewrite earlier samples.
            guard start >= written - 1 else { throw InferenceAudioPreparationError.invalidAudio }
            try writeFrames(max(0, min(start, frameLimit) - written), from: nil, offset: 0, to: destination)
            written = max(written, min(start, frameLimit))
            let count = CMSampleBufferGetNumSamples(sample)
            guard count > 0, count <= maximumFrames,
                  CMBlockBufferGetDataLength(bytes) == count * 2 else {
                throw InferenceAudioPreparationError.invalidAudio
            }
            let skipped = max(0, written - start)
            let copied = max(0, min(count - skipped, frameLimit - written))
            try writeFrames(copied, from: bytes, offset: skipped * 2, to: destination)
            written += copied
            receivedSamples = receivedSamples || copied > 0
        }
        guard reader.status == .completed, receivedSamples else {
            throw reader.error ?? InferenceAudioPreparationError.invalidAudio
        }
        try writeFrames(frameLimit - written, from: nil, offset: 0, to: destination)
        let finalization = ExtAudioFileDispose(destination)
        closed = true
        guard finalization == noErr else { throw InferenceAudioPreparationError.invalidAudio }
        try Task.checkCancellation()
    }

    /// Convert absolute asset time to companion frames exactly once. One frame
    /// permits sample timestamp rounding, never a larger gap/overlap correction.
    nonisolated static func frameOffset(_ time: CMTime, origin: CMTime, frameLimit: Int) throws -> Int {
        let offset = (time - origin).seconds * rate
        guard time.isNumeric, origin.isNumeric, frameLimit > 0,
              offset.isFinite, offset >= -1, offset <= Double(frameLimit) + 1 else {
            throw InferenceAudioPreparationError.invalidAudio
        }
        return max(0, Int(offset.rounded()))
    }

    /// Fixed-size copy/silence buffer; no duration-sized PCM allocation.
    nonisolated private static func writeFrames(
        _ count: Int, from source: CMBlockBuffer?, offset: Int, to output: ExtAudioFileRef
    ) throws {
        var remaining = count
        var copied = 0
        var buffer = [UInt8](repeating: 0, count: chunkFrames * 2)
        while remaining > 0 {
            try Task.checkCancellation()
            let frames = min(remaining, chunkFrames)
            try buffer.withUnsafeMutableBytes { bytes in
                if let source {
                    guard CMBlockBufferCopyDataBytes(source, atOffset: offset + copied * 2,
                        dataLength: frames * 2, destination: bytes.baseAddress!) == kCMBlockBufferNoErr else {
                        throw InferenceAudioPreparationError.invalidAudio
                    }
                }
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: UInt32(frames * 2), mData: bytes.baseAddress))
                guard ExtAudioFileWrite(output, UInt32(frames), &list) == noErr else {
                    throw InferenceAudioPreparationError.invalidAudio
                }
            }
            remaining -= frames
            copied += frames
        }
    }
}
