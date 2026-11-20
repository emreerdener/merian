import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ReanalysisRecoveryCheckingIntegrationTests {
    @Test(arguments: ["close", "background", "deleted"])
    func photoScreenDepartureKeepsExactLateCompletion(departure: String) async throws {
        let fixture = ReanalysisHeldOutcomeTests(), execution = fixture.execution
        let container = try execution.fixture.fixture.container(), saved = try fixture.held(container)
        let identity = saved.intent.identity, cloud = ReanalysisOperationStatusTests().preparation.producerFixture.account()
        let owner = ObservationReanalysisPreparationOwner()
        var reply: CheckedContinuation<Data?, Never>?, notifications = 0
        let session = try IdentificationHistorySession(observation: identity.observationID.uuidString.lowercased(), container: container,
            cloud: cloud, currentGeneration: { 1 }, sessionIsCurrent: { _ in true })
        let dependencies = session.operationStatusDependencies(retirement: .init(ownership: owner,
            fetch: { _, _, _ in Issue.record("Recovery requested retirement"); throw MerianError.invalidResponse }, wake: {},
            recover: { intent, validate in
                try validate(); #expect(intent == saved.intent)
                let data = await withCheckedContinuation { reply = $0 }
                try validate(); return data
            }, completionAttempted: { notifications += 1 }))
        let model = ReanalysisStatusViewModel(dependencies: dependencies)
        await model.load()
        #expect(model.message == nil && !model.isClosed)
        model.checkOutcome(try #require(model.rows.first))
        while reply == nil { await Task.yield() }
        let checker = try #require(model.recovery)
        #expect(checker.state == .checking && owner.contains(identity.analysisID))
        if departure == "close" { model.close() } else { model.setVisible(false) }
        let paused = try ObservationReanalysisRecoveryPresentationStore.read(identity, container: container, isCurrent: { true })
        #expect(paused.value.activeReservationID == nil && paused.value.chargedMilliseconds < 30_000)
        #expect(try ObservationReanalysisExecutionStore.read(identity, container: container, isCurrent: { true }) == saved)
        reply?.resume(returning: try execution.result())
        while checker.isRunning { await Task.yield() }
        #expect(notifications == 1 && !owner.contains(identity.analysisID) && checker.state != .recovered)
        try assertCompleted(identity, container)
        if departure == "deleted" {
            let context = ModelContext(container)
            context.delete(try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)); try context.save()
            model.setVisible(true)
            #expect(model.isClosed && model.rows.isEmpty && model.recoveryMessage == nil && checker.state == .unavailable)
        } else if departure == "background" {
            model.setVisible(true)
            while !model.rows.isEmpty || model.isBusy { await Task.yield() }
            #expect(checker.state == .recovered && model.rows.isEmpty && notifications == 1)
        }
    }

    @Test(arguments: ["close", "background", "deleted"])
    func audioConsumedCheckRetainsOwnerAndSidecarAcrossScreenDeparture(departure: String) async throws {
        let fixture = ObservationAudioExecutionServiceTests(), seed = try await fixture.fixture.ready()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try fixture.entry(seed, mode: "consumed"), identity = seed.preparation.identity
        let boundary = try ObservationAudioExecutionServiceTests.Boundary(seed), base = boundary.service.dependencies
        var reply: CheckedContinuation<Void, Never>?
        let service = ObservationAudioExecutionService(dependencies: .init(read: base.read, upload: base.upload,
            authorize: base.authorize, analyze: base.analyze, outcome: { claim, before, after in
                try before(); await withCheckedContinuation { reply = $0 }; try after()
                #expect(claim.snapshot.work.intent == saved.work.intent)
                return boundary.bytes
            }))
        let owner = ObservationAudioExecutionOwner(), cloud = fixture.fixture.fixture.fixture.account()
        let access = CaptureAudioReanalysisAccess.prepared(account: cloud, ownership: .init(),
            configuration: .init(authorize: { _, _ in Issue.record("Recovery requested authorization"); throw MerianError.invalidResponse },
                start: { _, _, _, _ in Issue.record("Recovery used broad resume"); return .unavailable },
                recover: { key, proof, container, _ in
                    #expect(key.snapshot.work.consumedAttempt != nil)
                    let admission = owner.start(key, account: cloud, isCurrent: { true }, operation: { scope in
                        #expect(await service.run(key.snapshot, proof: proof, container: container, scope: scope, cleanup: boundary.cleanup) == .completed)
                    }, didFinish: {})
                    #expect(admission == .started)
                    let exit = try #require(owner.captureActualExit(key)); await exit.wait()
                    return try ObservationReanalysisRecoveredResult.contains(identity, container: container, isCurrent: { true },
                        decode: { try ObservationReanalysisResult.decode($0, matching: saved.work.intent.request) })
                }), currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.root })
        let status = CaptureAudioStatusAccess.prepared(account: cloud, owner: .init(), reader: .init(),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container })
        let model = CaptureAudioSavedRequestsModel(status: try status.open(seed.source.ownerID, identity.observationID, seed.container),
            openResume: { try access.openResume($0, seed.container) }, isPresented: { true })
        model.start(); while model.isBusy { await Task.yield() }
        model.select(try #require(model.rows.first)); model.continueSelected()
        let checker = try #require(model.recovery)
        while reply == nil { await Task.yield() }
        if departure == "close" { model.close() } else { model.setVisible(false) }
        #expect(owner.isRunning)
        let paused = try ObservationReanalysisRecoveryPresentationStore.read(identity, container: seed.container, isCurrent: { true })
        #expect(paused.value.activeReservationID == nil && paused.value.chargedMilliseconds < 30_000)
        reply?.resume()
        while checker.isRunning { await Task.yield() }
        #expect(!owner.isRunning && checker.state != .recovered && boundary.events == ["cleanup"])
        try assertCompleted(identity, seed.container)
        if departure == "deleted" {
            let context = ModelContext(seed.container)
            context.delete(try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)); try context.save()
            model.setVisible(true)
            #expect(model.isClosed && model.rows.isEmpty && model.recoveryMessage == nil && checker.state == .unavailable)
        } else if departure == "background" {
            model.setVisible(true)
            while model.isBusy { await Task.yield() }
            #expect(checker.state == .recovered && model.rows.isEmpty)
        }
    }

    @Test(arguments: ["close", "background", "deleted"])
    func videoConsumedCheckRetainsOwnerAndSidecarAcrossScreenDeparture(departure: String) async throws {
        let fixture = ObservationVideoExecutionServiceTests(), (seed, saved) = try await fixture.seed("held-consumed")
        defer { seed.remove() }
        let identity = seed.preparation.identity
        let boundary = try ObservationVideoExecutionServiceTests.Boundary(seed), base = boundary.service.dependencies
        var reply: CheckedContinuation<Void, Never>?
        let service = ObservationVideoExecutionService(dependencies: .init(authorize: base.authorize, analyze: base.analyze,
            outcome: { snapshot, before, after in
                try before(); await withCheckedContinuation { reply = $0 }; try after()
                #expect(snapshot.work.request.body == saved.work.request.body)
                return boundary.bytes
            }))
        let owner = ObservationVideoExecutionOwner(), cloud = ObservationReanalysisProducerTests().account()
        let access = CaptureVideoResumeAccess.prepared(account: cloud, ownership: .init(),
            configuration: .init(start: { _, _, _, _, _ in Issue.record("Recovery used broad resume"); return .unavailable },
                recover: { key, proof, container, _ in
                    #expect(key.snapshot.work.consumed)
                    let admission = owner.start(key, account: cloud, isCurrent: { true }, operation: { scope in
                        #expect(await service.run(key.snapshot, proof: proof, container: container, scope: scope, cleanup: boundary.cleanup) == .completed)
                    }, didFinish: {})
                    #expect(admission == .started)
                    let exit = try #require(owner.captureActualExit(key)); await exit.wait()
                    return try ObservationReanalysisRecoveredResult.contains(identity, container: container, isCurrent: { true },
                        decode: { try ObservationReanalysisResult.decode($0, matching: saved.work.request) })
                }), currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.root })
        let status = CaptureVideoStatusAccess.prepared(account: cloud, owner: .init(), reader: .init(),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container })
        let model = CaptureVideoSavedRequestsModel(status: try status.open(seed.source.ownerID, identity.observationID, seed.container),
            openResume: { try access.openResume($0, seed.container) }, isPresented: { true })
        model.start(); while model.isBusy { await Task.yield() }
        model.select(try #require(model.rows.first)); model.continueSelected()
        let checker = try #require(model.recovery)
        while reply == nil { await Task.yield() }
        if departure == "close" { model.close() } else { model.setVisible(false) }
        #expect(owner.isRunning)
        let paused = try ObservationReanalysisRecoveryPresentationStore.read(identity, container: seed.container, isCurrent: { true })
        #expect(paused.value.activeReservationID == nil && paused.value.chargedMilliseconds < 30_000)
        reply?.resume()
        while checker.isRunning { await Task.yield() }
        #expect(!owner.isRunning && checker.state != .recovered && boundary.events == ["cleanup"])
        try assertCompleted(identity, seed.container)
        if departure == "deleted" {
            let context = ModelContext(seed.container)
            context.delete(try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)); try context.save()
            model.setVisible(true)
            #expect(model.isClosed && model.rows.isEmpty && model.recoveryMessage == nil && checker.state == .unavailable)
        } else if departure == "background" {
            model.setVisible(true)
            while model.isBusy { await Task.yield() }
            #expect(checker.state == .recovered && model.rows.isEmpty)
        }
    }

    @Test func audioUnconsumedWorkCannotUseExactOutcomeAction() async throws {
        let fixture = ObservationAudioExecutionStoreTests(), seed = try await fixture.ready()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try fixture.bind(seed)
        let access = CaptureAudioReanalysisAccess.prepared(account: fixture.fixture.fixture.account(), ownership: .init(),
            configuration: .init(authorize: { _, _ in Issue.record("Unexpected authorization"); throw MerianError.invalidResponse },
                start: { _, _, _, _ in Issue.record("Unexpected broad resume"); return .unavailable },
                recover: { _, _, _, _ in Issue.record("Unconsumed outcome check"); return false }),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.root })
        let recovery = try #require(access.openResume(seed.preparation.identity, seed.container).recovery)
        await #expect(throws: (any Error).self) { try await recovery.reserve() }
        await #expect(throws: (any Error).self) { try await recovery.check() }
        #expect(try ObservationAudioExecutionStore.read(seed.proof, container: seed.container, isCurrent: { true }) == saved)
        #expect(try ObservationReanalysisRecoveryPresentationStore.read(seed.preparation.identity,
            container: seed.container, isCurrent: { true }).bytes == nil)
    }

    @Test func videoUnconsumedWorkCannotUseExactOutcomeAction() async throws {
        let (seed, saved) = try await ObservationVideoExecutionServiceTests().seed("idle")
        defer { seed.remove() }
        let access = CaptureVideoResumeAccess.prepared(account: ObservationReanalysisProducerTests().account(), ownership: .init(),
            configuration: .init(start: { _, _, _, _, _ in Issue.record("Unexpected broad resume"); return .unavailable },
                recover: { _, _, _, _ in Issue.record("Unconsumed outcome check"); return false }),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true },
            containerIsCurrent: { $0 === seed.container }, documents: { seed.root })
        let recovery = try #require(access.openResume(seed.preparation.identity, seed.container).recovery)
        await #expect(throws: (any Error).self) { try await recovery.reserve() }
        await #expect(throws: (any Error).self) { try await recovery.check() }
        #expect(try ObservationVideoExecutionStore.read(proof: seed.proof, container: seed.container, isCurrent: { true }) == saved)
        #expect(try ObservationReanalysisRecoveryPresentationStore.read(seed.preparation.identity,
            container: seed.container, isCurrent: { true }).bytes == nil)
    }

    private func assertCompleted(_ identity: OfflineQueueWork.Reanalysis, _ container: ModelContainer) throws {
        let context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == identity.sourceAnalysisID.uuidString.lowercased())
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: identity.analysisID.uuidString.lowercased())) == nil)
        #expect(try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(identity.analysisID)) != nil)
    }
}
