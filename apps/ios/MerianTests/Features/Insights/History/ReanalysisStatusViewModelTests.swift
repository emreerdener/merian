import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ReanalysisStatusViewModelTests {
    typealias Page = ObservationReanalysisOperationStatus.Page
    let fixture = ObservationReanalysisRecoveryTests()

    @Test func completionEventRemovesFinishedStatusWithoutPolling() async {
        var completed = false, reads = 0
        let row = ObservationReanalysisOperationStatus.Summary(id: UUID(), sourceAnalysisID: UUID(), phase: .processing)
        let model = ReanalysisStatusViewModel(dependencies: .init(page: { _ in
            reads += 1
            return .init(items: completed ? [] : [row], next: nil)
        }, validate: {}, isCurrent: { true }, close: {}))
        await model.load(); #expect(model.rows.count == 1)
        completed = true; model.refreshForLibraryChange()
        while reads < 2 || model.isBusy { await Task.yield() }
        #expect(model.rows.isEmpty && reads == 2)
        model.close(); model.refreshForLibraryChange()
        await Task.yield(); #expect(reads == 2)
    }

    @Test func oneIdentificationCanOfferStatusWithoutOfferingHistoryOrMutatingWork() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let cloud = fixture.producerFixture.account()
        let session = try IdentificationHistorySession(observation: seed.source.observationID.uuidString, container: seed.container,
            cloud: cloud, currentGeneration: { 1 }, sessionIsCurrent: { _ in true })
        let before = try ObservationReanalysisAdmissionStore.read(seed.pending.draft.identity, container: seed.container, isCurrent: { true })
        #expect(try !ObservationHistoryListingService(cloud: cloud).hasMultiple(observationID: seed.source.observationID.uuidString, container: seed.container))
        #expect(ReanalysisStatusAccess.offersPage(try session.operationStatusPage(after: nil)))
        let model = ReanalysisStatusViewModel(dependencies: session.operationStatusDependencies)
        await model.load()
        #expect(model.rows.map(\.id) == [seed.pending.draft.identity.analysisID])
        #expect(model.rows.first?.sourceAnalysisID == seed.source.analysisID)
        model.close()
        #expect(model.rows.isEmpty && model.isClosed)
        #expect(try ObservationReanalysisAdmissionStore.read(seed.pending.draft.identity, container: seed.container, isCurrent: { true }) == before)
    }

    @Test func emptyCorruptPageStillOffersAndLoadsLaterValidRequests() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let child = UUID()
        let draft = try ObservationReanalysisDraft(identity: .init(observationID: seed.source.observationID, sourceAnalysisID: seed.source.analysisID,
            analysisID: child, ownerID: seed.source.ownerID), evidence: seed.pending.draft.evidence)
        let pending = try ObservationReanalysisPreparationIntent(draft: draft, source: seed.source, action: .submit)
        _ = try ObservationReanalysisPersistence.beginPreparation(pending.verified(source: seed.source), container: seed.container, isCurrent: { true })
        let context = ModelContext(seed.container), rows = try context.fetch(FetchDescriptor<OfflineQueuedScan>(sortBy: [SortDescriptor(\.id, comparator: .lexical)]))
        #expect(rows[0].id < rows[1].id)
        let savedJob = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: rows[0].id))
        let job = try #require(savedJob); job.metadataJSON = "{}"; try context.save()
        let reader = ObservationReanalysisOperationStatus(account: fixture.producerFixture.account())
        var current = true
        let dependencies = ReanalysisStatusDependencies(page: { cursor in
            try reader.page(observationID: seed.source.observationID, ownerID: seed.source.ownerID, after: cursor, limit: 1,
                container: seed.container, isCurrent: { current })
        }, validate: {}, isCurrent: { current }, close: { current = false })
        let first = try await dependencies.page(nil)
        #expect(first.items.isEmpty && first.next != nil && ReanalysisStatusAccess.offersPage(first))
        let direct = try await dependencies.page(first.next)
        #expect(direct.items.count == 1 && direct.next == nil)
        let model = ReanalysisStatusViewModel(dependencies: dependencies)
        await model.load(); #expect(model.rows.isEmpty && model.next != nil)
        await model.load(more: true)
        #expect(model.message == nil && !model.isClosed && !model.isBusy)
        #expect(model.rows.count == 1 && model.next == nil)
        let displayed = model.rows
        await model.load(more: true); #expect(model.rows == displayed)
        await model.load(); #expect(model.rows.isEmpty && model.next != nil)
        #expect(!ReanalysisStatusAccess.offersPage(.init(items: [], next: nil)))
    }

    @Test(arguments: ["closed", "account", "presentation", "parent"])
    func latePageCannotRestorePrivateValuesAfterInvalidation(_ change: String) async throws {
        var current = true, presented = true, parent = true, closes = 0
        var resume: CheckedContinuation<Page, Never>?
        let row = ObservationReanalysisOperationStatus.Summary(id: UUID(), sourceAnalysisID: UUID(), phase: .consentRequired)
        let dependencies = ReanalysisStatusDependencies(page: { _ in await withCheckedContinuation { resume = $0 } },
            validate: { if !parent { throw ObservationHistoryError.deleted } },
            isCurrent: { current }, close: { closes += 1 })
        let model = ReanalysisStatusViewModel(dependencies: dependencies, isPresented: { presented })
        let task = Task { await model.load() }
        while resume == nil { await Task.yield() }
        switch change {
        case "closed": model.close()
        case "account": current = false
        case "presentation": presented = false
        default: parent = false
        }
        resume?.resume(returning: .init(items: [row], next: nil)); await task.value
        #expect(model.isClosed && model.rows.isEmpty && model.next == nil && !model.isBusy && closes == 1)
        model.close(); #expect(closes == 1)
    }

    @Test(arguments: ["account", "generation", "parent", "closed"])
    func preparedSessionRevalidatesItsOriginalOwnerAndParent(_ change: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        var current = true, generation: UInt64 = 1
        let session = try IdentificationHistorySession(observation: seed.source.observationID.uuidString, container: seed.container,
            cloud: fixture.producerFixture.account(), currentGeneration: { generation }, sessionIsCurrent: { _ in current })
        let model = ReanalysisStatusViewModel(dependencies: session.operationStatusDependencies)
        await model.load(); #expect(model.rows.count == 1)
        switch change {
        case "account": current = false
        case "generation": generation += 1
        case "closed": session.close()
        default:
            let context = ModelContext(seed.container)
            context.insert(PendingCloudDeletionTask(scanId: seed.source.observationID.uuidString)); try context.save()
        }
        #expect(!model.validate() && model.isClosed && model.rows.isEmpty)
    }

    @Test(arguments: [false, true])
    func actualShellDismissalOrScanSwitchInvalidatesOriginalStatus(switchScan: Bool) async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let first = LocalScanRecord(id: UUID().uuidString, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", isBiological: false)
        let second = LocalScanRecord(id: UUID().uuidString, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", isBiological: false)
        context.insert(first); context.insert(second); try context.save()
        let shell = InsightSheetViewModel(), engine = InferenceEngine()
        defer { engine.cancelHistoricHydration() }
        shell.inferenceEngine = engine
        shell.beginPresentationSession()
        #expect(shell.bindPresentedScan(scanId: first.id, modelContext: context, inferenceEngine: engine))
        let generation = shell.scanBoundActionGeneration
        #expect(shell.isPresentingLocalRecord(scanId: first.id, generation: generation))
        let row = ObservationReanalysisOperationStatus.Summary(id: UUID(), sourceAnalysisID: UUID(), phase: .waitingToStart)
        let model = ReanalysisStatusViewModel(dependencies: .init(page: { _ in .init(items: [row], next: nil) },
            validate: {}, isCurrent: { true }, close: {}), isPresented: {
                shell.isPresentingLocalRecord(scanId: first.id, generation: generation)
            })
        await model.load(); #expect(model.rows == [row])
        if switchScan {
            #expect(shell.bindPresentedScan(scanId: second.id, modelContext: context, inferenceEngine: engine))
            #expect(shell.bindPresentedScan(scanId: first.id, modelContext: context, inferenceEngine: engine))
        } else { shell.endPresentationSession() }
        #expect(!model.validate() && model.rows.isEmpty && model.isClosed)
    }

    @Test func readFailureCanRefreshWithoutInventingAnOperation() async {
        var reads = 0
        let row = ObservationReanalysisOperationStatus.Summary(id: UUID(), sourceAnalysisID: UUID(), phase: .reconciliationRequired)
        let model = ReanalysisStatusViewModel(dependencies: .init(page: { _ in
            reads += 1
            if reads == 1 { throw ObservationHistoryError.unavailable }
            return .init(items: [row], next: nil)
        }, validate: {}, isCurrent: { true }, close: {}))
        await model.load(); #expect(model.message != nil && !model.isClosed && model.rows.isEmpty)
        await model.load(); #expect(model.message == nil && model.rows == [row] && reads == 2)
    }
    @Test func ambiguousRetirementRetryRetainsFinalTapIdentity() async {
        let row = ObservationReanalysisOperationStatus.Summary(id: UUID(), sourceAnalysisID: UUID(), phase: .processing, retirement: .requestStop)
        var operations: [UUID] = []
        let model = ReanalysisStatusViewModel(dependencies: .init(page: { _ in .init(items: [row], next: nil) },
            validate: {}, isCurrent: { true }, close: {}, retire: { target, operation in
                #expect(target == row); operations.append(operation)
                throw ObservationHistoryError.unavailable
            }))
        await model.load()
        model.requestRetirement(row)
        while model.isBusy { await Task.yield() }
        #expect(operations.count == 1 && model.message != nil)
        model.requestRetirement(row)
        while model.isBusy { await Task.yield() }
        #expect(operations.count == 2 && operations[0] == operations[1])
    }

    @Test func closingPresentationCannotRestoreLateRetirementValues() async {
        let row = ObservationReanalysisOperationStatus.Summary(id: UUID(), sourceAnalysisID: UUID(), phase: .stopNeedsChecking, retirement: .checkSameStop)
        var resume: CheckedContinuation<ObservationReanalysisRetirementAction.Outcome, Never>?
        let model = ReanalysisStatusViewModel(dependencies: .init(page: { _ in .init(items: [row], next: nil) },
            validate: {}, isCurrent: { true }, close: {}, retire: { _, _ in
                await withCheckedContinuation { resume = $0 }
            }))
        await model.load(); model.requestRetirement(row)
        while resume == nil { await Task.yield() }
        model.close(); resume?.resume(returning: .saved)
        await Task.yield()
        #expect(model.isClosed && model.rows.isEmpty && model.message == nil && !model.isBusy)
    }

    @Test func qualifiedPassExitExposesHeldRecoveryWithoutMutationOrPolling() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let manager = OfflineQueueManager.shared, previous = manager.modelContext, context = ModelContext(seed.container)
        manager.modelContext = context; defer { manager.modelContext = previous }
        var held = false, reads = 0, mutations = 0
        let row = ObservationReanalysisOperationStatus.Summary(id: UUID(), sourceAnalysisID: UUID(), phase: .stopping)
        let model = ReanalysisStatusViewModel(dependencies: .init(page: { _ in
            reads += 1
            return .init(items: [held ? .init(id: row.id, sourceAnalysisID: row.sourceAnalysisID,
                phase: .stopNeedsChecking, retirement: .checkSameStop) : row], next: nil)
        }, validate: {}, isCurrent: { true }, close: {}, generation: { manager.reanalysisExecutionGeneration },
        retire: { _, _ in mutations += 1; return .saved }))
        await model.load(); let before = model.deliveryGeneration
        manager.reanalysisExecutionDidFinish(ownerID: seed.source.ownerID, context: context, currentOwnerID: UUID())
        #expect(model.deliveryGeneration == before && reads == 1)
        held = true
        manager.reanalysisExecutionDidFinish(ownerID: seed.source.ownerID, context: context, currentOwnerID: seed.source.ownerID)
        #expect(model.deliveryGeneration == before &+ 1)
        // The sheet's onChange performs this read-only refresh; no scanLibraryChanged is needed.
        model.refreshForLibraryChange()
        while reads < 2 || model.isBusy { await Task.yield() }
        #expect(model.rows.first?.phase == .stopNeedsChecking && model.rows.first?.retirement == .checkSameStop)
        #expect(reads == 2 && mutations == 0)
        model.close()
        manager.reanalysisExecutionDidFinish(ownerID: seed.source.ownerID, context: ModelContext(seed.container), currentOwnerID: seed.source.ownerID)
        #expect(model.deliveryGeneration == before &+ 1)
    }

}
