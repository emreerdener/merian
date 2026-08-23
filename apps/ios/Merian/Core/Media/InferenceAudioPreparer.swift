import AudioToolbox
import AVFoundation
import Foundation

enum InferenceAudioPreparationError: Error, Equatable {
    case sourceUnavailable
    case insecureRemoteSource
    case payloadTooLarge
    case invalidAudio
}

/// Materializes any supported local or cloud-backed recording as the one audio
/// format accepted by scan inference: mono, interleaved, 16-bit PCM WAV.
///
/// The prepared file is a new Documents-owned sidecar. The caller may stage it
/// without moving or deleting the historical playback source; normal staged-media
/// removal and queue cleanup own the sidecar after this method returns.
enum InferenceAudioPreparer {
    static let sampleRate = 44_100.0
    static let channelCount: AVAudioChannelCount = 1

    private struct SourceLease {
        let url: URL
        let deleteAfterUse: Bool

        func release() {
            guard deleteAfterUse else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private struct WAVMetadata {
        let audioFormat: UInt16
        let channels: UInt16
        let sampleRate: UInt32
        let bitsPerSample: UInt16
        let dataLength: UInt32
    }

    static func isCanonicalInferencePath(_ path: String) -> Bool {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if let scheme = URLComponents(string: normalized)?.scheme,
           !scheme.isEmpty {
            return false
        }
        return URL(fileURLWithPath: normalized).pathExtension.lowercased() == "wav"
    }

    /// Validates the exact local source contract used before a capture may
    /// claim funding or become a durable queue row.
    static func isQueueEligibleInferenceAudioPath(_ path: String) -> Bool {
        guard isCanonicalInferencePath(path) else { return false }
        return inferenceSourceCandidates(for: path).contains(
            where: isEdgeCompatibleWAV
        )
    }

    static func prepareHistoricalReference(
        _ reference: StoredMediaReference,
        outputDirectory: URL = .documentsDirectory
    ) async throws -> URL {
        let source = try await acquireSource(reference)
        defer { source.release() }
        return try await prepareLocalFile(
            at: source.url,
            outputDirectory: outputDirectory
        )
    }

    static func prepareLocalFile(
        at sourceURL: URL,
        outputDirectory: URL = .documentsDirectory
    ) async throws -> URL {
        try await prepareLocalFile(
            at: sourceURL,
            outputDirectory: outputDirectory,
            outputFilePrefix: "historical-refinement-"
        )
    }

    /// Produces a queue-owned upgrade file with a distinct prefix so partial
    /// repair artifacts can never be mistaken for refinement sidecars.
    static func prepareLegacyQueuedFile(
        at sourceURL: URL,
        scanId: String,
        outputDirectory: URL = .documentsDirectory
    ) async throws -> URL {
        try await prepareLocalFile(
            at: sourceURL,
            outputDirectory: outputDirectory,
            outputFilePrefix: legacyQueueOutputPrefix(scanId: scanId)
        )
    }

    static func legacyQueueOutputPrefix(scanId: String) -> String {
        let sanitizedScanId = scanId.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-"
                || scalar == "_"
                ? String(scalar)
                : "_"
        }.joined()
        return "queued-audio-upgrade-\(sanitizedScanId.prefix(80))-"
    }

    private static func prepareLocalFile(
        at sourceURL: URL,
        outputDirectory: URL,
        outputFilePrefix: String
    ) async throws -> URL {
        try Task.checkCancellation()
        try validateSourceFile(at: sourceURL)

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let outputURL = outputDirectory
            .appendingPathComponent(
                "\(outputFilePrefix)\(UUID().uuidString.lowercased())"
            )
            .appendingPathExtension("wav")
        try? FileManager.default.removeItem(at: outputURL)

        do {
            try await transcodeToCanonicalWAV(
                sourceURL: sourceURL,
                outputURL: outputURL
            )
            try Task.checkCancellation()
            try validatePreparedFile(at: outputURL)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    static func isEdgeCompatibleWAV(at url: URL) -> Bool {
        guard let metadata = wavMetadata(at: url) else { return false }
        let isSupportedPCM = metadata.audioFormat == 1
            && metadata.bitsPerSample == 16
        let isSupportedFloat = metadata.audioFormat == 3
            && metadata.bitsPerSample == 32
        return (isSupportedPCM || isSupportedFloat)
            && metadata.channels > 0
            && metadata.sampleRate > 0
            && metadata.dataLength > 0
    }

    static func isCanonicalPreparedWAV(at url: URL) -> Bool {
        guard let metadata = wavMetadata(at: url) else { return false }
        return metadata.audioFormat == 1
            && metadata.bitsPerSample == 16
            && metadata.channels == UInt16(channelCount)
            && metadata.sampleRate == UInt32(sampleRate)
            && metadata.dataLength > 0
    }

    /// Returns the only audio MIME types allowed for durable playback restore.
    /// WAV is validated structurally; ISO base-media input must contain audio
    /// and no video before it may be labeled as M4A.
    static func durableStorageContentType(at url: URL) async -> String? {
        if isEdgeCompatibleWAV(at: url) {
            return "audio/wav"
        }
        guard isISOBaseMediaContainer(at: url) else { return nil }

        let asset = AVURLAsset(url: url)
        guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
              !audioTracks.isEmpty,
              let videoTracks = try? await asset.loadTracks(withMediaType: .video),
              videoTracks.isEmpty else {
            return nil
        }
        return "audio/mp4"
    }

    private static func isISOBaseMediaContainer(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 12),
              data.count == 12 else {
            return false
        }
        let bytes = [UInt8](data)
        return bytes[4] == 0x66
            && bytes[5] == 0x74
            && bytes[6] == 0x79
            && bytes[7] == 0x70
    }

    private static func wavMetadata(at url: URL) -> WAVMetadata? {
        guard let byteSize = try? fileSize(at: url),
              byteSize > 0,
              byteSize <= MerianConfig.audioPayloadMaxBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count >= 44 else {
            return nil
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
            return nil
        }

        var offset = 12
        var audioFormat: UInt16 = 0
        var channels: UInt16 = 0
        var detectedSampleRate: UInt32 = 0
        var bitsPerSample: UInt16 = 0
        var dataLength: UInt32 = 0

        while offset + 8 <= bytes.count {
            let chunkSize = Int(uint32LE(at: offset + 4))
            guard offset + 8 + chunkSize <= bytes.count else {
                return nil
            }
            if hasTag("fmt ", at: offset), chunkSize >= 16 {
                audioFormat = uint16LE(at: offset + 8)
                channels = uint16LE(at: offset + 10)
                detectedSampleRate = uint32LE(at: offset + 12)
                bitsPerSample = uint16LE(at: offset + 22)
            } else if hasTag("data", at: offset) {
                dataLength = UInt32(chunkSize)
                break
            }
            offset += 8 + chunkSize + (chunkSize.isMultiple(of: 2) ? 0 : 1)
        }

        return WAVMetadata(
            audioFormat: audioFormat,
            channels: channels,
            sampleRate: detectedSampleRate,
            bitsPerSample: bitsPerSample,
            dataLength: dataLength
        )
    }

    private static func acquireSource(
        _ reference: StoredMediaReference
    ) async throws -> SourceLease {
        if reference.isRemote {
            guard let remoteURL = reference.resolvedURL,
                  SecureTransportPolicy.isSecureRemoteURL(remoteURL) else {
                throw InferenceAudioPreparationError.insecureRemoteSource
            }
            let downloadedURL = try await downloadRemoteSource(from: remoteURL)
            return SourceLease(url: downloadedURL, deleteAfterUse: true)
        }

        guard let localPath = reference.resolvedLocalPath else {
            throw InferenceAudioPreparationError.sourceUnavailable
        }
        let localURL = URL(fileURLWithPath: localPath)
        try validateSourceFile(at: localURL)
        return SourceLease(url: localURL, deleteAfterUse: false)
    }

    /// Streams an authenticated-independent historical media URL into an owned
    /// temporary file. Both declared and actual bytes are capped; chunked or
    /// dishonest responses are cancelled before they can grow without bound.
    static func downloadRemoteSource(
        from remoteURL: URL,
        configuration: URLSessionConfiguration = .ephemeral,
        outputDirectory: URL = FileManager.default.temporaryDirectory
    ) async throws -> URL {
        guard SecureTransportPolicy.isSecureRemoteURL(remoteURL) else {
            throw InferenceAudioPreparationError.insecureRemoteSource
        }

        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw InferenceAudioPreparationError.sourceUnavailable
        }
        let maximumBytes = MerianConfig.audioPayloadMaxBytes
        guard response.expectedContentLength <= 0
                || response.expectedContentLength <= Int64(maximumBytes) else {
            throw InferenceAudioPreparationError.payloadTooLarge
        }

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let supportedExtension = ["wav", "m4a", "mp4"].contains(
            remoteURL.pathExtension.lowercased()
        ) ? remoteURL.pathExtension.lowercased() : "audio"
        let destinationURL = outputDirectory
            .appendingPathComponent(
                "historical-audio-source-\(UUID().uuidString.lowercased())"
            )
            .appendingPathExtension(supportedExtension)
        guard FileManager.default.createFile(
            atPath: destinationURL.path,
            contents: nil
        ) else {
            throw InferenceAudioPreparationError.sourceUnavailable
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
        var bufferedData = Data()
        bufferedData.reserveCapacity(64 * 1_024)
        var receivedByteCount = 0
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                receivedByteCount += 1
                guard receivedByteCount <= maximumBytes else {
                    throw InferenceAudioPreparationError.payloadTooLarge
                }
                bufferedData.append(byte)
                if bufferedData.count >= 64 * 1_024 {
                    try handle.write(contentsOf: bufferedData)
                    bufferedData.removeAll(keepingCapacity: true)
                }
            }
            if !bufferedData.isEmpty {
                try handle.write(contentsOf: bufferedData)
            }
            try handle.close()
            try validateSourceFile(at: destinationURL)
            return destinationURL
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    private static func inferenceSourceCandidates(for path: String) -> [URL] {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("/") {
            return [URL(fileURLWithPath: normalized)]
        }
        return [
            URL.documentsDirectory.appendingPathComponent(normalized),
            FileManager.default.temporaryDirectory.appendingPathComponent(normalized)
        ]
    }

    private static func transcodeToCanonicalWAV(
        sourceURL: URL,
        outputURL: URL
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw InferenceAudioPreparationError.invalidAudio
        }

        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw InferenceAudioPreparationError.invalidAudio
        }
        let estimatedOutputBytes = ceil(
            duration * sampleRate * Double(channelCount) * 2
        ) + 4_096
        guard estimatedOutputBytes.isFinite,
              estimatedOutputBytes <= Double(MerianConfig.audioPayloadMaxBytes) else {
            throw InferenceAudioPreparationError.payloadTooLarge
        }

        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger |
                kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: channelCount,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var sourceFile: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(sourceURL as CFURL, &sourceFile) == 0,
              let sourceFile else {
            throw InferenceAudioPreparationError.invalidAudio
        }
        defer { ExtAudioFileDispose(sourceFile) }

        let formatSize = UInt32(
            MemoryLayout<AudioStreamBasicDescription>.size
        )
        guard ExtAudioFileSetProperty(
            sourceFile,
            kExtAudioFileProperty_ClientDataFormat,
            formatSize,
            &format
        ) == 0 else {
            throw InferenceAudioPreparationError.invalidAudio
        }

        var outputFile: ExtAudioFileRef?
        guard ExtAudioFileCreateWithURL(
            outputURL as CFURL,
            kAudioFileWAVEType,
            &format,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &outputFile
        ) == 0,
            let outputFile else {
            throw InferenceAudioPreparationError.invalidAudio
        }
        defer { ExtAudioFileDispose(outputFile) }
        guard ExtAudioFileSetProperty(
            outputFile,
            kExtAudioFileProperty_ClientDataFormat,
            formatSize,
            &format
        ) == 0 else {
            throw InferenceAudioPreparationError.invalidAudio
        }

        let framesPerBuffer: UInt32 = 4_096
        let bytesPerFrame = Int(format.mBytesPerFrame)
        var buffer = Data(
            count: Int(framesPerBuffer) * bytesPerFrame
        )
        let maxPCMByteCount = MerianConfig.audioPayloadMaxBytes - 44
        var writtenByteCount = 0

        while true {
            try Task.checkCancellation()
            var frameCount = framesPerBuffer
            let readStatus = buffer.withUnsafeMutableBytes { bytes in
                let audioBuffer = AudioBuffer(
                    mNumberChannels: channelCount,
                    mDataByteSize: UInt32(bytes.count),
                    mData: bytes.baseAddress
                )
                var bufferList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: audioBuffer
                )
                return ExtAudioFileRead(
                    sourceFile,
                    &frameCount,
                    &bufferList
                )
            }
            guard readStatus == 0 else {
                throw InferenceAudioPreparationError.invalidAudio
            }
            guard frameCount > 0 else {
                break
            }
            let byteCount = Int(frameCount) * bytesPerFrame
            guard writtenByteCount <= maxPCMByteCount - byteCount else {
                throw InferenceAudioPreparationError.payloadTooLarge
            }
            let writeStatus = buffer.withUnsafeMutableBytes { bytes in
                let audioBuffer = AudioBuffer(
                    mNumberChannels: channelCount,
                    mDataByteSize: UInt32(byteCount),
                    mData: bytes.baseAddress
                )
                var bufferList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: audioBuffer
                )
                return ExtAudioFileWrite(
                    outputFile,
                    frameCount,
                    &bufferList
                )
            }
            guard writeStatus == 0 else {
                throw InferenceAudioPreparationError.invalidAudio
            }
            writtenByteCount += byteCount
        }

        guard writtenByteCount > 0 else {
            throw InferenceAudioPreparationError.invalidAudio
        }
    }

    private static func validateSourceFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InferenceAudioPreparationError.sourceUnavailable
        }
        let byteSize = try fileSize(at: url)
        guard byteSize > 0 else {
            throw InferenceAudioPreparationError.invalidAudio
        }
        guard byteSize <= MerianConfig.audioPayloadMaxBytes else {
            throw InferenceAudioPreparationError.payloadTooLarge
        }
    }

    private static func validatePreparedFile(at url: URL) throws {
        try validateSourceFile(at: url)
        guard isCanonicalPreparedWAV(at: url) else {
            throw InferenceAudioPreparationError.invalidAudio
        }
    }

    private static func fileSize(at url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize ?? 0
    }
}
