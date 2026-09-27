#if DEBUG && targetEnvironment(simulator)
import CoreFoundation
import CryptoKit
import Foundation

/// A frozen experiment slot, not a caller-selected processing or model policy.
struct DebugAudioPromptComparisonAssignment: DebugAudioComparisonBinding {
    let slot: Int
    let block: Int
    let repeatIndex: Int
    let caseId: String
    let arm: String
    let sourceWavSha256: String
    let sourceByteLength: Int
    let processedWavSha256: String
    let providerRequestSha256: String
    let policySha256: String
    let confidenceSha256: String
    let scanId: String

    var planSha256: String { DebugAudioPromptComparisonPlan.sha256 }
    var requestKey: String { "audio_prompt_comparison" }
    var responseHeader: String { "X-Merian-Audio-Prompt-Comparison" }
    var eventVersion: String { "identification_audio_prompt_comparison_v1" }
    var logMarker: String { "[⏱ BENCH] Audio prompt comparison " }
    var requiresSubjectProof: Bool { true }

    var handle: [String: Any] {
        ["planSha256": DebugAudioPromptComparisonPlan.sha256, "slot": slot]
    }

    var receipt: [String: Any] {
        ["version": 1, "planSha256": DebugAudioPromptComparisonPlan.sha256,
         "slot": slot, "block": block, "repeat": repeatIndex, "caseId": caseId, "arm": arm,
         "sourceWavSha256": sourceWavSha256, "processedWavSha256": processedWavSha256,
         "providerRequestSha256": providerRequestSha256, "policySha256": policySha256,
         "confidenceSha256": confidenceSha256]
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func matchesSource(_ data: Data) -> Bool {
        data.count == sourceByteLength && Self.digest(data) == sourceWavSha256
    }

    /// Called off the main actor before dispatch; compare actual serialized audio.
    func addHandle(to payload: inout [String: Any]) throws {
        guard payload["client_scan_id"] as? String == scanId,
              let audio = payload["audioBase64s"] as? [String], audio.count == 1,
              let bytes = Data(base64Encoded: audio[0]), matchesSource(bytes) else {
            throw MerianError.invalidResponse
        }
        payload["audio_prompt_comparison"] = handle
    }

    func acceptsReceipt(_ header: String?) -> Bool {
        guard let header, header.utf8.count <= 1_024,
              let value = try? JSONSerialization.jsonObject(with: Data(header.utf8)) as? [String: Any],
              let version = value["version"] as? NSNumber, let slot = value["slot"] as? NSNumber,
              let block = value["block"] as? NSNumber, let repeatIndex = value["repeat"] as? NSNumber,
              [version, slot, block, repeatIndex].allSatisfy({ CFGetTypeID($0) != CFBooleanGetTypeID() })
        else { return false }
        return NSDictionary(dictionary: value).isEqual(to: receipt)
    }
}
#endif
