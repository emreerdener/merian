import Foundation

enum InferenceMediaPolicy {
    static let maxInlineBodyBytes = 3_600_000
    static let maxInlineAudioBytes = MerianConfig.audioPayloadMaxBytes

    static func validatePayloadBudget(
        imageBase64s: [String],
        audioBase64s: [String]
    ) throws {
        var remainingBytes = maxInlineBodyBytes
        try consumeEncodedBytes(imageBase64s, remainingBytes: &remainingBytes)
        try consumeEncodedBytes(audioBase64s, remainingBytes: &remainingBytes)
    }

    static func validateAudioFiles(fileURLs: [URL]) throws {
        guard fileURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try validateAudioFileBudget(fileURLs: fileURLs)
        guard fileURLs.allSatisfy(InferenceAudioPreparer.isEdgeCompatibleWAV) else {
            throw MerianError.invalidResponse
        }
    }

    static func validateAudioFileBudget(fileURLs: [URL]) throws {
        var remainingBytes = maxInlineAudioBytes
        for url in fileURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let byteCount = try audioFileSize(at: url)
            guard byteCount <= remainingBytes else {
                throw MerianError.payloadTooLarge
            }
            remainingBytes -= byteCount
        }
    }

    private static func consumeEncodedBytes(
        _ values: [String],
        remainingBytes: inout Int
    ) throws {
        for value in values {
            let byteCount = value.utf8.count
            guard byteCount <= remainingBytes else {
                throw MerianError.payloadTooLarge
            }
            remainingBytes -= byteCount
        }
    }

    private static func audioFileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber {
            let byteCount = size.uint64Value
            guard byteCount <= UInt64(Int.max) else {
                throw MerianError.payloadTooLarge
            }
            return Int(byteCount)
        }
        throw MerianError.invalidResponse
    }
}

extension MerianNetworkClient {
    static let maxInlineInferenceBodyBytes = InferenceMediaPolicy.maxInlineBodyBytes
    static let maxInlineAudioBytes = InferenceMediaPolicy.maxInlineAudioBytes

    static func validateMultiModalPayloadBudget(
        imageBase64s: [String],
        audioBase64s: [String]
    ) throws {
        try InferenceMediaPolicy.validatePayloadBudget(
            imageBase64s: imageBase64s,
            audioBase64s: audioBase64s
        )
    }

    static func validateInlineAudioFilesForInference(fileURLs: [URL]) throws {
        try InferenceMediaPolicy.validateAudioFiles(fileURLs: fileURLs)
    }

    static func validateInlineAudioFileBudget(fileURLs: [URL]) throws {
        try InferenceMediaPolicy.validateAudioFileBudget(fileURLs: fileURLs)
    }
}
