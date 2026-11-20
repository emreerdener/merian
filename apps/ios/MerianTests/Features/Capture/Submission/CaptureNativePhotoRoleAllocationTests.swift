import Foundation
@testable import Merian
import os
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureNativePhotoRoleAllocationTests {
    typealias Wire = InitialPhotoAllocationTransportTests

    @Test(arguments: [false, true], [false, true])
    func twoPhotoRoleAllocationAndColdRecoveryPreserveSubmission(lostReply: Bool, boundBackend: Bool) async throws {
        let f = try await CaptureNativePhotoSubmissionTests().fixture(count: 2)
        let wire = Wire.Fixture(ownerID: f.store.ownerID); defer { wire.close() }
        var authorizations = 0, actions: [InitialPhotoAllocationRequest.Action] = []
        let authorize: SharedMediaNativePhotoAllocationAccess.Authorize = { _, validate in
            try validate(); authorizations += 1
            return .init(recipient: .gemini, validate: {})
        }
        let send: NativePhotoAllocationTransportAccess.RolesSend = { request, validate, settle in
            #expect(request.projection == (boundBackend ? .boundRoles : .roles) && request.allocation.version == (boundBackend ? 6 : 2))
            actions.append(request.action)
            let data = try Wire.reply(request), body = request.body, lose = lostReply && request.action == .create
            wire.mock.register(path: Wire.path) { outgoing in
                #expect(MockURLProtocol.bodyData(for: outgoing) == body)
                if lose { throw URLError(.networkConnectionLost) }
                return (HTTPURLResponse(url: outgoing.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
            }
            return try await wire.transport.performRoles(request, validateAttempt: validate, validateResponse: settle)
        }
        let access = boundBackend ? SharedMediaNativePhotoAllocationAccess(authorize: authorize, sendBoundRoles: send)
            : SharedMediaNativePhotoAllocationAccess(authorize: authorize, sendRoles: send)
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection,
            preflight: { _, _, _ in .init(recipient: .gemini, validate: {}) }, allocationAccess: access, resolveOwner: { f.owner })
        let snapshot = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        _ = try await session.submit(snapshot)
        let prepared = try #require(session.prepared), local = try #require(session.receipt)
        if lostReply { await #expect(throws: (any Error).self) { _ = try await session.allocate(snapshot) } }
        else {
            _ = try await session.allocate(snapshot)
            #expect(session.allocation?.roleMapping?.entries.count == 6)
        }
        #expect(session.receipt == local && !session.isBusy)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(f.store)
        let recovered = CaptureNativePhotoSubmissionSession(selection: f.selection, preflight: { _, _, _ in
            Issue.record("Recovery rediscovered processor"); throw SharedMediaStorageFailure.closed
        }, allocationAccess: access, resolveOwner: { cold })
        _ = try await recovered.submit(snapshot)
        #expect(try recovered.prepared?.encoded() == prepared.encoded())
        #expect(recovered.receipt == local)
        _ = try await recovered.allocate(snapshot)
        #expect(actions == [.create, .status] && authorizations == 1)
        #expect(recovered.allocation?.roleMapping?.entries.count == 6)
        #expect(recovered.allocation?.remainingAdvances == 0)
        #expect((recovered.allocation?.backendBinding != nil) == boundBackend)
        #expect(try f.store.context().fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.queueNeedsAttention) == [true])
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["accepted", "changedDraft", "revokedPermission", "interveningReceive", "lostReceiveAcknowledgement", "lostBoundAcknowledgement", "revokedAtResume"])
    func freshCaptureSendsOneFrozenSourceAndFencesChanges(duringTicket: String) async throws {
        try await runCapture(duringTicket)
    }

    @Test(arguments: ["accepted", "stillOpen", "lostProgress"])
    func firstOriginalPutChecksExactProgressOnce(_ outcome: String) async throws {
        try await runCapture(outcome)
    }

    @Test func revokedAtTaskConstructionKeepsOriginalWithoutOpeningSession() async throws {
        try await runCapture("revokedAtConstruction")
    }

    @Test(arguments: ["accepted", "twoPhotos", "lostNextStart", "duplicateAttempt", "lostRoleAck", "unqualifiedSession"])
    func assignedPhotoRolesArePreservedInOrder(_ outcome: String) async throws {
        try await runCapture(outcome)
    }

    @Test(arguments: ["admitted", "lostAdmissionReply", "serverHeld", "revokedBeforePin"])
    func sealedRosterStartsOneVerificationAndRecoversOriginalAdmission(_ outcome: String) async throws {
        try await runCapture(outcome)
    }

    @Test func freshPhotoReopensInHistoryAndChildRecoversThroughUndo() async throws {
        try await runCapture("freshHistory")
    }

    private func runCapture(_ duringTicket: String) async throws {
        let photoCount = duringTicket == "twoPhotos" ? 2 : 1
        let harness = CaptureNativePhotoSubmissionTests(), f = try await harness.fixture(count: photoCount)
        let wire = Wire.Fixture(ownerID: f.store.ownerID); defer { wire.close() }
        let uploadWire = ScopedMockTransport(), uploadSession = uploadWire.makeSession()
        defer { uploadSession.invalidateAndCancel() }
        let pinned = PinnedNetworkTransport()
        pinned.overridingSession = uploadSession
        let ticket = InitialPhotoUploadTicketTests(), binding = ticket.binding()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let puts = OSAllocatedUnfairLock(initialState: 0)
        let loseBoundSave = OSAllocatedUnfairLock(initialState: false)
        if duringTicket == "lostBoundAcknowledgement" {
            try f.owner.setMetadataFault { boundary in
                if boundary == .afterSave, loseBoundSave.withLock({ let armed = $0; $0 = false; return armed }) {
                    throw SharedMediaStorageFailure.closed
                }
            }
        }
        let remainingSaves = OSAllocatedUnfairLock(initialState: 0)
        if ["lostNextStart", "lostRoleAck"].contains(duringTicket) {
            try f.owner.setMetadataFault { boundary in
                guard boundary == .afterSave else { return }
                if remainingSaves.withLock({ count in
                    guard count > 0 else { return false }
                    count -= 1
                    return count == 0
                }) { throw SharedMediaStorageFailure.closed }
            }
        }
        let permission = OSAllocatedUnfairLock(initialState: true)
        let issuedExchanges = OSAllocatedUnfairLock(initialState: 0)
        var grants = 0, issues = 0, statusReads = 0, progressReads = 0
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { _, check in
            try check(); grants += 1
            return .init(recipient: .gemini) { guard permission.withLock({ $0 }) else { throw MerianError.aiConsentRequired } }
        }, sendBoundRoles: { request, check, settle in
            #expect(request.action == .create && request.projection == .boundRoles)
            var row = try #require(JSONSerialization.jsonObject(with: Wire.reply(request)) as? [String: Any])
            let created = Int64(Date().timeIntervalSince1970 * 1000) - 1000
            row["created_at_ms"] = created; row["expires_at_ms"] = created + 1_800_000
            row["backend_generation"] = binding.generation.uuidString.lowercased()
            let bytes = try JSONSerialization.data(withJSONObject: row)
            wire.mock.register(path: Wire.path) { outgoing in
                (HTTPURLResponse(url: outgoing.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, bytes)
            }
            let reply = try await wire.transport.performRoles(request, validateAttempt: check, validateResponse: settle)
            if duringTicket == "lostBoundAcknowledgement" { loseBoundSave.withLock { $0 = true } }
            return reply
        })
        var neverStarted: PinnedPhotoUploadTask?
        let originalReceiptArrived = OSAllocatedUnfairLock(initialState: false)
        if duringTicket == "revokedBeforePin" {
            try f.owner.setMetadataFault { boundary in
                if boundary == .beforeSave, originalReceiptArrived.withLock({ $0 }) {
                    permission.withLock { $0 = false }
                }
            }
        }
        let verifyAdmission = ["freshHistory", "admitted", "lostAdmissionReply", "serverHeld", "revokedBeforePin"].contains(duringTicket)
        let serviceCalls = OSAllocatedUnfairLock(initialState: 0)
        var originalAck: Data?
        let recoveryTransport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: wire.dispatcher)
        let read: @MainActor (SharedMediaNativePhotoAllocation, @escaping SharedMediaNativePhotoAllocationAccess.Validator) async throws -> Data? = { allocation, validate in
            guard duringTicket != "serverHeld" else { return nil }
            let ack = try originalAck ?? SharedMediaNativeInitialBindingFoundationTests().originalAcknowledgement(allocation)
            originalAck = ack
            wire.mock.register(path: "/check-scan-status") { request in
                #expect(request.value(forHTTPHeaderField: "X-Merian-Initial-Recovery") == "admission-v1")
                return (try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])), ack)
            }
            let answer = try await recoveryTransport.recoverAdmission(.saved(allocation), validate: validate)
            originalReceiptArrived.withLock { $0 = true }
            return answer
        }
        let admission = SharedMediaNativePhotoAllocationAccess.CohortAdmission(verify: { grant in
            wire.mock.register(path: "/initial-photo-transfer") { request in
                serviceCalls.withLock { $0 += 1 }
                let data = try #require(MockURLProtocol.bodyData(for: request))
                let row = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(row["action"] as? String == "verify_cohort" && row["version"] as? Int == 3)
                #expect(row["object_id"] == nil && row["owner_id"] == nil && row["role_mapping"] == nil)
                if duringTicket == "lostAdmissionReply" { throw URLError(.networkConnectionLost) }
                let text = try #require(row["candidate_canonical"] as? String)
                let candidateDigest = SharedMediaAcquisitionEncoding.digest(Data(("merian.initial-analysis.cpm-photo-candidate.v1\n" + text).utf8))
                var reply = row.filter { ["scan_id", "assignment_digest", "backend_generation", "backend_configuration_digest"].contains($0.key) }
                reply["version"] = 3; reply["authority"] = "none"; reply["candidate_digest"] = candidateDigest
                reply["outcome"] = duringTicket == "serverHeld" ? "held" : "admitted"
                return (try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])), try JSONSerialization.data(withJSONObject: reply))
            }
            return try await wire.transport.verifyCohort(grant)
        }, readOriginal: read)
        let first = CaptureNativePhotoSubmissionSession.FirstTransfer(catalog: try .init([ticket.destination()]), send: { request, check in
            try check()
            if request.action != .issue {
                let allocation = request.allocation, attempt = try #require(allocation.remoteAttempt)
                let bytes: Data
                if request.action == .status {
                    statusReads += 1
                    bytes = try NativePhotoStatusRecoveryTests().statusBytes(allocation, state: "may_have_issued", closed: duringTicket != "stillOpen", id: attempt.id)
                } else {
                    progressReads += 1
                    if duringTicket == "lostProgress" { throw URLError(.networkConnectionLost) }
                    let transfer = try #require(allocation.transferReservation), backend = try #require(allocation.backendBinding)
                    let stamp = Date().formatted(.iso8601).replacingOccurrences(of: "Z", with: ".000000Z")
                    bytes = try ticket.bytes(["version": 2, "authority": "none", "outcome": "live_role_observed",
                        "owner_id": f.store.ownerID.uuidString.lowercased(), "scan_id": allocation.claim.observationID.uuidString.lowercased(),
                        "assignment_digest": try #require(allocation.receipt).assignmentDigest, "object_id": transfer.selection.objectID.uuidString.lowercased(),
                        "attempt_id": attempt.id.uuidString.lowercased(), "role": transfer.selection.role.rawValue, "byte_count": transfer.byteCount,
                        "content_type": try transfer.declaredContentType(claim: allocation.claim), "sha256": transfer.sha256,
                        "backend_generation": backend.generation.uuidString.lowercased(), "backend_configuration_digest": backend.configurationDigest,
                        "policy_digest": String(repeating: "e", count: 64), "observed_at": stamp])
                }
                let body = request.body
                wire.mock.register(path: "/initial-photo-transfer") { outgoing in
                    #expect(MockURLProtocol.bodyData(for: outgoing) == body)
                    return (HTTPURLResponse(url: outgoing.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, bytes)
                }
                let result = try await wire.transport.performTransfer(request, validateAttempt: check)
                if ["lostNextStart", "lostRoleAck"].contains(duringTicket), request.action == .roleProgress {
                    remainingSaves.withLock { $0 = duringTicket == "lostRoleAck" ? 1 : 2 }
                }
                return result
            }
            issues += 1
            let transfer = try #require(request.allocation.transferReservation)
            let slot = issues - 1
            #expect(request.action == .issue && transfer.selection.photoOrdinal == slot / 3)
            #expect(transfer.selection.role == SharedMediaNativePhotoRoleMapping.Role.allCases[slot % 3])
            var row = try ticket.row(request.allocation, createdAtMilliseconds: Int64(Date().timeIntervalSince1970 * 1000))
            if duringTicket != "duplicateAttempt" { row["attempt_id"] = UUID().uuidString.lowercased() }
            let data = try ticket.bytes(row)
            let rawURL = try #require(row["url"] as? String), path = try #require(URL(string: rawURL)?.path)
            uploadWire.register(path: path) { outgoing in
                puts.withLock { $0 += 1 }
                let body = try #require(MockURLProtocol.bodyData(for: outgoing))
                #expect(body.count == transfer.byteCount && SharedMediaAcquisitionEncoding.digest(body) == transfer.sha256)
                #expect(outgoing.httpMethod == "PUT" && outgoing.value(forHTTPHeaderField: "x-amz-content-sha256") == transfer.sha256)
                return (HTTPURLResponse(url: outgoing.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data())
            }
            await entered.open(); await release.wait()
            wire.mock.register(path: "/initial-photo-transfer") { outgoing in
                issuedExchanges.withLock { $0 += 1 }
                return (HTTPURLResponse(url: outgoing.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
            }
            return try await wire.transport.performTransfer(request, validateAttempt: check)
        }, makeTask: {
            if duringTicket == "revokedAtResume" {
                return pinned.measuredPhotoUploadTask { permission.withLock { $0 = false } }
            }
            if duringTicket == "unqualifiedSession" { return .init(session: uploadSession) }
            let task = pinned.photoUploadTask()
            if duringTicket == "revokedAtConstruction" {
                neverStarted = task
                permission.withLock { $0 = false }
            }
            return task
        }, admission: verifyAdmission ? admission : nil)
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection, preflight: { _, _, _ in
            .init(recipient: .gemini, validate: {})
        }, allocationAccess: access, firstTransfer: first, resolveOwner: { f.owner })
        if duringTicket == "interveningReceive" {
            session.beforeReceiveForTesting = { prepared in _ = try await f.owner.receiveAppPrepared(prepared) }
        } else if duringTicket == "lostReceiveAcknowledgement" {
            let dropped = OSAllocatedUnfairLock(initialState: false)
            session.beforeReceiveForTesting = { _ in
                try f.owner.setMetadataFault { boundary in
                    if boundary == .afterSave, dropped.withLock({ if $0 { return false }; $0 = true; return true }) {
                        throw SharedMediaStorageFailure.closed
                    }
                }
            }
        }
        let vm = harness.viewModel(session: session, account: { f.store.ownerID })
        vm.stagedCapture = f.capture
        let bound = vm.draftSession.bindAccount(f.store.ownerID)
        #expect(bound)
        let running = Task {
            await vm.submitStagedCapture(modelContext: ModelContext(f.store.container))
            await entered.open() // Fail diagnostically if an earlier boundary refuses.
        }
        await entered.wait()
        if duringTicket == "revokedPermission" { permission.withLock { $0 = false } }
        if duringTicket == "changedDraft" { vm.stagedCapture.observationContexts[0].context = .init(freeText: "Later selection") }
        let visible = try CaptureNativePhotoSubmissionSnapshot(vm.stagedCapture)
        await release.open(); await running.value
        if verifyAdmission {
            let prepared = try #require(session.prepared)
            let stored = try await f.owner.recoverAppInitialAdmission(prepared) { _, _ in nil }
            #expect((stored != nil) == (["admitted", "freshHistory"].contains(duringTicket)))
            #expect(puts.withLock { $0 } == 3 && serviceCalls.withLock { $0 } == 1)
            #expect(await f.owner.invalidateAndAwaitForAccountTransition())
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(f.store)
            let recovered = try await cold.recoverAppInitialAdmission(prepared, readOriginal: read)
            #expect((recovered != nil) == (duringTicket != "serverHeld"))
            #expect(serviceCalls.withLock { $0 } == 1 && puts.withLock { $0 } == 3 && vm.pendingAnalyzeScanId == nil)
            if duringTicket == "freshHistory" {
                let original = try #require(recovered)
                try await SharedMediaNativeInitialBindingFoundationTests().continueFreshPhotoInHistory(
                    store: f.store, owner: cold, prepared: prepared, admission: original,
                    expectedAI: f.capture.images.map(\.compressedData),
                    expectedDescriptions: f.capture.observationContexts.map { $0.context.freeText })
                #expect(serviceCalls.withLock { $0 } == 1 && puts.withLock { $0 } == 3)
            } else {
                #expect(await cold.invalidateAndAwaitForAccountTransition())
            }
            return
        }
        let saved = try #require(try await f.owner.discoverAppPhotoSubmission(packageID: f.store.packageID))
        let intervened = ["interveningReceive", "lostReceiveAcknowledgement", "lostBoundAcknowledgement"].contains(duringTicket)
        let completed = ["accepted", "twoPhotos"].contains(duringTicket)
        let interruptedNext = ["lostNextStart", "duplicateAttempt"].contains(duringTicket)
        let confirmedOnly = ["lostRoleAck", "unqualifiedSession"].contains(duringTicket)
        let putCount = completed ? photoCount * 3 : (["stillOpen", "lostProgress"].contains(duringTicket) || interruptedNext || confirmedOnly ? 1 : 0)
        let issueCount = completed ? putCount : duringTicket == "duplicateAttempt" ? 2 : intervened ? 0 : 1
        let allocation = try #require(saved.allocation)
        if completed {
            let history = try #require(allocation.completedRoles), mapping = try #require(allocation.roleMapping)
            #expect(allocation.version == 17 && history.count == putCount)
            #expect(history.map(\.transfer.selection) == mapping.entries)
            #expect(Set(history.map(\.attempt.id)).count == putCount)
            #expect(allocation.transferReservation == nil && allocation.remoteAttempt == nil)
            var fields = try #require(try JSONSerialization.jsonObject(with: allocation.encoded()) as? [String: Any])
            let prior = try #require(fields["completedRoles"] as? [[String: Any]])
            fields["completedRoles"] = Array(prior.reversed())
            let corrupted = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
            #expect(throws: (any Error).self) {
                try SharedMediaNativePhotoAllocation.decode(corrupted, sha256: SharedMediaAcquisitionEncoding.digest(corrupted))
            }
        } else if confirmedOnly {
            #expect(allocation.version == 13 && allocation.liveRoleReceipt != nil && allocation.completedRoles == nil)
            #expect(allocation.transferReservation?.selection.role == .source)
        } else if interruptedNext {
            #expect(allocation.version == 14 && allocation.completedRoles?.count == 1 && allocation.remoteAttempt == nil)
            #expect(allocation.transferReservation?.selection.role == .ai)
        } else {
            let putMarker = putCount > 0 || ["revokedAtResume", "revokedAtConstruction"].contains(duringTicket)
            #expect(allocation.version == (intervened ? 6 : putMarker ? 12 : 11))
        }
        #expect(try saved.prepared.encoded() == session.prepared?.encoded())
        #expect(try CaptureNativePhotoSubmissionSnapshot(vm.stagedCapture) == visible)
        #expect(grants == (intervened ? 1 : 2) && issues == issueCount && puts.withLock { $0 } == putCount)
        #expect(vm.pendingAnalyzeScanId == nil && (vm.offlineToastMessage != nil) == (duringTicket != "changedDraft"))
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
        let reopened = try await SharedMediaNativeReceivingStagingTests().reopen(f.store)
        let recovered = CaptureNativePhotoSubmissionSession(selection: f.selection,
            allocationAccess: access, firstTransfer: first, resolveOwner: { reopened })
        let submitted = try CaptureNativePhotoSubmissionSnapshot(f.capture)
        let recovery = try await recovered.submit(submitted)
        #expect(recovered.allocation == saved.allocation && !recovered.hasFreshFirstTransfer)
        try await recovered.startFirstTransferIfPresent(submitted, after: recovery, validate: {
            Issue.record("Cold submission opened a fresh transfer")
        })
        #expect(grants == (intervened ? 1 : 2) && issues == issueCount && puts.withLock { $0 } == putCount)
        if duringTicket == "revokedAtConstruction" {
            let task = try #require(neverStarted)
            #expect(!task.hasCreatedOwnedSessionForTesting)
        }
        if interruptedNext {
            let recoveredIssue = try InitialPhotoTransferRequest(allocation: allocation, action: .issue)
            await #expect(throws: SharedMediaStorageFailure.closed) {
                _ = try await wire.transport.performTransfer(recoveredIssue, validateAttempt: {})
            }
        }
        let refusedBeforeExchange = ["changedDraft", "revokedPermission"].contains(duringTicket)
        #expect(issuedExchanges.withLock { $0 } == (refusedBeforeExchange ? 0 : issueCount))
        #expect(statusReads == putCount && progressReads == (duringTicket == "stillOpen" ? 0 : putCount))
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true], [false, true])
    func actualCaptureCallerPreservesLaterSelectionWithRoleProjection(changeSelection: Bool, boundBackend: Bool) async throws {
        let harness = CaptureNativePhotoSubmissionTests(), f = try await harness.fixture()
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let wire = Wire.Fixture(ownerID: f.store.ownerID); defer { wire.close() }
        var actions: [InitialPhotoAllocationRequest.Action] = []
        let authorize: SharedMediaNativePhotoAllocationAccess.Authorize = { _, validate in
            try validate(); return .init(recipient: .gemini, validate: {})
        }
        let send: NativePhotoAllocationTransportAccess.RolesSend = { request, validate, settle in
            try validate(); actions.append(request.action)
            await entered.open(); await release.wait()
            let data = try Wire.reply(request)
            wire.mock.register(path: Wire.path) { outgoing in
                (HTTPURLResponse(url: outgoing.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
            }
            return try await wire.transport.performRoles(request, validateAttempt: validate, validateResponse: settle)
        }
        let access = boundBackend ? SharedMediaNativePhotoAllocationAccess(authorize: authorize, sendBoundRoles: send)
            : SharedMediaNativePhotoAllocationAccess(authorize: authorize, sendRoles: send)
        let session = CaptureNativePhotoSubmissionSession(selection: f.selection,
            preflight: { _, _, _ in .init(recipient: .gemini, validate: {}) }, allocationAccess: access, resolveOwner: { f.owner })
        let vm = harness.viewModel(session: session, account: { f.store.ownerID })
        vm.stagedCapture = f.capture
        let bound = vm.draftSession.bindAccount(f.store.ownerID)
        #expect(bound)
        let running = Task { await vm.submitStagedCapture(modelContext: ModelContext(f.store.container)) }
        await entered.wait()
        if changeSelection { vm.stagedCapture.observationContexts[0].context = .init(freeText: "Later selection") }
        let visible = try CaptureNativePhotoSubmissionSnapshot(vm.stagedCapture)
        await release.open(); await running.value
        #expect(actions == [.create] && session.allocation?.roleMapping?.entries.count == 3)
        #expect(try CaptureNativePhotoSubmissionSnapshot(vm.stagedCapture) == visible)
        #expect((vm.offlineToastMessage != nil) == !changeSelection)
        #expect(vm.pendingAnalyzeScanId == nil && !vm.isCheckingScanAdmission)
        #expect(await f.owner.invalidateAndAwaitForAccountTransition())
    }
}
