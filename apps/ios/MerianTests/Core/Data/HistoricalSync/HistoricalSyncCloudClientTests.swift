import Foundation
import Testing

@testable import Merian

@MainActor
@Suite("Historical Sync Cloud Client")
struct HistoricalSyncCloudClientTests {
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
