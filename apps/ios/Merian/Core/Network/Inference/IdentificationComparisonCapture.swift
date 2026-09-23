import Foundation

/// Ephemeral handoff from an authenticated foreground response to its exact
/// presentation and queue completion. It cannot be restored by queue recovery.
@MainActor
final class IdentificationComparisonCapture {
    enum Persistence: String {
        case saved
        case completedWithoutRecord = "completed_without_record"
    }
    #if DEBUG && targetEnvironment(simulator)
    static let marker = "[⏱ BENCH] Audio comparison "
    let assignment: DebugAudioComparisonAssignment
    private let record: (String) -> Void
    private var measurementSha256: String?
    private var received = false
    private var finalized = false
    private var rendered = false

    init(assignment: DebugAudioComparisonAssignment, record: @escaping (String) -> Void) {
        self.assignment = assignment
        self.record = record
    }
    #endif

    static func make(telemetry: CaptureTelemetry, scanId: String?) -> IdentificationComparisonCapture? {
        #if DEBUG && targetEnvironment(simulator)
        guard let assignment = telemetry.debugReplayProfile?.comparison,
              assignment.scanId == scanId else { return nil }
        return Self(assignment: assignment) { record in
            MerianLog.network.debug("[⏱ BENCH] Audio comparison \(record, privacy: .public)")
        }
        #else
        return nil
        #endif
    }

    func receive(response: HTTPURLResponse, measurement: String, isCurrentInitialAttempt: Bool) {
        #if DEBUG && targetEnvironment(simulator)
        guard !received else {
            measurementSha256 = nil
            return
        }
        received = true
        guard isCurrentInitialAttempt, !Task.isCancelled,
              response.statusCode == 200,
              response.value(forHTTPHeaderField: "X-Merian-Idempotent-Replay") == nil,
              assignment.acceptsReceipt(response.value(forHTTPHeaderField: "X-Merian-Audio-Comparison")),
              let value = try? JSONSerialization.jsonObject(with: Data(measurement.utf8)) as? [String: Any],
              value["contextProfile"] as? String == "audio-minimal-v1",
              value["delivery"] as? String == "fresh",
              let diagnostics = value["diagnostics"] as? [String: Any],
              diagnostics["requestedModel"] as? String == "gemini-2.5-pro"
        else { return }
        measurementSha256 = DebugAudioComparisonAssignment.digest(Data(measurement.utf8))
        emit("receipt")
        #endif
    }

    func matches(scanId: String?) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        return measurementSha256 != nil && scanId == assignment.scanId
        #else
        return false
        #endif
    }

    /// Called only after successful exact-generation durable queue finalization.
    func finalize(scanId: String?, confidenceScore: Double, isBiological: Bool, persistence: Persistence) {
        #if DEBUG && targetEnvironment(simulator)
        guard !finalized, !Task.isCancelled, matches(scanId: scanId),
              confidenceScore.isFinite, (0...1).contains(confidenceScore) else { return }
        finalized = true
        emit("finalized", extra: [
            "confidenceScore": confidenceScore, "isBiological": isBiological,
            "persistence": persistence.rawValue
        ])
        #endif
    }

    /// Called by the existing exact-scan UIKit draw probe, never by HTTP success.
    func recordFirstRender(scanId: String) {
        #if DEBUG && targetEnvironment(simulator)
        guard !rendered, matches(scanId: scanId) else { return }
        rendered = true
        emit("rendered")
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private func emit(_ event: String, extra: [String: Any] = [:]) {
        guard let measurementSha256 else { return }
        var value: [String: Any] = [
            "version": "identification_audio_comparison_v1", "event": event,
            "planSha256": DebugAudioComparisonPlan.sha256, "slot": assignment.slot,
            "measurementSha256": measurementSha256
        ]
        value.merge(extra) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              data.count + Self.marker.utf8.count <= 1_024,
              let text = String(data: data, encoding: .utf8) else { return }
        record(text)
    }
    #endif
}
