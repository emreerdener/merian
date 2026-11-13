import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisRecoveryPresentationStoreTests {
    typealias Store = ObservationReanalysisRecoveryPresentationStore
    let fixture = ObservationReanalysisPersistenceTests()

    func staged() throws -> (ModelContainer, OfflineQueueWork.Reanalysis) {
        let container = try fixture.fixture.container()
        return (container, try fixture.stage(container).intent.identity)
    }
    func reserve(_ snapshot: Store.Snapshot, _ container: ModelContainer,
                 save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Store.Interval {
        try Store.reserve(snapshot, container: container, isCurrent: { true }, validateOperation: {
            _ = try ObservationReanalysisExecutionStore.read(snapshot.identity, container: container, isCurrent: { true })
        }, canReserveBytes: { $0 == 512 }, save: save)
    }

    @Test func repeatedVisibleIntervalsChargeOnceAndLeaveExecutionUnchanged() throws {
        let (container, identity) = try staged()
        let execution = try ObservationReanalysisExecutionStore.read(identity, container: container, isCurrent: { true })
        let (_, _, originalJob) = try fixture.stored(container)
        let metadata = originalJob.metadataJSON
        for index in 0..<3 {
            let before = try Store.read(identity, container: container, isCurrent: { true })
            #expect(before.value.chargedMilliseconds == index * 1_001)
            let live = try reserve(before, container)
            #expect(try Store.read(identity, container: container, isCurrent: { true }).value.needsAttention)
            let after = try Store.settle(live, elapsed: .microseconds(1_000_001), container: container, isCurrent: { true })
            #expect(after.chargedMilliseconds == (index + 1) * 1_001)
            let (_, row, job) = try fixture.stored(container)
            #expect(job.approximateBytes == 512 && job.metadataJSON == metadata)
            #expect(row.recoveryPresentationData?.count ?? 0 <= 512)
            #expect(try ObservationReanalysisExecutionStore.read(identity, container: container, isCurrent: { true }) == execution)
        }
    }

    @Test func staleReservationCannotRefundOrReplaceAnotherInterval() throws {
        let (container, identity) = try staged()
        let original = try Store.read(identity, container: container, isCurrent: { true })
        let first = try reserve(original, container)
        #expect(throws: (any Error).self) { try reserve(original, container) }
        _ = try Store.settle(first, elapsed: .seconds(2), container: container, isCurrent: { true })
        let second = try reserve(Store.read(identity, container: container, isCurrent: { true }), container)
        #expect(throws: (any Error).self) {
            try Store.settle(first, elapsed: .zero, container: container, isCurrent: { true })
        }
        #expect(try Store.read(identity, container: container, isCurrent: { true }).value == second.reservation.reserved)
    }

    @Test(arguments: [false, true])
    func reserveSaveFailureNeverManufacturesAnotherBudget(committed: Bool) throws {
        let (container, identity) = try staged()
        let before = try Store.read(identity, container: container, isCurrent: { true })
        #expect(throws: (any Error).self) {
            try reserve(before, container, save: { context in
                if committed { try context.save() }
                throw CocoaError(.fileWriteUnknown)
            })
        }
        let fresh = try Store.read(identity, container: container, isCurrent: { true })
        let (_, _, job) = try fixture.stored(container)
        #expect(job.approximateBytes == (committed ? 512 : 0))
        #expect(fresh.value.needsAttention == committed)
        if committed {
            #expect(fresh.value.chargedMilliseconds == 30_000)
            #expect(throws: (any Error).self) { try reserve(fresh, container) }
        } else { #expect(fresh == before) }
    }

    @Test(arguments: [false, true])
    func settlementAcknowledgementLossCannotRefundTwice(committed: Bool) throws {
        let (container, identity) = try staged()
        let interval = try reserve(Store.read(identity, container: container, isCurrent: { true }), container)
        #expect(throws: (any Error).self) {
            try Store.settle(interval, elapsed: .seconds(4), container: container, isCurrent: { true }, save: { context in
                if committed { try context.save() }
                throw CocoaError(.fileWriteUnknown)
            })
        }
        let fresh = try Store.read(identity, container: container, isCurrent: { true })
        #expect(fresh.value.chargedMilliseconds == (committed ? 4_000 : 30_000))
        if committed {
            #expect(throws: (any Error).self) {
                try Store.settle(interval, elapsed: .zero, container: container, isCurrent: { true })
            }
        }
        #expect(try fixture.stored(container).2.approximateBytes == 512)
    }

    @Test(arguments: ["account", "capacity", "operation", "nonzero-charge", "negative-charge", "overflow-charge", "wrong-work", "wrong-job", "malformed", "foreign-sidecar", "deletion"])
    func invalidAdmissionDoesNotChangeStoredBytes(reason: String) throws {
        let (container, identity) = try staged()
        let (context, row, job) = try fixture.stored(container)
        switch reason {
        case "nonzero-charge": job.approximateBytes = 1
        case "negative-charge": job.approximateBytes = -1
        case "overflow-charge": job.approximateBytes = Int64.max
        case "wrong-work": row.reanalysisOwnerAccountID = UUID().uuidString.lowercased()
        case "wrong-job": job.kind = .scanIngestion
        case "malformed": row.recoveryPresentationData = Data("bad".utf8); job.approximateBytes = 512
        case "foreign-sidecar":
            row.recoveryPresentationData = try AnalysisRecoveryPresentation.initial(for: .init(ownerID: UUID(), observationID: identity.observationID, operationID: identity.analysisID)).encoded()
            job.approximateBytes = 512
        case "deletion": context.insert(PendingCloudDeletionTask(scanId: identity.observationID.uuidString.lowercased()))
        default: break
        }
        try context.save()
        let oldBytes = row.recoveryPresentationData, oldCharge = job.approximateBytes
        #expect(throws: (any Error).self) {
            let before = try Store.read(identity, container: container, isCurrent: { reason != "account" })
            return try Store.reserve(before, container: container, isCurrent: { true }, validateOperation: {
                if reason == "operation" { throw CocoaError(.fileReadUnknown) }
            }, canReserveBytes: { _ in reason != "capacity" })
        }
        let (_, freshRow, freshJob) = try fixture.stored(container)
        #expect(freshRow.recoveryPresentationData == oldBytes && freshJob.approximateBytes == oldCharge)
    }

    @Test func removalWinsOverLatePauseAndDoesNotRecreateRows() throws {
        let (container, identity) = try staged()
        let interval = try reserve(Store.read(identity, container: container, isCurrent: { true }), container)
        let context = ModelContext(container)
        _ = try ObservationReanalysisErasure.removeChildren(of: identity.observationID.uuidString.lowercased(), context: context)
        try context.save()
        #expect(throws: (any Error).self) {
            try Store.settle(interval, elapsed: .seconds(1), container: container, isCurrent: { true })
        }
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try fresh.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: identity.analysisID.uuidString.lowercased())) == nil)
        #expect(try fresh.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(identity.analysisID)) != nil)
    }

    @Test func diskReopenKeepsUnownedReservationFullySpent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite"), identity = try fixture.intent().identity
        do {
            let container = try fixture.fixture.container(url: url)
            _ = try fixture.stage(container)
            _ = try reserve(Store.read(identity, container: container, isCurrent: { true }), container)
        }
        let reopened = try fixture.fixture.container(url: url, seed: false)
        let fresh = try Store.read(identity, container: reopened, isCurrent: { true })
        #expect(fresh.value.needsAttention && fresh.value.chargedMilliseconds == 30_000)
        #expect(throws: (any Error).self) { try reserve(fresh, reopened) }
        #expect(try fixture.stored(reopened).2.approximateBytes == 512)
    }

    @Test(arguments: [false, true])
    func exhaustionByTimeOrTransitionsNeverReopensSpinnerBudget(byTime: Bool) throws {
        let (container, identity) = try staged()
        for _ in 0..<(byTime ? 1 : 30) {
            let live = try reserve(Store.read(identity, container: container, isCurrent: { true }), container)
            _ = try Store.settle(live, elapsed: byTime ? .seconds(30) : .zero, container: container, isCurrent: { true })
        }
        let exhausted = try Store.read(identity, container: container, isCurrent: { true })
        #expect(exhausted.value.needsAttention)
        #expect(throws: (any Error).self) { try reserve(exhausted, container) }
        #expect(try fixture.stored(container).2.approximateBytes == 512)
    }
}
