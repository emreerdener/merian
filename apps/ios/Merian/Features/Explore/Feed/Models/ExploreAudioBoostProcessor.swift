import AVFoundation
import Foundation

struct ExploreAudioBoostResult: Sendable {
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

actor ExploreAudioBoostProcessor {
    static let shared = ExploreAudioBoostProcessor()

    private var cached: [String: ExploreAudioBoostResult] = [:]
    private var cacheOrder: [String] = []
    private let maxCacheEntries = 8

    func prepare(urlString: String) async throws -> ExploreAudioBoostResult {
        if let cached = cached[urlString] { return cached }
        guard let remoteURL = URL(string: urlString), remoteURL.scheme == "https" else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 30
        let (downloadURL, response) = try await URLSession.shared.download(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        let byteSize = try downloadURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard byteSize <= MerianConfig.audioPayloadMaxBytes else { throw URLError(.dataLengthExceedsMaximum) }

        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("explore-boost-source-\(UUID().uuidString).wav")
        try FileManager.default.moveItem(at: downloadURL, to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let result = try Self.renderBoostedAudio(sourceURL: sourceURL)
        cached[urlString] = result
        cacheOrder.removeAll { $0 == urlString }
        cacheOrder.append(urlString)
        while cacheOrder.count > maxCacheEntries {
            let evictedKey = cacheOrder.removeFirst()
            if let evicted = cached.removeValue(forKey: evictedKey) {
                try? FileManager.default.removeItem(at: evicted.url)
            }
        }
        return result
    }

    private static nonisolated func renderBoostedAudio(sourceURL: URL) throws -> ExploreAudioBoostResult {
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
        return ExploreAudioBoostResult(url: outputURL, gainDecibels: gainDb)
    }

    static nonisolated func adaptiveGainDecibels(rmsDb: Double, peakDb: Double) -> Double {
        max(0, min(18, min(-18 - rmsDb, -1 - peakDb)))
    }
}
