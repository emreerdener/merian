#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Common mechanics only. Each immutable experiment owns its wire and proof contract.
protocol DebugAudioComparisonBinding: Sendable {
    var slot: Int { get }
    var scanId: String { get }
    var sourceByteLength: Int { get }
    var sourceWavSha256: String { get }
    var receipt: [String: Any] { get }
    var planSha256: String { get }
    var requestKey: String { get }
    var responseHeader: String { get }
    var eventVersion: String { get }
    var logMarker: String { get }
    var requiresSubjectProof: Bool { get }
    var handle: [String: Any] { get }
    func matchesSource(_ data: Data) -> Bool
    func addHandle(to payload: inout [String: Any]) throws
    func acceptsReceipt(_ header: String?) -> Bool
}

extension DebugAudioComparisonAssignment: DebugAudioComparisonBinding {
    var planSha256: String { DebugAudioComparisonPlan.sha256 }
    var requestKey: String { "audio_comparison" }
    var responseHeader: String { "X-Merian-Audio-Comparison" }
    var eventVersion: String { "identification_audio_comparison_v1" }
    var logMarker: String { "[⏱ BENCH] Audio comparison " }
    var requiresSubjectProof: Bool { false }
}
#endif
