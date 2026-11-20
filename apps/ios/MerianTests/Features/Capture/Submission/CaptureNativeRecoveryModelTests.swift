import Foundation
import Testing
import SwiftData
import UIKit
@testable import Merian

@Suite("Native Capture local holding presentation", .serialized)
@MainActor
struct CaptureNativeRecoveryModelTests {
    @Test(arguments: [0, 1, 2])
    func discoveryNeverSelectsOrAuthorizesAnOperation(_ count: Int) async {
        let candidates = (0..<count).map { _ in candidate() }
        let ownerID = candidates.first?.profile.ownerID ?? Self.ownerID
        var reads = 0
        let model = CaptureNativeRecoveryModel(ownerID: ownerID, isCurrent: { true }) {
            reads += 1; return candidates
        }
        await model.open()
        #expect(model.state == .unselected(candidates))
        await model.select(candidate()) // unlisted identity cannot be selected
        #expect(reads == 1)
        if let selected = candidates.last {
            await model.select(selected)
            #expect(model.state == .holding(selected) && reads == 2)
        }
        model.close()
        #expect(model.state == .closed)
    }

    @Test(arguments: ["missing", "changed", "foreign", "profile"])
    func exactRefreshRejectsChangedDurableIdentity(_ change: String) async {
        let original = candidate()
        var returned = [original]
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { true }) { returned }
        await model.open()
        await model.select(original)
        #expect(model.state == .holding(original))
        switch change {
        case "missing": returned = []
        case "foreign": returned = [candidate(ownerID: UUID())]
        case "profile": returned = [candidate(inventoryID: UUID())]
        default: returned = [candidate(packageID: original.packageID)]
        }
        await model.refresh()
        #expect(model.state == .unavailable)
    }

    @Test(arguments: ["account", "close", "cancel"])
    func lateReadCannotRestoreInvalidPresentation(_ change: String) async {
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var current = true, reads = 0
        let value = candidate()
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { current }) {
            reads += 1; await entered.open(); await release.wait(); return [value]
        }
        let task = Task { await model.open() }
        await entered.wait()
        await model.open()
        #expect(reads == 1)
        switch change {
        case "account": current = false
        case "close": model.close()
        default: task.cancel()
        }
        await release.open(); await task.value
        #expect(model.state == (change == "close" ? .closed : .unavailable))
    }


    @Test func closeDuringDiscoveryCannotAttachLateLifetime() async throws {
        let drain = SharedMediaNativeOriginalDrain()
        let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: Self.ownerID, runtime: AuthRuntimeState())
        _ = try drain.register(account: account) { true }
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var providers = 0
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { true }, lifetime: {
            providers += 1; return drain
        }) { await entered.open(); await release.wait(); return [] }
        let reading = Task { await model.open() }
        await entered.wait()
        var closed = false
        let closing = Task { await model.closeAndWait(); closed = true }
        while model.state != .closed { await Task.yield() }
        #expect(!closed && providers == 0)
        await release.open(); await reading.value; await closing.value
        #expect(model.state == .closed && providers == 0)
        let token = try drain.registerRecoveryPresentation(ownerID: Self.ownerID, close: {})
        drain.unregisterRecoveryPresentation(token)
        #expect(await drain.shutdown())
    }

    @Test func admittedDiscoveryIsJoinedByAccountLifetime() async throws {
        let drain = SharedMediaNativeOriginalDrain()
        let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: Self.ownerID, runtime: AuthRuntimeState())
        var ownerEnded = false
        _ = try drain.register(account: account) { ownerEnded = true; return true }
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal(), value = candidate()
        var reads = 0
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { true }, lifetime: { drain }) {
            reads += 1
            if reads == 2 { await entered.open(); await release.wait() }
            return [value]
        }
        await model.open()
        let selection = Task { await model.select(value) }
        await entered.wait()
        let shutdown = Task { await drain.shutdown() }
        while model.state != .closed { await Task.yield() }
        #expect(!ownerEnded)
        await release.open(); await selection.value
        #expect(await shutdown.value && ownerEnded && model.state == .closed)
    }


    @Test func concurrentReopenWaitersCannotOverwriteOwnedDiscovery() async throws {
        let firstEntered = ImageFocusEngineTests.Signal(), firstRelease = ImageFocusEngineTests.Signal()
        let nextEntered = ImageFocusEngineTests.Signal(), nextRelease = ImageFocusEngineTests.Signal()
        var reads = 0
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { true }) {
            reads += 1
            if reads == 1 { await firstEntered.open(); await firstRelease.wait() }
            else { await nextEntered.open(); await nextRelease.wait() }
            return []
        }
        let initial = Task { await model.open() }
        await firstEntered.wait(); model.close()
        var waiters = 0
        let first = Task { waiters += 1; await model.open() }
        let second = Task { waiters += 1; await model.open() }
        while waiters != 2 { await Task.yield() }
        await firstRelease.open(); await initial.value; await nextEntered.wait()
        #expect(reads == 2)
        var closed = false
        let closing = Task { await model.closeAndWait(); closed = true }
        while model.state != .closed { await Task.yield() }
        #expect(!closed)
        await nextRelease.open(); await first.value; await second.value; await closing.value
        #expect(closed && reads == 2 && model.state == .closed)
    }

    @Test func savedPagesReplaceWithoutSelectingOrStartingWork() async throws {
        let first = candidate(), last = candidate(), header = pageHeader()
        let cursor = SharedMediaNativeInitialPage.Cursor(kind: .enrollment, profile: first.profile,
            header: header, after: ObservationHistoryEnrollmentIntent.prefix + UUID().uuidString.lowercased())
        var pages = 0, selections = 0, actions = 0
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { true }, lifetime: { nil },
            initialRead: { _ in selections += 1; return nil },
            initialCompletion: { _, _ in actions += 1; return nil }, initialPageRead: { kind, after in
                pages += 1; #expect(kind == .enrollment)
                if pages == 1 { #expect(after == nil); return .init(candidates: [first], next: cursor) }
                #expect(after == cursor); return .init(candidates: [last], next: nil)
            }, discover: { throw SharedMediaStorageFailure.unavailable })
        await model.open()
        #expect(model.state == .unavailable)
        await model.findSavedInitial(.enrollment)
        #expect(model.state == .savedResults(.enrollment) && selections == 0 && actions == 0)
        await model.selectSavedInitial(last)
        #expect(selections == 0)
        await model.findSavedInitial(.enrollment, next: true)
        #expect(model.savedInitialPage?.candidates == [last] && pages == 2)
        await model.selectSavedInitial(first)
        #expect(selections == 0)
        await model.selectSavedInitial(last)
        #expect(selections == 1 && actions == 0 && model.state == .unavailable)
        await model.closeAndWait()
    }

    @Test(arguments: ["duplicate", "foreign", "profile", "overfull"])
    func savedPageRejectsInvalidBoundedIdentities(_ change: String) async {
        let first = candidate()
        let values: [SharedMediaNativeReceivedCandidate]
        switch change {
        case "duplicate": values = [first, first]
        case "foreign": values = [candidate(ownerID: UUID())]
        case "profile": values = [first, candidate(inventoryID: UUID())]
        default: values = (0...SharedMediaStoragePolicy.pageSize).map { _ in candidate() }
        }
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { true },
            initialPageRead: { _, _ in .init(candidates: values, next: nil) }, discover: { [] })
        await model.findSavedInitial(.retained)
        #expect(model.state == .unavailable && model.savedInitialPage == nil)
    }

    @Test(arguments: ["close", "hidden", "account", "cancel"])
    func savedPageLateReadCannotRestorePresentation(_ boundary: String) async {
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let value = candidate()
        var current = true, reads = 0, providers = 0
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { current }, lifetime: {
            providers += 1; return nil
        }, initialPageRead: { _, _ in
            reads += 1; await entered.open(); await release.wait()
            return .init(candidates: [value], next: nil)
        }, discover: { [] })
        let task = Task { await model.findSavedInitial(.enrollment) }
        await entered.wait()
        await model.findSavedInitial(.enrollment)
        #expect(reads == 1)
        switch boundary {
        case "close": model.close()
        case "hidden": model.setVisible(false)
        case "account": current = false
        default: task.cancel()
        }
        await release.open(); await task.value; await model.waitForStatusCleanup()
        #expect(model.state == (boundary == "close" ? .closed : .unavailable))
        #expect(model.savedInitialPage == nil && providers == 0)
    }

    @Test(arguments: ["absent", "valid", "sealed", "changed"])
    func enrollmentPageDistinguishesAbsentFromRejectedLifetime(_ boundary: String) async throws {
        let drain = SharedMediaNativeOriginalDrain()
        let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: Self.ownerID, runtime: AuthRuntimeState())
        _ = try drain.register(account: account) { true }
        if boundary == "sealed" { #expect(await drain.shutdown()) }
        var supplied: SharedMediaNativeOriginalDrain? = boundary == "absent" ? nil : drain
        let value = candidate()
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { true }, lifetime: { supplied },
            initialPageRead: { _, _ in .init(candidates: [value], next: nil) }, discover: { [] })
        await model.findSavedInitial(.enrollment)
        #expect(model.state == (boundary == "sealed" ? .unavailable : .savedResults(.enrollment)))
        if boundary == "changed" {
            supplied = nil
            await model.findSavedInitial(.enrollment)
            #expect(model.state == .unavailable)
        }
        if boundary == "absent" {
            await model.findSavedInitial(.retained)
            #expect(model.state == .unavailable)
        }
        await model.closeAndWait()
        #expect(await drain.shutdown())
    }

    private func pageHeader() -> SharedMediaNativeAppEligibility.Header {
        .init(inventory: .init(generation: Self.generation, revision: 1, phase: "ready", cursor: ""),
            bootstrapID: UUID(), bootstrapGeneration: Self.generation, bootstrapContract: 1, bootstrapRevision: 1)
    }

    @Test(arguments: ["visible", "close", "background", "account", "refresh"])
    func originalPreviewLateReadCannotOutliveSelection(_ action: String) async throws {
        let value = candidate()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var current = true, validations = 0
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).jpegData(withCompressionQuality: 0.8) { $0.fill(CGRect(x: 0, y: 0, width: 16, height: 16)) }
        let image = try #require(ImageDownsampler.downsampledSendableImage(data: bytes, maxSize: 2048))
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { current }, originalRead: { candidate, index, _ in
            #expect(candidate == value && index == 0)
            await entered.open(); await release.wait()
            return .init(image: image, index: index, count: 1, validate: { validations += 1 })
        }, discover: { [value] })
        #expect(!model.canViewOriginal)
        await model.open(); #expect(!model.canViewOriginal)
        await model.select(value); #expect(model.canViewOriginal)
        let reading = Task { await model.viewOriginal() }; await entered.wait()
        var closing: Task<Void, Never>?, closed = false
        switch action {
        case "close": closing = Task { await model.closeAndWait(); closed = true }; while model.state != .closed { await Task.yield() }; #expect(!closed)
        case "background": model.setVisible(false)
        case "account": current = false
        case "refresh":
            // Refresh joins the cancelled read before rediscovering the same identity.
            closing = Task { await model.refresh() }
            while model.canViewOriginal { await Task.yield() }
            await Task.yield()
        default: break
        }
        await release.open(); await reading.value; await closing?.value
        #expect((model.originalPreview != nil) == (action == "visible"))
        if action == "visible" {
            #expect(validations == 1)
            await model.checkOriginalScope(); #expect(validations == 2)
            current = false; await model.checkOriginalScope(); #expect(model.originalPreview == nil)
        }
        await model.closeAndWait()
    }

    @Test func originalScopeCheckIsDrainedBeforeClosing() async throws {
        let value = candidate(), entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 0.8) { $0.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
        let image = try #require(ImageDownsampler.downsampledSendableImage(data: bytes, maxSize: 2048))
        var validations = 0, closed = false
        let model = CaptureNativeRecoveryModel(ownerID: Self.ownerID, isCurrent: { true }, originalRead: { _, _, _ in
            .init(image: image, index: 0, count: 1, validate: {
                validations += 1
                if validations == 2 { await entered.open(); await release.wait() }
            })
        }, discover: { [value] })
        await model.open(); await model.select(value); await model.viewOriginal()
        let checking = Task { await model.checkOriginalScope() }; await entered.wait()
        let closing = Task { await model.closeAndWait(); closed = true }
        while model.state != .closed { await Task.yield() }
        #expect(!closed && model.originalPreview == nil)
        await release.open(); await checking.value; await closing.value
        #expect(closed && model.originalPreview == nil)
    }

    private static let ownerID = UUID(), inventoryID = UUID(), generation = UUID()
    private func candidate(ownerID: UUID? = nil, inventoryID: UUID? = nil,
                           packageID: UUID = UUID()) -> SharedMediaNativeReceivedCandidate {
        .init(profile: .init(ownerID: ownerID ?? Self.ownerID, inventoryID: inventoryID ?? Self.inventoryID, generation: Self.generation,
            storeIdentity: "synthetic", physicalBinding: "synthetic", receiptDigest: "synthetic"),
            packageID: packageID, draftGeneration: UUID(), operationID: UUID(), revision: 1,
            preparedSHA256: String(repeating: "a", count: 64), receivedSHA256: String(repeating: "b", count: 64))
    }
}

@Suite("Native Capture durable visible checking", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct CaptureNativeRecoveryClockTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Prepared = SharedMediaNativeReceivingIntent.Prepared
    private func saved(_ h: Store, _ p: Prepared) throws -> AnalysisRecoveryPresentation {
        let id = p.queueID.uuidString.lowercased(), context = h.context()
        let queue = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id }))
        return try .decode(#require(queue.recoveryPresentationData),
            identity: .init(ownerID: h.ownerID, observationID: p.observationID, operationID: p.operationID))
    }
    private func selected(_ h: Store, _ owner: SharedMediaNativeOriginalOwner,
                          current: @escaping () -> Bool = { true },
                          lifetime: (() -> SharedMediaNativeOriginalDrain?)? = nil,
                          didAcknowledge: @escaping () async -> Void = {},
                          send: @escaping NativeReceivedStatusTransport.Send) async throws -> CaptureNativeRecoveryModel {
        let model = CaptureNativeRecoveryModel(ownerID: h.ownerID, isCurrent: current,
            statusAccess: .fixture(owner: owner, didAcknowledge: didAcknowledge, send: send), lifetime: lifetime) { try await owner.discoverAppReceivedCandidates() }
        await model.open()
        guard case .unselected(let candidates) = model.state else { throw SharedMediaStorageFailure.closed }
        await model.select(try #require(candidates.first))
        #expect(model.canCheckStatus && model.observationStatus == .idle)
        return model
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(90)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func actualStatusActionSettlesAndExplicitlyReservesAgain() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let fixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: h.ownerID)
        defer { fixture.close() }
        fixture.mock.register(path: "/check-scan-status") { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, try ScanObservationTestFixture.response(to: request))
        }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        let first = try #require(try await owner.discoverAppReceivedCandidates().first)
        var listing = [first]
        let access = CaptureNativeRecoveryStatusAccess.app(isCurrent: { true }, owner: { owner }) {
            try await transport.perform(scanID: $0, ownerID: $1, validate: $2)
        }
        let model = CaptureNativeRecoveryModel(ownerID: h.ownerID, isCurrent: { true }, statusAccess: access) { listing }
        await model.open(); await model.select(first)
        for revision in [Int64(2), 4] {
            model.checkStatus()
            try await wait { model.canCheckStatus }
            #expect(model.recordObserved && model.observationStatus == .observed)
            let value = try saved(h, p)
            #expect(value.revision == revision && value.activeReservationID == nil)
            #expect(value.chargedMilliseconds > 0 && value.chargedMilliseconds < 30_000)
        }
        await model.closeAndWait()
        let other = SharedMediaNativeReceivedCandidate(profile: first.profile, packageID: UUID(),
            draftGeneration: UUID(), operationID: UUID(), revision: first.revision,
            preparedSHA256: first.preparedSHA256, receivedSHA256: first.receivedSHA256)
        listing = [other]
        await model.open(); await model.select(other)
        #expect(model.state == .holding(other) && !model.recordObserved && model.observationStatus == .idle)
        model.checkStatus(); try await wait { model.canCheckStatus }
        #expect(!model.recordObserved && model.observationStatus == .needsAttention)
        #expect(try saved(h, p).revision == 4)
        await model.closeAndWait()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["pause", "background", "close"])
    func visibilityEndsBeforeTransportDrainAndReopenWaits(action: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var ended = false
        let model = try await selected(h, owner) { scan, account, _ in
            await entered.open(); await release.wait(); ended = true
            return try ScanObservationTestFixture.response(ownerID: account, scanID: scan, rowExists: true)
        }
        model.checkStatus(); await entered.wait()
        #expect(model.observationStatus == .checking)
        switch action {
        case "close": model.close()
        case "background": model.setVisible(false)
        default: model.pauseChecking()
        }
        var reopened = false
        let reopen = Task { await model.open(); reopened = true }
        model.checkStatus() // no second reservation while cleanup owns the first
        try await Task.sleep(for: .milliseconds(200))
        #expect(!ended && !reopened && !model.canCheckStatus)
        #expect(try saved(h, p).revision == 1)
        await release.open(); await model.waitForStatusCleanup(); await reopen.value
        #expect(ended && reopened && !model.recordObserved)
        let value = try saved(h, p)
        #expect(value.revision == 2 && value.activeReservationID == nil)
        // Compare the actual monotonic interval frozen before the injected
        // drain delay. Pre-transport native audit time legitimately counts.
        let frozen = try #require(model.frozenVisibleElapsedForTesting)
        let reservation = try AnalysisRecoveryPresentation.initial(for: value.identity).reserve(id: UUID())
        let expected = try reservation.settle(current: reservation.reserved, elapsed: frozen)
        #expect(value.chargedMilliseconds == expected.chargedMilliseconds)
        await model.closeAndWait()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func closeBeforeAcknowledgementNeverStartsHiddenCheck() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        var calls = 0
        var presented: CaptureNativeRecoveryModel? = try await selected(h, owner) { _, _, _ in calls += 1; return Data() }
        weak let retained = presented
        var reached = false
        try owner.setMetadataFault { boundary in
            if boundary == .beforeReadback && !reached { reached = true; presented?.close(); presented = nil }
        }
        presented?.checkStatus()
        try await wait { reached }
        await retained?.waitForStatusCleanup()
        try await wait { retained == nil }
        #expect(calls == 0)
        let value = try saved(h, p)
        // An acknowledged late reservation settles zero; a denied acknowledgement
        // remains fully charged. Neither path may create hidden visible time.
        #expect((value.revision == 2 && value.chargedMilliseconds == 0)
            || (value.revision == 1 && value.chargedMilliseconds == 30_000))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["pause", "background", "close"])
    func acknowledgedReservationAfterVisibilityEndsSettlesExactlyZero(action: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let acknowledged = ImageFocusEngineTests.Signal(), deliver = ImageFocusEngineTests.Signal()
        var calls = 0
        let model = try await selected(h, owner, didAcknowledge: {
            await acknowledged.open(); await deliver.wait()
        }) { scan, account, _ in calls += 1; return try ScanObservationTestFixture.response(ownerID: account, scanID: scan, rowExists: true) }
        model.checkStatus(); await acknowledged.wait()
        #expect(model.observationStatus == .reserving && calls == 0)
        let reserved = try saved(h, p)
        #expect(reserved.revision == 1 && reserved.chargedMilliseconds == 30_000)
        #expect(reserved.activeReservationID != nil)
        switch action {
        case "close": model.close()
        case "background": model.setVisible(false)
        default: model.pauseChecking()
        }
        #expect(model.frozenVisibleElapsedForTesting == .zero)
        #expect(!model.canCheckStatus && !model.recordObserved)
        model.checkStatus() // Cleanup retains the acknowledged interval exclusively.
        await deliver.open(); await model.waitForStatusCleanup()
        let settled = try saved(h, p)
        #expect(calls == 0 && !model.recordObserved)
        #expect(settled.revision == 2 && settled.chargedMilliseconds == 0)
        #expect(settled.activeReservationID == nil && model.observationStatus == .paused)
        await model.closeAndWait()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func accountTeardownDrainsAndDeniesLateResultAndRefund() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var current = true, ended = false
        let model = try await selected(h, owner, current: { current }) { scan, account, _ in
            await entered.open(); await release.wait(); ended = true
            return try ScanObservationTestFixture.response(ownerID: account, scanID: scan, rowExists: true)
        }
        model.checkStatus(); await entered.wait()
        current = false; model.close()
        var completed = false
        let shutdown = Task { let result = await owner.invalidateAndAwaitForAccountTransition(); completed = true; return result }
        try await Task.sleep(for: .milliseconds(20))
        #expect(!completed)
        await release.open(); #expect(await shutdown.value)
        await model.waitForStatusCleanup()
        #expect(ended && !model.recordObserved && model.observationStatus == .needsAttention)
        #expect(try saved(h, p).chargedMilliseconds == 30_000)
    }

    @Test func expiryAndPauseChooseOneSettlement() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let model = try await selected(h, owner) { scan, account, _ in
            await entered.open(); await release.wait(); return try ScanObservationTestFixture.response(ownerID: account, scanID: scan, rowExists: false)
        }
        model.checkStatus(); await entered.wait()
        try await wait { model.observationStatus == .needsAttention }
        model.pauseChecking()
        await release.open(); await model.waitForStatusCleanup()
        let value = try saved(h, p)
        #expect(value.revision == 2 && value.chargedMilliseconds == 30_000 && value.activeReservationID == nil)
        #expect(!model.recordObserved)
        await model.closeAndWait()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func droppedHostKeepsOutstandingCleanupAlive() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var presented: CaptureNativeRecoveryModel? = try await selected(h, owner) { scan, account, _ in
            await entered.open(); await release.wait(); return try ScanObservationTestFixture.response(ownerID: account, scanID: scan, rowExists: true)
        }
        weak let retained = presented
        presented?.checkStatus(); await entered.wait()
        presented?.close(); presented = nil
        #expect(retained != nil)
        await release.open(); await retained?.waitForStatusCleanup()
        try await wait { retained == nil }
        #expect(try saved(h, p).revision == 2)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func uncertainAcknowledgementCannotStartOrRenewClock() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        var calls = 0, writes = 0
        let model = try await selected(h, owner) { scan, account, _ in
            calls += 1; return try ScanObservationTestFixture.response(ownerID: account, scanID: scan, rowExists: false)
        }
        try owner.setMetadataFault {
            if $0 == .afterSave { writes += 1 }
            if $0 == .beforeReadback { throw SharedMediaStorageFailure.unavailable }
        }
        model.checkStatus(); try await wait { model.canCheckStatus }
        #expect(model.observationStatus == .needsAttention)
        try owner.setMetadataFault(nil)
        model.checkStatus(); try await wait { model.canCheckStatus }
        #expect(model.observationStatus == .needsAttention && calls == 2 && writes == 1)
        let value = try saved(h, p)
        #expect(value.revision == 1 && value.chargedMilliseconds == 30_000)
        await model.closeAndWait()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["open", "closed", "dropped"])
    func accountLifetimeJoinsPresentationBeforeOwnerCompletion(host: String) async throws {
        let (h, originalOwner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        #expect(await originalOwner.invalidateAndAwaitForAccountTransition())
        let drain = SharedMediaNativeOriginalDrain()
        let owner = try await SharedMediaNativeReceivingStagingTests().reopen(h, container: h.container, drain: drain)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var senderEnded = false
        var presented: CaptureNativeRecoveryModel? = try await selected(h, owner, lifetime: { drain }) { scan, account, _ in
            await entered.open(); await release.wait(); senderEnded = true
            return try ScanObservationTestFixture.response(ownerID: account, scanID: scan, rowExists: true)
        }
        weak let retained = presented
        presented?.checkStatus(); await entered.wait()
        if host == "closed" { presented?.close() }
        if host == "dropped" { presented = nil }
        #expect(retained != nil)
        var finished = false, shutdownStarted = false
        let first = Task { shutdownStarted = true; let result = await drain.shutdown(); finished = true; return result }
        // In the already-closed case, presentation closure precedes account
        // shutdown. Synchronize on the account admission fence as well.
        try await wait { shutdownStarted && retained?.isCurrent == false && retained?.state == .closed }
        let second = Task { await drain.shutdown() }
        first.cancel() // Cancels this waiter, not the shared account shutdown.
        #expect(!finished && !senderEnded && retained?.isCurrent == false)
        #expect(throws: (any Error).self) { _ = try drain.registerRecoveryPresentation(ownerID: h.ownerID, close: {}) }
        await release.open()
        let firstResult = await first.value, secondResult = await second.value
        #expect(firstResult && secondResult)
        #expect(finished && senderEnded && !owner.isReadyForAppDispatch)
        let value = try saved(h, p)
        #expect(value.revision == 1 && value.chargedMilliseconds == 30_000)
        #expect(retained?.recordObserved != true)
        if host == "dropped" { try await wait { retained == nil } }
        else { #expect(presented?.observationStatus == .needsAttention) }
        await h.runtime.awaitAccountWorkDrain()
    }

}
