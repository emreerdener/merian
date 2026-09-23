#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
final class AudioComparisonTestFixture {
    let assignment = DebugAudioComparisonSlot.slot1.assignment
    var records: [String] = []
    lazy var capture = IdentificationComparisonCapture(assignment: assignment) { [unowned self] in records.append($0) }

    var events: [String] {
        records.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["event"] as? String }
    }

    func response(receipt: [String: Any]? = nil, replay: String? = nil, status: Int = 200) throws -> HTTPURLResponse {
        let diagnostics: [String: Any] = [
            "version": 1, "provider": "gemini", "requestedModel": "gemini-2.5-pro",
            "returnedModel": "gemini-2.5-pro", "backendBundleSha256": String(repeating: "b", count: 64)
        ]
        var headers = [
            "X-Merian-Audio-Comparison": String(decoding: try JSONSerialization.data(withJSONObject: receipt ?? assignment.receipt), as: UTF8.self),
            "X-Merian-Identification": String(decoding: try JSONSerialization.data(withJSONObject: diagnostics), as: UTF8.self),
            "Server-Timing": "provider;dur=10.1, edge_total;dur=20.2"
        ]
        headers["X-Merian-Idempotent-Replay"] = replay
        return try #require(HTTPURLResponse(url: URL(string: "https://example.invalid/identify-multimodal")!, statusCode: status, httpVersion: nil, headerFields: headers))
    }

    @discardableResult
    func receive(response: HTTPURLResponse? = nil, current: Bool = true, fixed: Bool = true) throws -> String {
        let response = try response ?? self.response()
        let measurement = try #require(IdentificationBenchmarkRecord.make(response: response, appInfo: [:], fixedAudioContext: fixed))
        capture.receive(response: response, measurement: measurement, isCurrentInitialAttempt: current)
        return measurement
    }
}

@MainActor
@Suite("Identification Comparison Capture")
struct IdentificationComparisonCaptureTests {
    @Test func exactReceiptJoinsMeasurementAndOneShotFinalizationAndRender() throws {
        let fixture = AudioComparisonTestFixture()
        let text = try fixture.receive()
        let id = fixture.assignment.scanId
        fixture.capture.recordFirstRender(scanId: "synthetic-wrong-scan")
        fixture.capture.finalize(scanId: "synthetic-wrong-scan", confidenceScore: 0.9, isBiological: true, persistence: .saved)
        #expect(fixture.events == ["receipt"])
        fixture.capture.recordFirstRender(scanId: id)
        fixture.capture.finalize(scanId: id, confidenceScore: 0.9, isBiological: true, persistence: .saved)
        fixture.capture.recordFirstRender(scanId: id)
        fixture.capture.finalize(scanId: id, confidenceScore: 0.9, isBiological: true, persistence: .saved)
        #expect(fixture.events == ["receipt", "rendered", "finalized"])
        for record in fixture.records {
            let value = try #require(JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any])
            #expect(value["measurementSha256"] as? String == DebugAudioComparisonAssignment.digest(Data(text.utf8)))
            #expect(record.utf8.count + IdentificationComparisonCapture.marker.utf8.count < 1_024)
            #expect(!record.contains(id))
            #expect(!record.contains("sourceWavSha256"))
        }
    }

    @Test func malformedReceiptMissingProofReplayAndStaleAttemptsCannotComplete() throws {
        for key in DebugAudioComparisonSlot.slot1.assignment.receipt.keys {
            let fixture = AudioComparisonTestFixture()
            var receipt = fixture.assignment.receipt
            receipt[key] = "synthetic-wrong-value"
            try fixture.receive(response: fixture.response(receipt: receipt))
            fixture.capture.finalize(scanId: fixture.assignment.scanId, confidenceScore: 0.9, isBiological: true, persistence: .saved)
            fixture.capture.recordFirstRender(scanId: fixture.assignment.scanId)
            #expect(fixture.records.isEmpty)
        }
        for failure in ["replay", "retry", "stale", "ordinary", "failure", "extra"] {
            let fixture = AudioComparisonTestFixture()
            var receipt = fixture.assignment.receipt
            if failure == "extra" { receipt["rawContent"] = "synthetic-private" }
            let response = try fixture.response(receipt: receipt, replay: failure == "replay" ? "stored" : nil, status: failure == "failure" ? 503 : 200)
            try fixture.receive(response: response, current: !["retry", "stale"].contains(failure), fixed: failure != "ordinary")
            #expect(fixture.records.isEmpty)
        }
        var booleanVersion = DebugAudioComparisonSlot.slot1.assignment.receipt
        booleanVersion["version"] = true
        #expect(!DebugAudioComparisonSlot.slot1.assignment.acceptsReceipt(String(decoding: try JSONSerialization.data(withJSONObject: booleanVersion), as: UTF8.self)))
    }

    @Test func responseAdoptionRechecksTheLiveOwnerOnTheMainActor() throws {
        let fixture = AudioComparisonTestFixture()
        let telemetry = DebugIdentificationReplayProfile.audioComparison(slot: .slot1).makeTelemetry()
        let body: [String: Any] = [
            "user_id": "synthetic-owner", "client_scan_id": fixture.assignment.scanId,
            "geoprivacy": "private", "mimeType": "image/webp", "deviceLocale": "en", "deviceTimeZone": "UTC",
            "currentMonth": 1, "timeOfDay": "12:00 PM", "audioBase64s": ["AA=="],
            "audioMediaItems": [IdentifyAudioMediaItem.audio(sourceIndex: 0).jsonObject],
            "ownerMediaTimeline": [IdentifyOwnerMediaTimelineItem.audio(audioInputIndex: 0, sourceIndex: 0).jsonObject],
            "audio_comparison": fixture.assignment.handle
        ]
        var current = true
        let context = try #require(IdentificationMeasurementContext.fixedAudio(
            body: JSONSerialization.data(withJSONObject: body), telemetry: telemetry,
            validateAttempt: { if !current { throw CancellationError() } }, comparisonCapture: fixture.capture
        ))
        #expect(context.isCurrent())
        current = false // Owner changed between the timing snapshot and header adoption.
        let response = try fixture.response()
        let measurement = try #require(IdentificationBenchmarkRecord.make(response: response, appInfo: [:], fixedAudioContext: true))
        context.recordComparisonResponse(response: response, measurement: measurement, isInitialAttempt: true)
        #expect(fixture.records.isEmpty)
    }

    @Test func secondHTTPResponseInvalidatesProofAndNoMatchRemainsExplicit() throws {
        let repeated = AudioComparisonTestFixture()
        try repeated.receive()
        try repeated.receive(current: false)
        repeated.capture.finalize(scanId: repeated.assignment.scanId, confidenceScore: 0.9, isBiological: true, persistence: .saved)
        repeated.capture.recordFirstRender(scanId: repeated.assignment.scanId)
        #expect(repeated.events == ["receipt"])
        let noMatch = AudioComparisonTestFixture()
        try noMatch.receive()
        noMatch.capture.finalize(scanId: noMatch.assignment.scanId, confidenceScore: 0, isBiological: false, persistence: .completedWithoutRecord)
        #expect(noMatch.records.last?.contains("completed_without_record") == true)
        #expect(noMatch.events == ["receipt", "finalized"])
    }

    @Test func renderProofIsExactAndClearedByReplacementAndAuth() throws {
        for transition in ["reset", "auth", "published", "quiescence"] {
            let fixture = AudioComparisonTestFixture()
            try fixture.receive()
            let owner = InferencePresentationCoordinator()
            owner.armComparisonRender(fixture.capture, scanId: fixture.assignment.scanId)
            #expect(owner.consumeComparisonRender(scanId: "synthetic-other") == nil)
            switch transition {
            case "reset": owner.reset()
            case "auth": owner.clearForAuthTransitionAdmission()
            case "published": owner.clearForPublishedResult()
            default: owner.finishAuthTransitionQuiescence()
            }
            #expect(owner.consumeComparisonRender(scanId: fixture.assignment.scanId) == nil)
        }
        let fixture = AudioComparisonTestFixture()
        let owner = InferencePresentationCoordinator()
        owner.armComparisonRender(fixture.capture, scanId: fixture.assignment.scanId)
        #expect(owner.consumeComparisonRender(scanId: fixture.assignment.scanId) === fixture.capture)
        #expect(owner.consumeComparisonRender(scanId: fixture.assignment.scanId) == nil)
    }

    @Test func sourceGuardRejectsChangedBytesAndWrongQueueIdentity() throws {
        let bytes = Data([1, 2, 3, 4])
        let frozen = DebugAudioComparisonSlot.slot1.assignment
        let synthetic = DebugAudioComparisonAssignment(
            slot: frozen.slot, caseId: frozen.caseId, arm: frozen.arm,
            sourceWavSha256: DebugAudioComparisonAssignment.digest(bytes), sourceByteLength: bytes.count,
            processedWavSha256: frozen.processedWavSha256, providerRequestSha256: frozen.providerRequestSha256,
            policySha256: frozen.policySha256, confidenceSha256: frozen.confidenceSha256, scanId: frozen.scanId
        )
        var payload: [String: Any] = ["client_scan_id": synthetic.scanId, "audioBase64s": [bytes.base64EncodedString()]]
        try synthetic.addHandle(to: &payload)
        #expect((payload["audio_comparison"] as? [String: Any])?["slot"] as? Int == 1)
        payload["client_scan_id"] = "synthetic-other"
        #expect(throws: (any Error).self) { try synthetic.addHandle(to: &payload) }
        #expect(!synthetic.matchesSource(Data([1, 2, 3, 5])))
        #expect(!synthetic.matchesSource(bytes + Data([5])))
        #expect(!frozen.matchesSource(bytes))
    }

    @Test func comparisonIDsCannotUpsertQueuedOrSavedRecords() throws {
        let schema = Schema([OfflineQueuedScan.self, LocalScanRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let id = DebugAudioComparisonSlot.slot1.assignment.scanId
        #expect(!DebugAudioComparisonAdmission.isAvailable(scanId: id, context: nil))
        #expect(DebugAudioComparisonAdmission.isAvailable(scanId: id, context: context))
        let queued = OfflineQueuedScan(id: id)
        context.insert(queued)
        try context.save()
        #expect(!DebugAudioComparisonAdmission.isAvailable(scanId: id, context: context))
        context.delete(queued)
        try context.save()
        context.insert(LocalScanRecord(id: id, speciesId: "synthetic-species", scientificName: "Synthetic taxon", commonName: "Synthetic subject"))
        try context.save()
        #expect(!DebugAudioComparisonAdmission.isAvailable(scanId: id, context: context))
        #expect(DebugAudioComparisonAdmission.isAvailable(scanId: DebugAudioComparisonSlot.slot2.assignment.scanId, context: context))
    }
}
#endif
