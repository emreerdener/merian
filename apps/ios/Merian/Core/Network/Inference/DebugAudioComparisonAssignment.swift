#if DEBUG && targetEnvironment(simulator)
import CoreFoundation
import CryptoKit
import Foundation

/// A frozen experiment slot, not a caller-selected processing or model policy.
struct DebugAudioComparisonAssignment: Sendable {
    let slot: Int
    let caseId: String
    let arm: String
    let sourceWavSha256: String
    let sourceByteLength: Int
    let processedWavSha256: String
    let providerRequestSha256: String
    let policySha256: String
    let confidenceSha256: String
    let scanId: String

    var handle: [String: Any] {
        ["planSha256": DebugAudioComparisonPlan.sha256, "slot": slot]
    }

    var receipt: [String: Any] {
        ["version": 1, "planSha256": DebugAudioComparisonPlan.sha256,
         "slot": slot, "caseId": caseId, "arm": arm,
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
        payload["audio_comparison"] = handle
    }

    func acceptsReceipt(_ header: String?) -> Bool {
        guard let header, header.utf8.count <= 1_024,
              let value = try? JSONSerialization.jsonObject(with: Data(header.utf8)) as? [String: Any],
              let version = value["version"] as? NSNumber, let slot = value["slot"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), CFGetTypeID(slot) != CFBooleanGetTypeID()
        else { return false }
        return NSDictionary(dictionary: value).isEqual(to: receipt)
    }
}
#endif
