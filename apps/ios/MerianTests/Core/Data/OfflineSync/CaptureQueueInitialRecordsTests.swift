import Foundation
@testable import Merian
import Testing

@Suite("Capture queue initial record mappings")
@MainActor
struct CaptureQueueInitialRecordsTests {
    @Test(arguments: [0, 1, 2])
    func preservesSubmissionMapping(variant: Int) throws {
        let scanID = UUID().uuidString.lowercased()
        let generation = UUID()
        let timestamp = Date(timeIntervalSince1970: 100)
        let funding = ScanFundingReservation(
            accountId: UUID(), scanId: scanID, source: .complimentaryPro,
            createdAt: timestamp
        )
        let goal = FieldTripPreferredGoal(userFieldTripId: "synthetic-trip", itemId: "synthetic-goal")
        let records = CaptureQueueInitialRecords(
            scanId: scanID, timestamp: timestamp, capturedMediaJSON: nil,
            initialFieldNotes: "Synthetic field notes", inferenceImagePaths: ["synthetic.webp"],
            visualMediaItemsJSON: "[]", preferredGoal: goal,
            telemetry: CaptureTelemetry(
                subjectDistanceInMeters: 2, gpsLatitude: nil, gpsLongitude: nil,
                gpsElevation: nil, locationName: nil, weatherCondition: nil,
                weatherTemperatureF: nil, timeOfDay: nil, timestamp: nil, zoomFactor: 1.5
            ),
            blurScore: 0.5, funding: funding, foregroundInferenceGeneration: generation,
            mode: variant == 0 ? .visual : .nonVisual(hasUploadableMedia: variant == 1)
        )
        #expect(records.scan.id == scanID)
        #expect(records.scan.timestamp == timestamp)
        #expect(records.scan.queueState == (variant == 2 ? .staged : .pending))
        #expect(records.scan.subjectDistanceInMeters == (variant == 0 ? 2 : nil))
        #expect(records.scan.stagedR2Keys == (variant == 0 ? nil : []))
        #expect(records.scan.fieldNotes == "Synthetic field notes")
        #expect(records.scan.inferenceImagePaths == ["synthetic.webp"])
        #expect(records.scan.visualMediaItemsJSON == "[]")
        #expect(records.scan.zoomFactor == 1.5)
        #expect(records.scan.blurScore == 0.5)
        #expect(records.goalHint?.scanId == scanID)
        #expect(records.goalHint?.userFieldTripId == goal.userFieldTripId)
        #expect(records.goalHint?.itemId == goal.itemId)
        #expect(OfflineScanJobMetadataContract.funding(in: records.jobMetadata) == funding)
        #expect(InferenceGenerationMetadataContract.generation(in: records.jobMetadata) == generation)
        let event = records.queuedEvent(jobID: "synthetic-job")
        #expect(event.scanId == scanID)
        #expect(event.jobId == "synthetic-job")
        #expect(event.kind == .queued)
        #expect(event.message == (variant == 0 ? "Queued scan for upload." : "Queued non-visual scan for sync."))
    }
}
