import Foundation
@testable import Merian
import os
import SwiftData
import Testing

/// Opt-in integration with one preprovisioned disposable host database. The
/// ordinary suite records a skip; only the armed exact-selector run qualifies it.
@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct SharedMediaNativeLiteralRecoveryTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MERIAN_LITERAL_BRIDGE_ENABLED"] == "1"))
    func nativeCandidateAndSQLRepliesRemainLiteralThroughDurableRecovery() async throws {
        let fixture = try await CaptureNativePhotoSubmissionTests().fixture(count: 2)
        let owner = fixture.owner, store = fixture.store
        let network = InitialPhotoAllocationTransportTests.Fixture(ownerID: store.ownerID)
        defer { network.close() }
        var packet: LiteralNativeRecoveryPacket?
        let access = SharedMediaNativePhotoAllocationAccess(authorize: { _, validate in
            try validate(); return .init(recipient: .gemini, validate: {})
        }, sendBoundRoles: { request, validate, settle in
            try validate()
            #expect(request.action == .create && request.projection == .boundRoles)
            #expect(packet == nil)
            let canonical = request.allocation.claim.candidateCanonical
            let received = try await LiteralNativeRecoveryPacket.exchange(owner: store.ownerID, candidate: canonical,
                sources: fixture.sourceInputs, capture: fixture.capture)
            try validate(); try settle()
            packet = received
            network.mock.register(path: InitialPhotoAllocationTransportTests.path) { outgoing in
                #expect(MockURLProtocol.bodyData(for: outgoing) == request.body)
                return (HTTPURLResponse(url: outgoing.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json", "Cache-Control": "private, no-store"])!, received.allocation)
            }
            return try await network.transport.performRoles(request, validateAttempt: validate, validateResponse: settle)
        })
        let session = CaptureNativePhotoSubmissionSession(selection: fixture.selection,
            preflight: { _, _, _ in .init(recipient: .gemini, validate: {}) }, allocationAccess: access, resolveOwner: { owner })
        let snapshot = try CaptureNativePhotoSubmissionSnapshot(fixture.capture)
        _ = try await session.submit(snapshot)
        _ = try await session.allocate(snapshot)
        let prepared = try #require(session.prepared), allocation = try #require(session.allocation)
        let literal = try #require(packet)
        let admission = try InitialCompletionDocuments.CpmAdmission(acknowledgement: literal.admission, original: .saved(allocation))
        let candidate = try #require(try await owner.discoverAppReceivedCandidates().first)
        let calls = OSAllocatedUnfairLock(initialState: [String]())
        network.mock.register(path: "/check-scan-status") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(Set(fields.keys) == ["initial_recovery"])
            let recovery = try #require(fields["initial_recovery"] as? [String: Any])
            let phase = try #require(recovery["phase"] as? String)
            #expect(request.timeoutInterval == 5 && request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "X-Merian-Initial-Recovery") == phase + "-v1")
            let sequence = calls.withLock { $0.append(phase); return $0 }
            if sequence.count == 1 { throw URLError(.networkConnectionLost) }
            let bytes = phase == "admission" ? literal.admission :
                (sequence.filter { $0 == "completion" }.count == 1 ? literal.pending : literal.found)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "Cache-Control": "no-store"])!, bytes)
        }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: network.dispatcher)
        let readAdmission: @MainActor (SharedMediaNativePhotoAllocation, @escaping NativeReceivedStatusTransport.Validator) async throws -> Data? = {
            try await transport.recoverAdmission(.saved($0), validate: $1)
        }
        var lastAcquisition: InitialCompletionDocuments.CpmAcquisition?
        let readCompletion: @MainActor (InitialCompletionDocuments.CpmAdmission, @escaping NativeReceivedStatusTransport.Validator) async throws -> InitialCompletionDocuments.CpmAcquisition? = {
            #expect($0.admission == admission.admission)
            let result = try await transport.recoverCompletion($0, validate: $1)
            if let result { lastAcquisition = result }
            return result
        }
        await #expect(throws: (any Error).self) {
            _ = try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: owner, isCurrent: { true },
                readAdmission: readAdmission, readCompletion: readCompletion, enroll: { _ in Issue.record("Lost reply enrolled") })
        }
        #expect(try store.context().fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: owner, isCurrent: { true },
            readAdmission: readAdmission, readCompletion: readCompletion, enroll: { _ in Issue.record("Pending enrolled") }) == nil)
        let packageID = store.packageID
        let waiting = try SharedMediaNativeReleaseLiveFixture.one(store.context(),
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }))
        #expect(waiting.initialAdmissionData == literal.admission && waiting.initialCompletionData == nil)
        await #expect(throws: SharedMediaStorageFailure.unavailable) {
            _ = try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: owner, isCurrent: { true },
                readAdmission: readAdmission, readCompletion: readCompletion,
                enroll: { _ in throw SharedMediaStorageFailure.unavailable })
        }
        let applied = try #require(try await owner.discoverAppInitialContinuation(candidate))
        #expect(applied.phase == .applied && applied.baseline == nil)
        #expect(try applied.prepared.encoded() == prepared.encoded())
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
        var enrollments = 0
        let pendingCompletion = try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: cold,
            isCurrent: { true }, readAdmission: { _, _ in Issue.record("Restart fetched admission"); return nil },
            readCompletion: readCompletion, enroll: { observation in
                #expect(observation == prepared.observationID); enrollments += 1
                _ = try await SharedMediaNativeInitialBindingFoundationTests().enrollInitialFixture(store,
                    prepared: prepared, acquisition: #require(lastAcquisition))
            })
        let completed = try #require(pendingCompletion)
        #expect(completed.observationID == prepared.observationID && enrollments == 1)
        let replay = try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: cold, isCurrent: { true },
            readAdmission: { _, _ in Issue.record("Terminal replay read admission"); return nil },
            readCompletion: { _, _ in Issue.record("Terminal replay read completion"); return nil },
            enroll: { _ in Issue.record("Terminal replay enrolled") })
        #expect(replay == completed && enrollments == 1)
        #expect(calls.withLock { $0 } == ["admission", "admission", "completion", "admission", "completion", "completion", "completion"])
        #expect(try store.context().fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
        print("LiteralNativeRecovery verified candidate=" + literal.candidateSHA256)
    }
}

private struct LiteralNativeRecoveryPacket: Sendable {
    let candidateSHA256: String
    let allocation: Data
    let admission: Data
    let pending: Data
    let found: Data

    @MainActor static func exchange(owner: UUID, candidate: String, sources: [Data], capture: StagedCapture) async throws -> Self {
        let environment = ProcessInfo.processInfo.environment
        let nonce = try #require(environment["MERIAN_LITERAL_BRIDGE_NONCE"])
        let port = try #require(environment["MERIAN_LITERAL_BRIDGE_PORT"].flatMap(Int.init))
        guard nonce.count == 64, nonce.allSatisfy({ $0.isASCII && ("0123456789abcdef".contains($0)) }),
              (1024...65535).contains(port), sources.count == 2, capture.images.count == 2 else { throw SharedMediaStorageFailure.closed }
        #if !targetEnvironment(simulator)
        throw SharedMediaStorageFailure.closed
        #endif
        let sourceSHA = try #require(environment["MERIAN_LITERAL_BRIDGE_SOURCE_SHA256"])
        let appSHA = try #require(environment["MERIAN_LITERAL_BRIDGE_APP_SHA256"])
        let testsSHA = try #require(environment["MERIAN_LITERAL_BRIDGE_TESTS_SHA256"])
        let app = try #require(Bundle.main.executableURL)
        let tests = try #require(Bundle(for: LiteralBridgeRedirectDenial.self).executableURL)
        guard [sourceSHA, appSHA, testsSHA].allSatisfy({ $0.count == 64 && $0.allSatisfy { $0.isASCII && "0123456789abcdef".contains($0) } }),
              try SharedMediaStageExitProbeSupport.digest(app) == appSHA,
              try SharedMediaStageExitProbeSupport.digest(tests) == testsSHA else { throw SharedMediaStorageFailure.stale }
        let execution = ["source_sha256": sourceSHA, "app_sha256": appSHA, "tests_sha256": testsSHA]
        let digest = SharedMediaAcquisitionEncoding.digest(Data(candidate.utf8))
        var roles: [[String: Any]] = []
        for ordinal in 0..<2 {
            let photo = capture.images[ordinal]
            for (name, bytes) in [("source", sources[ordinal]), ("ai", photo.compressedData), ("display", photo.displayData)] {
                guard !bytes.isEmpty, bytes.count <= 262144 else { throw SharedMediaStorageFailure.capacity }
                roles.append(["ordinal": ordinal, "role": name, "bytes_base64": bytes.base64EncodedString()])
            }
        }
        let body = try JSONSerialization.data(withJSONObject: ["version": 1, "nonce": nonce,
            "owner_id": owner.uuidString.lowercased(), "execution": execution, "candidate_canonical": candidate, "candidate_sha256": digest, "roles": roles])
        guard body.count <= 2 * 1048576 else { throw SharedMediaStorageFailure.capacity }
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/native/\(nonce)"))
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 135)
        request.httpMethod = "POST"; request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 135
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: LiteralBridgeRedirectDenial(), delegateQueue: nil)
        // An absolute whole-exchange bound; neither byte trickles nor socket
        // activity extend it. This is test IPC, not the production 5s recovery.
        let deadline = Task { try await Task.sleep(for: .seconds(135)); session.invalidateAndCancel() }
        defer { deadline.cancel(); session.invalidateAndCancel() }
        try Task.checkCancellation()
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == url,
              http.value(forHTTPHeaderField: "Cache-Control") == "no-store" else { throw SharedMediaStorageFailure.unavailable }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < 524288 else { throw SharedMediaStorageFailure.capacity }
            data.append(byte)
        }
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        guard Set(fields.keys) == ["version", "nonce", "candidate_sha256", "allocation", "admission", "pending", "found", "wire_metadata"] else { throw SharedMediaStorageFailure.conflict }
        guard fields["version"] as? Int == 1, fields["nonce"] as? String == nonce,
              fields["candidate_sha256"] as? String == digest else { throw SharedMediaStorageFailure.stale }
        let metadata = try #require(fields["wire_metadata"] as? [String: [String: Any]])
        func wire(_ key: String, _ label: String) throws -> Data {
            let encoded = try #require(fields[key] as? String), bytes = try #require(Data(base64Encoded: encoded))
            let facts = try #require(metadata[label])
            guard !bytes.isEmpty, bytes.count <= 131072, bytes.base64EncodedString() == encoded,
                  facts["byteCount"] as? Int == bytes.count, facts["reads"] as? Int == 1,
                  facts["sha256"] as? String == SharedMediaAcquisitionEncoding.digest(bytes) else { throw SharedMediaStorageFailure.conflict }
            print("LiteralNativeRecovery wire=" + key + " sha256=" + SharedMediaAcquisitionEncoding.digest(bytes))
            return bytes
        }
        return try .init(candidateSHA256: digest, allocation: wire("allocation", "allocation"), admission: wire("admission", "admission"),
            pending: wire("pending", "pending_status_after_original_dispatch"), found: wire("found", "original_completion_status_delivery"))
    }
}

private final class LiteralBridgeRedirectDenial: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
                    newRequest _: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
