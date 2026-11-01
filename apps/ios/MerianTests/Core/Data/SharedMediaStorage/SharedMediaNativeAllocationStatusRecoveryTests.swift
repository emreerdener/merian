import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Saved allocation status only", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct NativeAllocationStatusRecoveryTests {
    typealias Access = SharedMediaNativePhotoAllocationAccess
    typealias Transport = SharedMediaNativePhotoAllocationTransportAccess
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Prepared = SharedMediaNativeReceivingIntent.Prepared
    typealias Allocation = SharedMediaNativePhotoAllocation
    private struct Fixture {
        let store: Store
        let owner: SharedMediaNativeOriginalOwner
        let prepared: Prepared
    }
    typealias Send = @MainActor (InitialPhotoAllocationRequest, @escaping Access.Validator, @escaping Access.Validator) async throws -> Transport.Reply

    private func access(_ version: Int, send: @escaping Send) -> Access {
        let deny: Access.Authorize = { _, _ in Issue.record("Recovery invoked create authorization"); throw SharedMediaStorageFailure.closed }
        if version == 1 {
            return .init(authorize: deny, send: { request, check, settle in
                guard case .legacy(let reply) = try await send(request, check, settle) else { throw SharedMediaStorageFailure.conflict }
                return reply
            })
        }
        let roles: Transport.RolesSend = { request, check, settle in
            guard case .roles(let reply) = try await send(request, check, settle) else { throw SharedMediaStorageFailure.conflict }
            return reply
        }
        return version == 6 ? .init(authorize: deny, sendBoundRoles: roles) : .init(authorize: deny, sendRoles: roles)
    }
    private func positive(_ request: InitialPhotoAllocationRequest) throws -> Transport.Reply {
        let receipt = Allocation.Receipt(assignmentDigest: String(repeating: "a", count: 64), createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001)
        if request.projection == .legacy { return .legacy(.allocated(receipt)) }
        let entries = try request.allocation.roleMapping?.entries ?? SharedMediaNativePhotoRoleMapping.references(request.allocation.claim).enumerated().map { index, reference in
            SharedMediaNativePhotoRoleMapping.Entry(photoOrdinal: index / 3, role: SharedMediaNativePhotoRoleMapping.Role.allCases[index % 3], referenceID: reference, objectID: UUID())
        }
        return .roles(.allocated(.init(receipt: receipt, entries: entries,
            backendBinding: request.projection == .boundRoles ? InitialPhotoUploadTicketTests().binding() : nil)))
    }
    private func held(_ request: InitialPhotoAllocationRequest) -> Transport.Reply {
        request.projection == .legacy ? .legacy(.held(.notFound)) : .roles(.held(.notFound))
    }
    private func fixture(_ version: Int, settled: Bool = false) async throws -> Fixture {
        let (store, owner, prepared) = try await SharedMediaNativePhotoAllocationTests().fixture()
        do {
            let authorize: Access.Authorize = { _, check in try check(); return .init(recipient: .gemini, validate: {}) }
            if version == 1 {
                _ = try await owner.allocateAppPhoto(prepared, authorizeCreate: authorize) { request, check, settle in
                    try check(); try settle()
                    guard case .legacy(let reply) = try settled ? positive(request) : held(request) else { throw SharedMediaStorageFailure.conflict }
                    return reply
                }
            } else {
                _ = try await owner.allocateAppPhotoRoles(prepared, backendBinding: version == 6, authorizeCreate: authorize) { request, check, settle in
                    try check(); try settle()
                    guard case .roles(let reply) = try settled ? positive(request) : held(request) else { throw SharedMediaStorageFailure.conflict }
                    return reply
                }
            }
            return .init(store: store, owner: owner, prepared: prepared)
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: [1, 2, 6])
    func missingClaimCannotAuthorizeSaveOrDispatch(_ version: Int) async throws {
        let (store, owner, prepared) = try await SharedMediaNativePhotoAllocationTests().fixture()
        do {
            let before = try NativePhotoStatusRecoveryTests().row(store)
            let caller = access(version) { _, _, _ in Issue.record("Missing claim dispatched"); throw SharedMediaStorageFailure.closed }
            try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Missing claim saved") } }
            await #expect(throws: (any Error).self) { _ = try await caller.recover(owner: owner, prepared: prepared, validate: {}) }
            #expect(try NativePhotoStatusRecoveryTests().row(store) == before)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: [1, 2, 6], [false, true])
    func originalProjectionSettlesOnceAndColdReplayDoesNotSave(version: Int, settled: Bool) async throws {
        let f = try await fixture(version, settled: settled)
        let store = f.store, owner = f.owner, prepared = f.prepared
        do {
            let helper = NativePhotoStatusRecoveryTests(), before = try helper.row(store), original = try helper.saved(store)
            let identity = try await owner.discoverAppReceivedCandidates()
            var sends = 0, saves = 0
            let caller = access(version) { request, check, settle in
                sends += 1; try check(); try settle()
                #expect(request.action == .status && request.allocation.version == version)
                #expect(request.projection.rawValue == (version == 6 ? 3 : version))
                #expect(request.allocation.claim == original.claim)
                if sends == 1 { #expect(try helper.row(store) == before) }
                return try positive(request)
            }
            try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
            let recovered = try await caller.recover(owner: owner, prepared: prepared, validate: {})
            #expect(saves == (settled ? 0 : 1) && recovered.version == version)
            #expect(recovered.claim == original.claim && recovered.receipt != nil)
            let after = try helper.row(store)
            #expect(after.preparedData == before.preparedData && after.resultData == before.resultData && after.revision == before.revision)
            #expect(try await owner.discoverAppReceivedCandidates() == identity)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
            do {
                try cold.setMetadataFault { if $0 == .beforeSave { Issue.record("Exact cold status replay saved") } }
                let replay = try await caller.recover(owner: cold, prepared: prepared, validate: {})
                #expect(replay == recovered && sends == 2)
                #expect(try helper.row(store) == after)
                #expect(await cold.invalidateAndAwaitForAccountTransition())
            } catch { _ = await cold.invalidateAndAwaitForAccountTransition(); throw error }
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: [1, 2, 6], [false, true])
    func negativeStatusPreservesEverySavedFact(version: Int, settled: Bool) async throws {
        let f = try await fixture(version, settled: settled)
        let store = f.store, owner = f.owner, prepared = f.prepared
        do {
            let helper = NativePhotoStatusRecoveryTests(), before = try helper.row(store), original = try helper.saved(store)
            let caller = access(version) { request, check, settle in try check(); try settle(); return held(request) }
            try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Negative status saved") } }
            let recovered = try await caller.recover(owner: owner, prepared: prepared, validate: {})
            #expect(recovered == original)
            #expect(try helper.row(store) == before)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: [1, 2, 6])
    func mismatchedProjectionCannotUpgradeOrSend(_ version: Int) async throws {
        let f = try await fixture(version)
        let store = f.store, owner = f.owner, prepared = f.prepared
        do {
            let before = try NativePhotoStatusRecoveryTests().row(store)
            let caller = access(version == 1 ? 2 : version == 2 ? 6 : 1) { _, _, _ in
                Issue.record("Wrong saved projection dispatched"); throw SharedMediaStorageFailure.closed
            }
            await #expect(throws: (any Error).self) { _ = try await caller.recover(owner: owner, prepared: prepared, validate: {}) }
            #expect(try NativePhotoStatusRecoveryTests().row(store) == before)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: [false, true])
    func transferStateUsesItsSeparateRecoveryOwner(_ bound: Bool) async throws {
        let reservedFixture = try await SharedMediaNativePhotoTransferReadbackTests().fixture(boundBackend: bound)
        let store = reservedFixture.store
        let owner = reservedFixture.owner
        let prepared = reservedFixture.prepared
        do {
            let before = try NativePhotoStatusRecoveryTests().row(store)
            let caller = access(bound ? 6 : 2) { _, _, _ in Issue.record("Transfer state entered allocation recovery"); throw SharedMediaStorageFailure.closed }
            await #expect(throws: (any Error).self) { _ = try await caller.recover(owner: owner, prepared: prepared, validate: {}) }
            #expect(try NativePhotoStatusRecoveryTests().row(store) == before)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: [1, 2, 6], ["lost", "caller"])
    func failedExchangeOrLatePresentationCannotSettle(version: Int, fault: String) async throws {
        let f = try await fixture(version)
        let store = f.store, owner = f.owner, prepared = f.prepared
        do {
            let before = try NativePhotoStatusRecoveryTests().row(store)
            var current = true
            let caller = access(version) { request, check, settle in
                try check(); try settle()
                if fault == "lost" { throw URLError(.networkConnectionLost) }
                current = false // Sender intentionally omits another validator call.
                return try positive(request)
            }
            await #expect(throws: (any Error).self) {
                _ = try await caller.recover(owner: owner, prepared: prepared, validate: {
                    guard current else { throw SharedMediaStorageFailure.stale }
                })
            }
            #expect(try NativePhotoStatusRecoveryTests().row(store) == before)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test(arguments: ["owner", "revision", "deletion"])
    func staleStoreAcrossAwaitCannotSettle(_ fault: String) async throws {
        let f = try await fixture(6)
        let store = f.store, owner = f.owner, prepared = f.prepared
        do {
            var saves = 0
            try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
            let caller = access(6) { request, check, settle in
                try check(); try settle()
                let context = store.context()
                if fault == "deletion" {
                    let id = store.packageID
                    context.delete(try SharedMediaNativePairPlanGraph.one(context,
                        FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id })))
                } else {
                    let id = store.inventoryID
                    let inventory = try SharedMediaNativePairPlanGraph.one(context,
                        FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
                    if fault == "owner" { inventory.generation = UUID() } else { inventory.revision += 1 }
                }
                try context.save(); return try positive(request)
            }
            await #expect(throws: (any Error).self) { _ = try await caller.recover(owner: owner, prepared: prepared, validate: {}) }
            #expect(saves == 0)
            _ = await owner.invalidateAndAwaitForAccountTransition()
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }
    @Test(arguments: ["root", "restoredRoot", "control", "restoredControl", "store", "revision", "account", "liability", "receiving", "cancel", "pageRoot", "pageRevision", "finalRoot"])
    func auditReadFaultsCannotAuthorizeStatus(_ fault: String) async throws {
        var f = try await fixture(6)
        let helper = NativePhotoStatusRecoveryTests(), runtime = f.store.runtime
        let session = AuthTransitionSession(userID: f.store.ownerID, isAnonymous: false)
        var publishedSession: AuthTransitionSession? = session
        var activeLease: AccountBoundWorkLease?
        var reads = 0, sends = 0, saves = 0, injected = false, restoredAfterReads = false, finalPhase = false
        var restore: (() throws -> Void)?
        func restoreFiles() throws { try restore?(); restore = nil }
        do {
            if fault == "account" {
                try #require(await f.owner.invalidateAndAwaitForAccountTransition())
                let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: f.store.ownerID,
                    begin: {
                        let lease = runtime.beginAccountWork(session: session)
                        activeLease = lease; return lease
                    },
                    isCurrent: { runtime.accountWorkLeaseIsCurrent($0, publishedSession: publishedSession, sdkSession: session) },
                    finish: { _ = runtime.finishAccountWork($0); activeLease = nil })
                let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: account, drain: .init())
                f = .init(store: f.store, owner: owner, prepared: f.prepared)
                _ = try await owner.openApp(container: f.store.container, parent: f.store.parent, inventoryID: f.store.inventoryID)
            }
            let before = try helper.row(f.store)
            func inject() throws {
                switch fault {
                case "root", "restoredRoot", "store", "pageRoot", "finalRoot":
                    let database = try #require(f.store.container.configurations.first).url.deletingLastPathComponent()
                    let original = fault == "store" ? database : f.store.parent.appendingPathComponent("photo", isDirectory: true)
                    let held = original.deletingLastPathComponent().deletingLastPathComponent()
                        .appendingPathComponent("audit-held-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.moveItem(at: original, to: held)
                    restore = {
                        guard FileManager.default.fileExists(atPath: held.path) else { return }
                        if FileManager.default.fileExists(atPath: original.path) {
                            #expect(try FileManager.default.contentsOfDirectory(atPath: original.path).isEmpty)
                            guard try FileManager.default.contentsOfDirectory(atPath: original.path).isEmpty else { throw SharedMediaStorageFailure.conflict }
                            try FileManager.default.removeItem(at: original)
                        }
                        try FileManager.default.moveItem(at: held, to: original)
                    }
                    try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
                    var url = original, values = URLResourceValues(); values.isExcludedFromBackup = true
                    try url.setResourceValues(values)
                case "control", "restoredControl":
                    let url = f.store.parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.finalName)
                    let original = try Data(contentsOf: url)
                    restore = { try original.write(to: url) }
                    try Data("invalid-control".utf8).write(to: url)
                case "revision", "pageRevision":
                    let context = f.store.context()
                    let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
                    inventory.revision += 1; try context.save()
                case "account":
                    let lease = try #require(activeLease)
                    try #require(runtime.accountWorkLeaseIsCurrent(lease, publishedSession: publishedSession, sdkSession: session))
                    // A generation counter alone does not invalidate this lease.
                    // Match production's live published/SDK session predicate.
                    publishedSession = nil
                    #expect(!runtime.accountWorkLeaseIsCurrent(lease, publishedSession: publishedSession, sdkSession: session))
                case "liability":
                    let context = f.store.context()
                    let allocation = try #require(try context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first)
                    allocation.reservedBytes = -1; try context.save()
                case "receiving":
                    let context = f.store.context()
                    let row = try #require(try context.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
                    row.phaseRaw = "invalid-audit-phase"; try context.save()
                case "cancel": withUnsafeCurrentTask { $0?.cancel() }
                default: throw SharedMediaStorageFailure.invalid
                }
                injected = true
            }
            let trace = SharedMediaNativeDebugHooks.InspectionTrace { value in
                if value.phase == .finalHeader && !value.completed { finalPhase = true }
            }
            try f.owner.setMetadataFault({ if $0 == .beforeSave { saves += 1 } }, inspectionTrace: trace, inspectionReadFault: {
                reads += 1
                if reads == 4 && ["restoredRoot", "restoredControl"].contains(fault) {
                    // Checkpoints 2 and 3 completed with the replacement present.
                    #expect(injected && restore != nil)
                    try restoreFiles(); restoredAfterReads = true
                }
                let atFinal = fault == "finalRoot" && finalPhase
                if !injected && (atFinal || (reads == 2 && !["pageRoot", "pageRevision", "finalRoot"].contains(fault))) { try inject() }
            }, inspectionPageFault: {
                if !injected && ["pageRoot", "pageRevision"].contains(fault) {
                    await Task.yield(); try inject()
                }
            })
            let caller = access(6) { request, check, settle in
                sends += 1; try check(); try settle(); return held(request)
            }
            let outcome = await Task { try await caller.recover(owner: f.owner, prepared: f.prepared, validate: {}) }.result
            try restoreFiles()
            #expect(injected && saves == 0)
            if fault == "restoredRoot" || fault == "restoredControl" {
                _ = try outcome.get(); #expect(sends == 1 && restoredAfterReads)
            } else {
                if case .success = outcome { Issue.record("Audit fault authorized status: \(fault)") }
                #expect(sends == 0)
            }
            if ["store", "revision", "account", "cancel"].contains(fault) { #expect(reads == 2) }
            if fault != "receiving" { #expect(try helper.row(f.store) == before) }
            try f.owner.setMetadataFault(nil)
            #expect(await f.owner.invalidateAndAwaitForAccountTransition())
            if fault == "account" { #expect(activeLease == nil) }
        } catch {
            do { try restoreFiles() } catch { Issue.record("Audit fixture restoration failed: \(error)") }
            try? f.owner.setMetadataFault(nil)
            _ = await f.owner.invalidateAndAwaitForAccountTransition(); throw error
        }
    }

    @Test func componentMeasurementExecutesOnceAndPreservesErrorsAndOptionalResults() throws {
        let trace = SharedMediaNativeDebugHooks.InspectionTrace { _ in }
        var calls = 0
        let value: Int? = trace.measure(.roots) { calls += 1; return nil }
        #expect(value == nil && calls == 1)
        #expect(throws: SharedMediaStorageFailure.closed) {
            try trace.measure(.storeBinding) { calls += 1; throw SharedMediaStorageFailure.closed }
        }
        #expect(calls == 2)
        let summaries = trace.componentSummaries
        #expect(summaries.map(\.component) == [.roots, .storeBinding])
        #expect(summaries.allSatisfy { $0.calls == 1 && $0.elapsed >= .zero && !$0.saturated })
    }

    @Test
    func allocationStatusAuditMeasurementsPreserveSavedAttempt() async throws {
        let f = try await fixture(6)
        var completedPhases = 0, saturated = false, entered = false
        let trace = SharedMediaNativeDebugHooks.InspectionTrace { value in
            if value.completed { completedPhases += 1 }
            saturated = saturated || value.saturated
            print("Native status audit phase=\(value.phase.rawValue) completed=\(value.completed) elapsed=\(value.elapsed) checkpoints=\(value.checkpointCount) checkpointTime=\(value.checkpointTime)")
        }
        do {
            let before = try NativePhotoStatusRecoveryTests().row(f.store)
            try f.owner.setMetadataFault(nil, inspectionTrace: trace)
            let began = ContinuousClock.now
            let caller = access(6) { _, check, settle in
                let validationBegan = ContinuousClock.now
                try check(); try settle(); entered = true
                print("Native status sender entry elapsed=\(began.duration(to: .now)) validation=\(validationBegan.duration(to: .now))")
                throw URLError(.networkConnectionLost)
            }
            await #expect(throws: URLError.self) {
                _ = try await caller.recover(owner: f.owner, prepared: f.prepared, validate: {})
            }
            #expect(entered && completedPhases > 0 && !saturated)
            #expect(try NativePhotoStatusRecoveryTests().row(f.store) == before)
            let components = trace.componentSummaries
            #expect(components.map(\.component) == SharedMediaNativeInspectionComponent.allCases)
            #expect(components.allSatisfy { $0.calls > 0 && !$0.saturated })
            for value in components {
                print("Native status component=\(value.component.rawValue) count=\(value.calls) elapsed=\(value.elapsed)")
            }
            try f.owner.setMetadataFault(nil)
            #expect(!f.owner.hasInspectionTraceForTesting)
            #expect(await f.owner.invalidateAndAwaitForAccountTransition())
        } catch {
            try? f.owner.setMetadataFault(nil)
            _ = await f.owner.invalidateAndAwaitForAccountTransition()
            throw error
        }
    }

    @Test(arguments: [false, true])
    func cancellationRetainsOwnerUntilSenderReturns(_ shutdown: Bool) async throws {
        let f = try await fixture(6)
        let store = f.store, owner = f.owner, prepared = f.prepared
        let before = try NativePhotoStatusRecoveryTests().row(store)
        let release = ImageFocusEngineTests.Signal()
        var entered = false, returned = false, drained = false
        var closing: Task<Bool, Never>?
        let caller = access(6) { request, check, settle in
            try check(); try settle(); entered = true
            await release.wait()
            return try positive(request)
        }
        let began = ContinuousClock.now
        var maximumPollGap: Duration = .zero
        let call = Task {
            defer { returned = true }
            return try await caller.recover(owner: owner, prepared: prepared, validate: {})
        }
        do {
            let deadline = ContinuousClock.now + .seconds(4)
            while !entered {
                guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
                let poll = ContinuousClock.now
                try await Task.sleep(for: .milliseconds(5))
                maximumPollGap = max(maximumPollGap, poll.duration(to: .now))
            }
            if shutdown {
                closing = Task { let result = await owner.invalidateAndAwaitForAccountTransition(); drained = true; return result }
            } else { call.cancel() }
            try await Task.sleep(for: .milliseconds(30))
            #expect(!returned && !drained)
            await release.open()
            if case .success = await call.result { Issue.record("Cancelled status settled") }
            #expect(try NativePhotoStatusRecoveryTests().row(store) == before)
            if let closing { #expect(await closing.value) } else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
        } catch {
            print("Native allocation entry diagnostic elapsed=\(began.duration(to: .now)) maximumPollGap=\(maximumPollGap) entered=\(entered) returned=\(returned)")
            await release.open(); call.cancel(); _ = await call.result
            if let closing { _ = await closing.value } else { _ = await owner.invalidateAndAwaitForAccountTransition() }
            throw error
        }
    }

    @Test(arguments: ["beforeSave", "afterSave", "beforeReadback"])
    func interruptedSaveRecoversExactProjectionWithoutAnotherClaim(_ fault: String) async throws {
        let f = try await fixture(6)
        let store = f.store, owner = f.owner, prepared = f.prepared
        let original = try NativePhotoStatusRecoveryTests().saved(store)
        let reply = try positive(.init(allocation: original, action: .status, projection: .boundRoles))
        let caller = access(6) { _, check, settle in try check(); try settle(); return reply }
        do {
            try owner.setMetadataFault { boundary in
                if (fault == "beforeSave" && boundary == .beforeSave) || (fault == "afterSave" && boundary == .afterSave)
                    || (fault == "beforeReadback" && boundary == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
            }
            if fault == "afterSave" { _ = try await caller.recover(owner: owner, prepared: prepared, validate: {}) } else { await #expect(throws: (any Error).self) { _ = try await caller.recover(owner: owner, prepared: prepared, validate: {}) } }
            try owner.setMetadataFault(nil)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
            do {
                var saves = 0
                try cold.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
                let recovered = try await caller.recover(owner: cold, prepared: prepared, validate: {})
                #expect(recovered.claim == original.claim && recovered.roleMapping != nil && recovered.backendBinding != nil)
                #expect(saves == (fault == "beforeSave" ? 1 : 0))
                let replay = try await caller.recover(owner: cold, prepared: prepared, validate: {})
                #expect(replay == recovered && saves == (fault == "beforeSave" ? 1 : 0))
                #expect(await cold.invalidateAndAwaitForAccountTransition())
            } catch { _ = await cold.invalidateAndAwaitForAccountTransition(); throw error }
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

}
