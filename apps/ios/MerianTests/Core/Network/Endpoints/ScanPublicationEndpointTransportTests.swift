import Foundation
import Testing

@testable import Merian

private final class ScanPublicationRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var requestCount = 0
    private var idempotencyKeys: [String?] = []

    func record(idempotencyKey: String?) -> Int {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        idempotencyKeys.append(idempotencyKey)
        return requestCount
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requestCount == 0
    }

    var recordedIdempotencyKeys: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return idempotencyKeys
    }
}

@Suite("Scan Publication Endpoint Transport")
@MainActor
struct ScanPublicationEndpointTransportTests {
    @Test func testExploreShareRetriesPlatformFunctionRouteNotFound() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let requestID = "019fa6ef-279f-7c7a-9e18-ec70e067a331"
        let scanID = "019fa6ef-33ab-77b1-a331-a86678f53043"
        let probe = ScanPublicationRequestProbe()

        fixture.transport.register(path: "/share-scan-to-explore") { request in
            let attempt = probe.record(
                idempotencyKey: request.value(
                    forHTTPHeaderField: "Idempotency-Key"
                )
            )
            if attempt == 1 {
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: [
                        "SB-Error-Code": "NOT_FOUND",
                        "SB-Gateway-Version": "1"
                    ]
                ))
                return (response, Data("{}".utf8))
            }

            return try NetworkEndpointTestSupport.response(
                to: request,
                json: Self.shareResponse(scanID: scanID)
            )
        }

        let result = try await fixture.client.shareScanToExplore(
            scanId: scanID,
            idempotencyKey: requestID
        )

        #expect(result.success)
        #expect(probe.count == 2)
        #expect(probe.recordedIdempotencyKeys == [requestID, requestID])
    }

    @Test func testCancelledExploreShareUsesCanonicalCancellationAndDoesNotReplay() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let requestID = "019fa6ef-2f9f-7c7a-9e18-ec70e067a331"
        let scanID = "019fa6ef-39ab-77b1-a331-a86678f53043"
        let probe = ScanPublicationRequestProbe()

        fixture.transport.register(path: "/share-scan-to-explore") { request in
            _ = probe.record(
                idempotencyKey: request.value(
                    forHTTPHeaderField: "Idempotency-Key"
                )
            )
            return try NetworkEndpointTestSupport.response(
                to: request,
                status: 503,
                json: #"{"code":"service_unavailable"}"#
            )
        }

        let requestTask = Task {
            try await fixture.client.shareScanToExplore(
                scanId: scanID,
                idempotencyKey: requestID
            )
        }
        defer { requestTask.cancel() }

        let firstRequestDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while probe.isEmpty && ContinuousClock.now < firstRequestDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(probe.count == 1)

        requestTask.cancel()
        do {
            _ = try await requestTask.value
            Issue.record("A canceled request must not survive or replay.")
        } catch is CancellationError {
            // The shared transport normalizes task-owned cancellation.
        } catch {
            Issue.record("Expected CancellationError, got \(error).")
        }
        #expect(probe.count == 1)
    }

    @Test func testExploreShareDoesNotRetryHandlerOwnedNotFound() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019fa6ef-43ab-77b1-a331-a86678f53043"
        let rawError = #"{"error":"Scan not found.","code":"not_found"}"#
        let probe = ScanPublicationRequestProbe()

        fixture.transport.register(path: "/share-scan-to-explore") { request in
            _ = probe.record(
                idempotencyKey: request.value(
                    forHTTPHeaderField: "Idempotency-Key"
                )
            )
            return try NetworkEndpointTestSupport.response(
                to: request,
                status: 404,
                json: rawError
            )
        }

        await #expect(
            throws: MerianError.httpError(
                statusCode: 404,
                message: rawError
            )
        ) {
            try await fixture.client.shareScanToExplore(
                scanId: scanID,
                idempotencyKey: "019fa6ef-4fab-7d42-84d8-74dc8b1b5bb0"
            )
        }

        #expect(probe.count == 1)
    }

    @Test func testCancelledPersistencePollPropagatesWithoutAnotherStatusRequest() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let publicationProbe = ScanPublicationRequestProbe()
        let statusProbe = ScanPublicationRequestProbe()
        let record = LocalScanRecord(
            speciesId: "persistence_poll_species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )

        fixture.transport.register(path: "/share-scan-to-explore") { request in
            _ = publicationProbe.record(
                idempotencyKey: request.value(
                    forHTTPHeaderField: "Idempotency-Key"
                )
            )
            return try NetworkEndpointTestSupport.response(
                to: request,
                status: 404,
                json: #"{"error":"Scan not found.","code":"not_found"}"#
            )
        }
        fixture.transport.register(path: "/check-scan-status") { request in
            _ = statusProbe.record(idempotencyKey: nil)
            return try NetworkEndpointTestSupport.response(
                to: request,
                json: #"{"status":"not_found","job_status":"processing"}"#
            )
        }

        let requestTask = Task {
            try await fixture.client.shareScanToExplore(scan: record)
        }
        defer { requestTask.cancel() }

        let statusDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while statusProbe.isEmpty && ContinuousClock.now < statusDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(publicationProbe.count == 1)
        #expect(statusProbe.count == 1)

        requestTask.cancel()
        do {
            _ = try await requestTask.value
            Issue.record("A canceled persistence poll must not resume recovery.")
        } catch is CancellationError {
            // Recovery preserves task-owned cancellation across its backoff.
        } catch {
            Issue.record("Expected CancellationError, got \(error).")
        }

        try await Task.sleep(for: .milliseconds(300))
        #expect(publicationProbe.count == 1)
        #expect(statusProbe.count == 1)
    }

    private static func shareResponse(scanID: String) -> String {
        """
        {
          "success": true,
          "post_id": "019fa6ef-3ba3-7acc-9dbc-a9ec785f4152",
          "scan_id": "\(scanID)",
          "shared_at": "2026-07-28T04:00:00Z",
          "location_sharing": "private",
          "publication_status": "published"
        }
        """
    }
}
