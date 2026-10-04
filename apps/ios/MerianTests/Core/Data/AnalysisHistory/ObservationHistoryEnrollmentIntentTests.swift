import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationHistoryEnrollmentIntentTests {
    let support = ObservationHistoryEnrollmentTests()
    var observation: UUID { UUID(uuidString: support.support.support.observation)! }
    var owner: UUID { support.support.support.owner }

    @Test func lostResponseSurvivesStoreReopenAndReplayReusesIntent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("enrollment.sqlite"))
        var container: ModelContainer? = try ModelContainer(for: schema, configurations: [configuration])
        do {
            let context = ModelContext(container!)
            let scan = LocalScanRecord(id: observation.uuidString.lowercased(), speciesId: "", scientificName: "Saved fixture", commonName: "Saved fixture")
            scan.confidenceScore = 0.75; scan.aiReasoning = "Synthetic saved identification."
            scan.inferenceTier = "flash"; scan.candidatesData = Data("{}".utf8)
            context.insert(scan); try context.save()
        }
        await #expect(throws: ObservationHistoryError.unavailable) {
            try await support.run(support.service(duringEnroll: { throw ObservationHistoryError.unavailable }), container!)
        }
        let intent = try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: owner, context: ModelContext(container!))
        container = nil
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        #expect(try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: owner, context: ModelContext(reopened)) == intent)
        _ = try await support.run(support.service(), reopened)
        let verify = ModelContext(reopened)
        #expect(try !ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: verify))
        #expect(try verify.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
    }

    @Test func failuresAfterDispatchRetainHoldAndFinalSaveRollbackRestoresIt() async throws {
        let container = try support.container()
        var service = support.service()
        var saves = 0
        service.save = { context in
            saves += 1
            if saves == 2 { throw ObservationHistoryError.unavailable }
            try context.save()
        }
        await #expect(throws: ObservationHistoryError.unavailable) { try await support.run(service, container) }
        try support.expectUnenrolled(container)
        #expect(try ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: ModelContext(container)))
        _ = try await support.run(support.service(), container)
        #expect(try !ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: ModelContext(container)))
    }

    @Test func stageSaveFailureCannotDispatchOrLeavePartialHold() async throws {
        let container = try support.container()
        var called = false
        var service = support.service(duringEnroll: { called = true })
        service.save = { _ in throw ObservationHistoryError.unavailable }
        await #expect(throws: ObservationHistoryError.unavailable) { try await support.run(service, container) }
        #expect(!called)
        #expect(try !ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: ModelContext(container)))
        try support.expectUnenrolled(container)
    }

    @Test func wrongOwnerMalformedAndTerminalIntentsNeverReopenOrDispatch() async throws {
        for corruption in 0..<6 {
            let container = try support.container(), context = ModelContext(container)
            _ = try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: corruption == 0 ? UUID() : owner, context: context)
            let job = try #require(try context.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.jobID(observation.uuidString)))
            switch corruption {
            case 1: job.metadataJSON = "{}"
            case 2: job.status = .complete
            case 3: job.subjectId = UUID().uuidString
            case 4: job.kind = .scanIngestion
            case 5: job.metadataJSON = String(repeating: "x", count: 4097)
            default: break
            }
            try context.save()
            var called = false
            await #expect(throws: (any Error).self) { try await support.run(support.service(duringEnroll: { called = true }), container) }
            #expect(!called)
            #expect(try ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: ModelContext(container)))
            try support.expectUnenrolled(container)
        }
    }

    @Test func changedIntentGenerationCannotBeAcknowledgedByOlderResponse() async throws {
        let container = try support.container()
        let service = support.service(duringRead: {
            let context = ModelContext(container)
            context.delete(try #require(try context.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.jobID(observation.uuidString))))
            try context.save()
            _ = try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: owner, context: context)
            try context.save()
        })
        await #expect(throws: ObservationHistoryEnrollmentIntent.IntegrityError.self) { try await support.run(service, container) }
        try support.expectUnenrolled(container)
        #expect(try ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: ModelContext(container)))
    }

    @Test func holdNeverCreatesWakeEvenWhenStatusAndDeadlineAreDamaged() throws {
        let container = try support.container(), context = ModelContext(container)
        _ = try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: owner, context: context)
        try context.save()
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        manager.modelContext = context
        defer { manager.modelContext = previous }
        #expect(OfflineJobScheduler.shared.nextPersistedWakeDate(using: manager) == nil)
        let job = try #require(try context.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.jobID(observation.uuidString)))
        job.status = .pending; job.nextRunAt = .distantPast; try context.save()
        #expect(OfflineJobScheduler.shared.nextPersistedWakeDate(using: manager) == nil)
    }
}
