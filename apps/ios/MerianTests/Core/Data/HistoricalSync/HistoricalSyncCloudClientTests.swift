import Foundation
import Supabase
import Testing

@testable import Merian

@MainActor
@Suite("Historical Sync Cloud Client")
struct HistoricalSyncCloudClientTests {
    @Test func sdkTestSessionStorageIsIsolatedPerClient() throws {
        let first = MerianSupabaseClientFactory.makeAuthStorage()
        let second = MerianSupabaseClientFactory.makeAuthStorage()
        let key = "synthetic-session"
        let value = Data("synthetic-test-value".utf8)
        try first.store(key: key, value: value)
        #expect(try first.retrieve(key: key) == value)
        #expect(try second.retrieve(key: key) == nil)
        try first.remove(key: key)
        #expect(try first.retrieve(key: key) == nil)
    }

    @Test func sdkScanReadsCarryTheResultReaderCapability() async throws {
        let transport = ScopedMockTransport()
        let session = transport.makeSession()
        defer { session.invalidateAndCancel() }
        transport.register(path: "/rest/v1/scans") { request in
            #expect(request.value(forHTTPHeaderField: "X-Merian-Identification-Protocol") == "6")
            #expect(request.value(forHTTPHeaderField: "X-Merian-Identification-Recipient") == nil)
            #expect(request.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == nil)
            let url = try #require(request.url)
            return (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), Data("[]".utf8))
        }
        let client = MerianSupabaseClientFactory.makeClient(session: session)
        let page = try await client.from("scans").select("id, identification_provenance")
            .range(from: 0, to: 199).execute().data
        #expect(page == Data("[]".utf8))
        let record = try await client.from("scans").select("id, identification_provenance")
            .eq("id", value: "00000000-0000-0000-0000-00000000bc13")
            .limit(1).execute().data
        #expect(record == Data("[]".utf8))
    }

    @Test func sdkCompatibilityFailureMatchesTheNativeClassifier() async throws {
        let transport = ScopedMockTransport()
        let session = transport.makeSession()
        defer { session.invalidateAndCancel() }
        transport.register(path: "/rest/v1/scans") { request in
            let url = try #require(request.url)
            return (
                try #require(HTTPURLResponse(url: url, statusCode: 426, httpVersion: nil, headerFields: nil)),
                Data(#"{"code":"PT426","message":"client_update_required","details":null,"hint":"Update the app"}"#.utf8)
            )
        }
        let client = MerianSupabaseClientFactory.makeClient(session: session)
        do {
            _ = try await client.from("scans").select("id").execute().data
            Issue.record("Expected the SDK to surface the compatibility denial")
        } catch {
            #expect(ClientUpdateRequiredPolicy.matches(error))
        }
    }

    @Test func forwardsLeaseAndRequestValuesThroughInjectedHandlers() async throws {
        let lease = AccountBoundWorkLease(
            id: UUID(),
            session: AuthTransitionSession(
                userID: UUID(),
                isAnonymous: false
            )
        )
        let scanPageRequest = HistoricalScanPageRequest(
            userID: lease.session.userID.uuidString,
            offset: 200,
            pageSize: 200
        )
        let scanRequest = HistoricalScanRecordRequest(
            userID: lease.session.userID.uuidString,
            scanID: "scan-id"
        )
        let collectionRequest = HistoricalCollectionPageRequest(
            userID: lease.session.userID.uuidString,
            offset: 100,
            pageSize: 100
        )
        var finishedLease: AccountBoundWorkLease?
        var receivedScanPageRequest: HistoricalScanPageRequest?
        var receivedScanRequest: HistoricalScanRecordRequest?
        var receivedCollectionRequest: HistoricalCollectionPageRequest?

        let client = HistoricalSyncCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { finishedLease = $0 },
            isAccountWorkCurrent: { $0 == lease },
            fetchScanPage: { request in
                receivedScanPageRequest = request
                return Data("[]".utf8)
            },
            fetchScan: { request in
                receivedScanRequest = request
                return Data("[]".utf8)
            },
            fetchCollectionPage: { request in
                receivedCollectionRequest = request
                return []
            }
        )

        let activeLease = try client.beginAccountWork()
        #expect(activeLease == lease)
        #expect(client.isAccountWorkCurrent(activeLease))
        #expect(try await client.fetchScanPage(scanPageRequest) == Data("[]".utf8))
        #expect(try await client.fetchScan(scanRequest) == Data("[]".utf8))
        #expect(try await client.fetchCollectionPage(collectionRequest).isEmpty)
        client.finishAccountWork(activeLease)

        #expect(finishedLease == lease)
        #expect(receivedScanPageRequest == scanPageRequest)
        #expect(receivedScanRequest == scanRequest)
        #expect(receivedCollectionRequest == collectionRequest)
    }
}
