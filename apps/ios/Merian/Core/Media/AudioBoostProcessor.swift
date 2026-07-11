import AVFoundation
import Foundation

// Shared on-device listening enhancement for Explore and private Insight audio.

struct AudioBoostResult: Sendable {
    let url: URL
    let gainDecibels: Double

    var gainBand: String {
        switch gainDecibels {
        case ..<6: "low"
        case ..<12: "medium"
        default: "high"
        }
    }
}

struct AudioSourceLease: Sendable {
    let url: URL
    let shouldDeleteAfterUse: Bool

    func release() {
        if shouldDeleteAfterUse {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

actor AudioBoostProcessor {
    static let shared = AudioBoostProcessor()

    private var cached: [String: AudioBoostResult] = [:]
    private var cacheOrder: [String] = []
    private var inFlight: [String: Task<AudioBoostResult, Error>] = [:]
    private let maxCacheEntries = 8

    func prepare(source: String) async throws -> AudioBoostResult {
        if let cached = cached[source] { return cached }
        if let inFlight = inFlight[source] {
            return try await inFlight.value
        }

        let task = Task<AudioBoostResult, Error> {
            let resolved = try await Self.resolveSource(source)
            defer {
                if resolved.shouldDeleteAfterUse {
                    try? FileManager.default.removeItem(at: resolved.url)
                }
            }
            return try Self.renderBoostedAudio(sourceURL: resolved.url)
        }
        inFlight[source] = task

        let result: AudioBoostResult
        do {
            result = try await task.value
        } catch {
            inFlight[source] = nil
            throw error
        }
        inFlight[source] = nil
        cached[source] = result
        cacheOrder.removeAll { $0 == source }
        cacheOrder.append(source)
        while cacheOrder.count > maxCacheEntries {
            let evictedKey = cacheOrder.removeFirst()
            if let evicted = cached.removeValue(forKey: evictedKey) {
                try? FileManager.default.removeItem(at: evicted.url)
            }
        }
        return result
    }

    func prepare(urlString: String) async throws -> AudioBoostResult {
        try await prepare(source: urlString)
    }

    func acquireSource(_ source: String) async throws -> AudioSourceLease {
        try await Self.resolveSource(source)
    }

    private static func resolveSource(_ source: String) async throws -> AudioSourceLease {
        if let remoteURL = URL(string: source), remoteURL.scheme == "https" {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 30
            let (downloadURL, response) = try await URLSession.shared.download(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
            try validateSize(of: downloadURL)
            return AudioSourceLease(url: downloadURL, shouldDeleteAfterUse: true)
        }

        let localURL: URL
        if let fileURL = URL(string: source), fileURL.isFileURL {
            localURL = fileURL
        } else if source.hasPrefix("/") {
            localURL = URL(fileURLWithPath: source)
        } else {
            let documentsURL = URL.documentsDirectory.appendingPathComponent(source)
            localURL = FileManager.default.fileExists(atPath: documentsURL.path)
                ? documentsURL
                : FileManager.default.temporaryDirectory.appendingPathComponent(source)
        }
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try validateSize(of: localURL)
        return AudioSourceLease(url: localURL, shouldDeleteAfterUse: false)
    }

    private static func validateSize(of url: URL) throws {
        let byteSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard byteSize <= MerianConfig.audioPayloadMaxBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }
    }

    private static nonisolated func renderBoostedAudio(sourceURL: URL) throws -> AudioBoostResult {
        let source = try AVAudioFile(forReading: sourceURL)
        let format = source.processingFormat
        let frameCapacity = AVAudioFrameCount(min(source.length, 4096))
        guard frameCapacity > 0 else { throw CocoaError(.fileReadCorruptFile) }

        var sumSquares = 0.0
        var sampleCount = 0
        var peak = 0.0
        while source.framePosition < source.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try source.read(into: buffer)
            guard let channels = buffer.floatChannelData else { throw CocoaError(.fileReadCorruptFile) }
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let value = Double(channels[channel][frame])
                    sumSquares += value * value
                    peak = max(peak, abs(value))
                    sampleCount += 1
                }
            }
        }

        guard sampleCount > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let rms = sqrt(sumSquares / Double(sampleCount))
        let rmsDb = 20 * log10(max(rms, 0.000_001))
        let peakDb = 20 * log10(max(peak, 0.000_001))
        let gainDb = adaptiveGainDecibels(rmsDb: rmsDb, peakDb: peakDb)
        let linearGain = pow(10, gainDb / 20)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("explore-boosted-\(UUID().uuidString).wav")
        let output = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        source.framePosition = 0
        let highPassCutoff = 35.0
        let dt = 1.0 / format.sampleRate
        let rc = 1.0 / (2 * Double.pi * highPassCutoff)
        let highPassAlpha = rc / (rc + dt)
        var previousInput = Array(repeating: 0.0, count: Int(format.channelCount))
        var previousOutput = Array(repeating: 0.0, count: Int(format.channelCount))
        while source.framePosition < source.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity),
                  let channels = buffer.floatChannelData else { throw CocoaError(.fileReadCorruptFile) }
            try source.read(into: buffer)
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let input = Double(channels[channel][frame])
                    let clarified = highPassAlpha * (previousOutput[channel] + input - previousInput[channel])
                    previousInput[channel] = input
                    previousOutput[channel] = clarified
                    let amplified = clarified * linearGain
                    channels[channel][frame] = Float(max(-0.891, min(0.891, amplified)))
                }
            }
            try output.write(from: buffer)
        }
        return AudioBoostResult(url: outputURL, gainDecibels: gainDb)
    }

    static nonisolated func adaptiveGainDecibels(rmsDb: Double, peakDb: Double) -> Double {
        max(0, min(18, min(-18 - rmsDb, -1 - peakDb)))
    }
}
