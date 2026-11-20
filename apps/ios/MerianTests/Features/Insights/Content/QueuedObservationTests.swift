import Foundation
import os
import SwiftData
import Testing
@testable import Merian

@MainActor
@Suite("Ordinary queue observation fences", .serialized, .sharedProcessState(.offlineQueueManager))
struct QueuedObservationTests {
    @MainActor
    struct Fixture {
        let owner = UUID()
        let scanID = UUID().uuidString.lowercased()
        let context: ModelContext
        let queue: OfflineQueuedScan
        let job: OfflineJobRecord
        init() throws {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            let container = try ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            context = ModelContext(container); context.autosaveEnabled = false
            let media = CapturedMediaSnapshot(items: [.audio(.documents("synthetic-observation-" + scanID + ".wav"))])
            queue = OfflineQueuedScan(id: scanID, capturedMediaJSON: media.jsonString,
                scanState: .failed, fieldNotes: "Frozen note", queueNeedsAttention: true)
            let funding = ScanFundingReservation(accountId: owner, scanId: scanID, source: .deferredFlash)
            job = OfflineJobRecord(id: "scan-ingestion:" + scanID, kind: .scanIngestion,
                subjectId: scanID, status: .needsAttention,
                metadataJSON: OfflineScanJobMetadataContract.settingFunding(funding, in: nil))
            context.insert(queue); context.insert(job); try context.save()
        }
        func snapshot() throws -> OfflineQueueDurableAuthorityReader.ObservationSnapshot {
            try OfflineQueueDurableAuthorityReader.observation(scanId: scanID, ownerID: owner, from: context.container)
        }
        func read(isCurrent: @escaping @MainActor () -> Bool = { true },
                  send: @escaping NativeReceivedStatusTransport.Send) async throws -> QueuedContentDependencies.Observation {
            try await QueuedContentDependencies.readObservation(scanID: scanID, ownerID: owner,
                container: context.container, isCurrent: isCurrent, send: send)
        }
    }

    @Test func heldReadPreservesQueueJobFundingAndEvents() async throws {
        let f = try Fixture(), before = try f.snapshot()
        var calls = 0
        let result = try await f.read { scan, owner, validate in
            try validate(); calls += 1
            return try ScanObservationTestFixture.response(ownerID: owner, scanID: scan, rowExists: true)
        }
        try result.validate()
        #expect(result.value.rowExists && result.value.originalResult == "unavailable" && calls == 1)
        #expect(try f.snapshot() == before)
        #expect(try f.context.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0)
        #expect(try f.context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(!f.context.hasChanges)
    }

    @Test(arguments: ["audio", "video"], ["absent", "pending", "complete"])
    func reopenedMediaQueueUsesExplicitObservationWithoutRetry(_ kind: String, _ outcome: String) async throws {
        let owner = UUID(), scan = UUID(), scanID = scan.uuidString.lowercased()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("queue-observation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("queue.sqlite")
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let media = CapturedMediaSnapshot(items: kind == "audio"
            ? [.audio(.documents("synthetic-" + scanID + ".wav"))]
            : [.video(.init(video: .documents("synthetic-" + scanID + ".mp4")))])
        let before = try autoreleasepool {
            let seed = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(seed); context.autosaveEnabled = false
            context.insert(OfflineQueuedScan(id: scanID, capturedMediaJSON: media.jsonString,
                scanState: .failed, fieldNotes: "Exact original optional note", queueNeedsAttention: true))
            let funding = ScanFundingReservation(accountId: owner, scanId: scanID, source: .deferredFlash)
            context.insert(OfflineJobRecord(id: "scan-ingestion:" + scanID, kind: .scanIngestion,
                subjectId: scanID, status: .needsAttention,
                metadataJSON: OfflineScanJobMetadataContract.settingFunding(funding, in: nil)))
            try context.save()
            return try OfflineQueueDurableAuthorityReader.observation(scanId: scanID, ownerID: owner, from: seed)
        }
        // A new container reloads actual persisted queue/job/media/funding facts.
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(reopened); context.autosaveEnabled = false
        #expect(try OfflineQueueDurableAuthorityReader.observation(scanId: scanID, ownerID: owner, from: reopened) == before)
        let fixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: owner)
        defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.dispatcher.overridingAuthSessionRefresh = { Issue.record("Observation refreshed Auth"); return true }
        let reply = try ScanObservationTestFixture.response(ownerID: owner, scanID: scan,
            rowExists: outcome != "absent", status: outcome == "absent" ? nil : outcome == "pending" ? "processing" : "complete")
        fixture.mock.register(path: "/check-scan-status") { request in
            calls.withLock { $0 += 1 }
            _ = try ScanObservationTestFixture.response(to: request)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, reply)
        }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        var mutations = 0
        let model = QueuedContentViewModel(dependencies: .init(readObservation: { _, id, current in
            try await QueuedContentDependencies.readObservation(scanID: id, ownerID: owner, container: reopened,
                isCurrent: current, send: { scanID, account, validate in
                    try await transport.perform(scanID: scanID, ownerID: account, validate: validate)
                })
        }, scheduleNextPersistedWake: { _ in mutations += 1 }, retryQueuedScanNow: { _, _ in mutations += 1; return true },
            publishScanLibraryChanged: { mutations += 1 }))
        model.setObservationVisible(true)
        #expect(model.hasObservationAction && model.canCheckObservation && calls.withLock { $0 } == 0)
        let presentation = QueuedRetryPresentation.resolve(queueState: before.state, nextRetryAt: nil,
            errorCode: "server_result", needsAttention: before.needsAttention, canRetryNow: true,
            isOnline: true, now: Date(), canCheckStatus: model.hasObservationAction, openAIPermission: .needsReview)
        #expect(presentation?.action == .checkStatus)
        await model.checkObservation(scanID: scanID, queueManager: .shared,
            ticket: try #require(model.observationTicket()), isCurrent: { true })
        guard case .observed(let response) = model.observationState else { Issue.record("Expected observation"); return }
        #expect(response.originalResult == "unavailable" && response.rowExists == (outcome != "absent"))
        #expect(response.jobStatus?.rawValue == (outcome == "absent" ? nil : outcome == "pending" ? "processing" : "complete"))
        #expect(calls.withLock { $0 } == 1 && mutations == 0)
        #expect(try OfflineQueueDurableAuthorityReader.observation(scanId: scanID, ownerID: owner, from: reopened) == before)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        await model.closeObservationAndWait()
        model.setObservationVisible(true)
        #expect(model.observationState == .idle && calls.withLock { $0 } == 1 && mutations == 0)
        await model.closeObservationAndWait()
    }

    @Test(arguments: ["owner", "funding", "released", "metadata", "native", "marker", "job", "state", "failed", "complete", "cancelled", "external"])
    func refusesMissingForeignOrReservedAuthorityBeforeSend(_ fault: String) async throws {
        let f = try Fixture()
        switch fault {
        case "owner": f.job.metadataJSON = OfflineScanJobMetadataContract.settingFunding(.init(accountId: UUID(), scanId: f.scanID, source: .deferredFlash), in: nil)
        case "funding": f.job.metadataJSON = "{}"
        case "released": f.job.metadataJSON = OfflineScanJobMetadataContract.markingFundingReleased(in: f.job.metadataJSON)
        case "metadata": f.job.metadataJSON = "broken"
        case "native": f.queue.mediaAuthorityRaw = "sharedDirectNativeReceivingV2"
        case "marker": f.job.metadataJSON = "{\"native_receiving_v2\":null}"
        case "job": f.job.kindRaw = "future"
        case "state": f.queue.scanStateRaw = 999
        case "failed": f.queue.queueNeedsAttention = false
        case "complete": f.job.status = .complete
        case "cancelled": f.job.status = .cancelled
        default: f.queue.workKindRaw = "externalImport"
        }
        try f.context.save()
        var calls = 0
        await #expect(throws: (any Error).self) { _ = try await f.read { _, _, _ in calls += 1; return Data() } }
        #expect(calls == 0)
    }

    @Test(arguments: ["account", "note", "media", "metadata", "job", "queue", "cancel"])
    func rejectsChangedAuthorityAfterSuspendedRead(_ fault: String) async throws {
        let f = try Fixture(), entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var current = true
        let task = Task { try await f.read(isCurrent: { current }) { scan, owner, validate in
            try validate(); await entered.open(); await release.wait()
            return try ScanObservationTestFixture.response(ownerID: owner, scanID: scan, rowExists: true)
        } }
        await entered.wait()
        switch fault {
        case "account": current = false
        case "note": f.queue.fieldNotes = "Changed note"
        case "media": f.queue.capturedMediaJSON = "[]"
        case "metadata": f.job.metadataJSON = OfflineScanJobMetadataContract.settingFunding(.init(accountId: f.owner, scanId: f.scanID, source: .deferredFlash, createdAt: Date(timeIntervalSince1970: 1)), in: nil)
        case "job": f.job.status = .cancelled
        case "queue": f.context.delete(f.queue)
        default: task.cancel()
        }
        try f.context.save(); await release.open()
        await #expect(throws: (any Error).self) { _ = try await task.value }
    }

    @Test(arguments: [true, false])
    func actualQueueDeletionWinsBothOrders(deleteFirst: Bool) async throws {
        let f = try Fixture(), manager = OfflineQueueManager.shared, previous = manager.modelContext
        manager.modelContext = f.context
        defer { manager.modelContext = previous }
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var calls = 0
        if deleteFirst { #expect(await manager.deleteQueuedScan(scanId: f.scanID, enumerateBackgroundTasks: { [] })) }
        let task = Task { try await f.read { scan, owner, validate in
            try validate(); calls += 1; await entered.open(); await release.wait()
            return try ScanObservationTestFixture.response(ownerID: owner, scanID: scan, rowExists: true)
        } }
        if !deleteFirst {
            await entered.wait()
            #expect(await manager.deleteQueuedScan(scanId: f.scanID, enumerateBackgroundTasks: { [] }))
        }
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(calls == (deleteFirst ? 0 : 1))
        #expect(try f.context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test(arguments: ["close", "background", "account", "navigation", "cancel"])
    func latePresentationNeverPublishesAndCloseWaitsForRead(_ boundary: String) async throws {
        let f = try Fixture(), entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var current = true, reads = 0, mutations = 0, finished = false
        let model = QueuedContentViewModel(dependencies: .init(readObservation: { _, _, valid in
            reads += 1; await entered.open(); await release.wait(); finished = true
            return try await f.read(isCurrent: valid) { scan, owner, validate in
                try validate(); return try ScanObservationTestFixture.response(ownerID: owner, scanID: scan, rowExists: true)
            }
        }, scheduleNextPersistedWake: { _ in mutations += 1 }, retryQueuedScanNow: { _, _ in mutations += 1; return true },
            publishScanLibraryChanged: { mutations += 1 }))
        model.setObservationVisible(true)
        let ticket = try #require(model.observationTicket())
        let action = Task { await model.checkObservation(scanID: f.scanID, queueManager: .shared, ticket: ticket, isCurrent: { current }) }
        await entered.wait()
        await model.checkObservation(scanID: f.scanID, queueManager: .shared, ticket: ticket, isCurrent: { current })
        #expect(reads == 1 && !model.canCheckObservation)
        if boundary == "account" || boundary == "navigation" { current = false }
        if boundary == "cancel" { action.cancel() }
        model.closeObservation()
        var closed = false
        let close = Task { await model.closeObservationAndWait(); closed = true }
        await Task.yield(); #expect(!closed && !finished)
        await release.open(); await action.value; await close.value
        #expect(closed && finished && model.observationState == .idle && mutations == 0)
    }

    @Test func displayedObservationIsClearedWhenSavedIdentityChanges() async throws {
        let f = try Fixture()
        let model = QueuedContentViewModel(dependencies: .init(readObservation: { _, _, current in
            try await f.read(isCurrent: current) { scan, owner, validate in
                try validate(); return try ScanObservationTestFixture.response(ownerID: owner, scanID: scan, rowExists: true)
            }
        }))
        model.setObservationVisible(true)
        let ticket = try #require(model.observationTicket())
        await model.checkObservation(scanID: f.scanID, queueManager: .shared, ticket: ticket, isCurrent: { true })
        guard case .observed = model.observationState else { Issue.record("Expected literal observation"); return }
        f.job.status = .cancelled; try f.context.save(); model.validateObservation()
        #expect(model.observationState == .unavailable)
    }
    @Test(arguments: ["false", "true", "null", "string", "object"])
    func anyCoexistingReleaseMarkerRefusesPositiveFundingProof(_ kind: String) async throws {
        let f = try Fixture()
        var object = OfflineScanJobMetadataContract.object(from: f.job.metadataJSON)
        let marker: Any
        switch kind {
        case "false": marker = false
        case "true": marker = true
        case "null": marker = NSNull()
        case "string": marker = "true"
        default: marker = ["unexpected": true]
        }
        object["funding_reservation_released"] = marker
        f.job.metadataJSON = OfflineScanJobMetadataContract.json(from: object); try f.context.save()
        #expect(OfflineScanJobMetadataContract.funding(in: f.job.metadataJSON) != nil)
        #expect(OfflineScanJobMetadataContract.unreleasedFundingForObservation(in: f.job.metadataJSON) == nil)
        var calls = 0
        await #expect(throws: (any Error).self) { _ = try await f.read { _, _, _ in calls += 1; return Data() } }
        #expect(calls == 0)
    }

    @Test(arguments: ["close", "background", "close-reopen"])
    func queuedTapCannotStartAfterPresentationEnds(_ boundary: String) async throws {
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var reads = 0
        let model = QueuedContentViewModel(dependencies: .init(readObservation: { _, _, _ in
            reads += 1; throw MerianError.invalidResponse
        }))
        model.setObservationVisible(true)
        let ticket = try #require(model.observationTicket())
        let action = Task {
            await entered.open(); await release.wait()
            await model.checkObservation(scanID: "synthetic", queueManager: .shared, ticket: ticket, isCurrent: { true })
        }
        await entered.wait()
        if boundary == "close" { model.closeObservation() }
        else { model.setObservationVisible(false) }
        if boundary == "close-reopen" { model.setObservationVisible(true) }
        await release.open(); await action.value
        #expect(reads == 0 && model.observationState == .idle)
    }

    @Test func qualifiedUnknownOutcomeOffersCheckAndKeepsPlanConsentActions() {
        func resolve(_ code: String, qualified: Bool = true) -> QueuedRetryPresentation? {
            QueuedRetryPresentation.resolve(queueState: .failed, nextRetryAt: nil,
                errorCode: code, needsAttention: true, canRetryNow: true, isOnline: true,
                now: Date(), canCheckStatus: qualified, openAIPermission: .needsReview)
        }
        for code in ["network", "server_result", "automatic_retry_limit_reached", "unknown"] {
            #expect(resolve(code)?.action == .checkStatus)
            #expect(resolve(code, qualified: false)?.action == .retryNow)
        }
        #expect(resolve("pro_required")?.action == .viewPlans)
        #expect(resolve("ai_openai_consent_required")?.action == .reviewOpenAIPermission)
        #expect(resolve("ai_consent_required")?.action == nil)
    }
}
