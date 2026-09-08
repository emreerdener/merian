import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Queue Selection Persistence")
struct QueueSelectionPersistenceTests {
    @Test func testBackgroundActorIsolatesSendablePayloadsDynamically() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let queuedScan = OfflineQueuedScan(
            capturedMediaJSON: CapturedMediaSnapshot(items: [
                .image(.documents("isolation-1.jpg")),
                .image(.documents("isolation-2.jpg"))
            ]).jsonString
        )
        context.insert(queuedScan)
        try context.save()

        let payloads = await Task.detached {
            let actor = BackgroundDatabaseActor(modelContainer: container)
            return await actor.fetchPendingScans(limit: 5)
        }.value

        #expect(payloads.count == 1)
        #expect(payloads.first?.localImagePaths.count == 2)
        #expect(payloads.first?.id == queuedScan.id)
    }

    @Test func testFetchPendingScansExcludesNonPendingScans() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let states: [ScanQueueState] = [
            .pending,
            .uploading,
            .staged,
            .inferencing,
            .failed
        ]
        let scans = states.map { state in
            OfflineQueuedScan(
                id: "queue-selection-\(state.rawValue)",
                capturedMediaJSON: CapturedMediaSnapshot(items: [
                    .image(.documents("\(state.rawValue).webp"))
                ]).jsonString,
                scanState: state
            )
        }
        for scan in scans {
            context.insert(scan)
        }
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let payloads = await actor.fetchPendingScans(limit: 10)

        #expect(payloads.map(\.id) == [scans[0].id])
    }

    @Test func pendingFetchPagesPastDelayedAndLocallyBlockedRowsWithoutStarvingRunnableWork() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let baseDate = Date().addingTimeInterval(-3_600)
        let retryAt = Date().addingTimeInterval(600)

        for index in 0..<51 {
            context.insert(OfflineQueuedScan(
                id: String(format: "delayed-%03d", index),
                timestamp: baseDate.addingTimeInterval(Double(index)),
                scanState: .pending,
                queueNextRetryAt: retryAt
            ))
        }
        let deferred = OfflineQueuedScan(
            id: "deferred-behind-delayed-page",
            timestamp: baseDate.addingTimeInterval(52),
            scanState: .pending
        )
        let blockedVideo = OfflineQueuedScan(
            id: "video-behind-delayed-page",
            timestamp: baseDate.addingTimeInterval(53),
            capturedMediaJSON: CapturedMediaSnapshot(items: [
                .video(StoredVideoMediaReference(
                    .documents("blocked-video.mp4")
                ))
            ]).jsonString,
            scanState: .pending
        )
        for index in 0..<51 {
            context.insert(OfflineQueuedScan(
                id: String(format: "empty-%03d", index),
                timestamp: baseDate.addingTimeInterval(54 + Double(index)),
                scanState: .pending
            ))
        }
        let ready = OfflineQueuedScan(
            id: "ready-behind-delayed-page",
            timestamp: baseDate.addingTimeInterval(106),
            capturedMediaJSON: CapturedMediaSnapshot(items: [
                .image(.documents("ready-image.webp"))
            ]).jsonString,
            scanState: .pending
        )
        context.insert(deferred)
        context.insert(blockedVideo)
        context.insert(ready)
        context.insert(OfflineQueuedScan(
            id: "attention-row",
            timestamp: baseDate.addingTimeInterval(-1),
            scanState: .pending,
            queueNeedsAttention: true
        ))
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let payloads = await actor.fetchPendingScans(
            limit: 2,
            excludingScanIds: [deferred.id],
            allowsVideoUploads: false
        )
        let forcedPayloads = await actor.fetchPendingScans(
            limit: 2,
            excludingScanIds: [deferred.id],
            allowsVideoUploads: false,
            forcedVideoUploadScanIds: [blockedVideo.id]
        )

        #expect(
            payloads.filter { !$0.localUploadPaths.isEmpty }.map(\.id)
                == [ready.id]
        )
        #expect(
            forcedPayloads.filter { !$0.localUploadPaths.isEmpty }.map(\.id)
                == [blockedVideo.id, ready.id]
        )
        #expect(payloads.filter { $0.localUploadPaths.isEmpty }.count == 2)
        #expect(forcedPayloads.filter { $0.localUploadPaths.isEmpty }.count == 2)
    }

    @Test func pendingFetchPrioritizesFundingAndPreservesTierOrder() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let accountId = UUID()
        let baseDate = Date().addingTimeInterval(-600)
        let rows: [(String, ScanFundingSource?)] = [
            ("immediate-flash", .immediateFlash),
            ("paid-pro", .paidPro),
            ("complimentary-pro", .complimentaryPro),
            ("unfunded-compatibility", nil),
            ("deferred-flash", .deferredFlash)
        ]

        for (index, row) in rows.enumerated() {
            let scan = OfflineQueuedScan(
                id: row.0,
                timestamp: baseDate.addingTimeInterval(Double(index)),
                capturedMediaJSON: CapturedMediaSnapshot(items: [
                    .image(.documents("\(row.0).webp"))
                ]).jsonString,
                scanState: .pending
            )
            context.insert(scan)
            if let source = row.1 {
                context.insert(OfflineJobRecord(
                    id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
                    kind: .scanIngestion,
                    subjectId: scan.id,
                    metadataJSON: try #require(
                        OfflineScanJobMetadataContract.json(
                            generation: nil,
                            funding: ScanFundingReservation(
                                accountId: accountId,
                                scanId: scan.id,
                                source: source
                            )
                        )
                    )
                ))
            }
        }
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let payloads = await actor.fetchPendingScans(limit: 4)

        #expect(payloads.map(\.id) == [
            "complimentary-pro",
            "unfunded-compatibility",
            "paid-pro",
            "immediate-flash"
        ])
    }

    @Test func emptyPendingQuarantineIsAtomicAndStateBound() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let emptyPendingWithJob = OfflineQueuedScan(scanState: .pending)
        let emptyPendingWithoutJob = OfflineQueuedScan(scanState: .pending)
        let mediaPending = OfflineQueuedScan(
            capturedMediaJSON: CapturedMediaSnapshot(items: [
                .image(.documents("retained-image.webp"))
            ]).jsonString,
            scanState: .pending
        )
        let advancedEmpty = OfflineQueuedScan(scanState: .staged)
        let attentionEmpty = OfflineQueuedScan(
            scanState: .pending,
            queueNeedsAttention: true
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(
                scanId: emptyPendingWithJob.id
            ),
            kind: .scanIngestion,
            subjectId: emptyPendingWithJob.id
        )
        for scan in [
            emptyPendingWithJob,
            emptyPendingWithoutJob,
            mediaPending,
            advancedEmpty,
            attentionEmpty
        ] {
            context.insert(scan)
        }
        context.insert(job)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let quarantined = await actor.quarantineEmptyPendingScans(
            scanIds: [
                emptyPendingWithJob.id,
                emptyPendingWithoutJob.id,
                mediaPending.id,
                advancedEmpty.id,
                attentionEmpty.id
            ]
        )

        let readContext = ModelContext(container)
        let rows = try readContext.fetch(FetchDescriptor<OfflineQueuedScan>())
        let stateById = Dictionary(uniqueKeysWithValues: rows.map {
            ($0.id, ($0.queueState, $0.queueNeedsAttention))
        })
        let jobs = try readContext.fetch(FetchDescriptor<OfflineJobRecord>())
        let events = try readContext.fetch(FetchDescriptor<OfflineQueueEvent>())
        #expect(quarantined == Set([
            emptyPendingWithJob.id,
            emptyPendingWithoutJob.id
        ]))
        #expect(stateById[emptyPendingWithJob.id]?.0 == .failed)
        #expect(stateById[emptyPendingWithJob.id]?.1 == true)
        #expect(stateById[emptyPendingWithoutJob.id]?.0 == .failed)
        #expect(stateById[emptyPendingWithoutJob.id]?.1 == true)
        #expect(stateById[mediaPending.id]?.0 == .pending)
        #expect(stateById[advancedEmpty.id]?.0 == .staged)
        #expect(stateById[attentionEmpty.id]?.0 == .pending)
        #expect(jobs.first?.status == .needsAttention)
        #expect(jobs.first?.lastErrorCode == "queued_media_missing")
        #expect(events.count == 2)
        #expect(Set(events.compactMap(\.scanId)) == Set([
            emptyPendingWithJob.id,
            emptyPendingWithoutJob.id
        ]))
        #expect(events.allSatisfy {
            $0.errorCode == "queued_media_missing"
        })
    }
}
