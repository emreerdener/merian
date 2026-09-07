import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct OfflineQueueManagerTests {
    private struct ConsentResumeCandidate {
        let scanID: String
        let ownerID: UUID
        let errorCode: String
        let updatedAt: Date
    }

    private struct ConsentBlockedRow {
        let scanID: String
        let metadataJSON: String?
        let updatedAt: Date
    }

    @Test func queueDiagnosticsExportOmitsPrivateAndFreeFormValues() throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        defer {
            manager.modelContext = originalContext
        }

        let context = try createIsolatedContext()
        let scanId = UUID().uuidString.lowercased()
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let privatePath = "PRIVATE-MEDIA-PATH-\(UUID().uuidString).webp"
        let privateDescription = "PRIVATE-DESCRIPTION-\(UUID().uuidString)"
        let privateNotes = "PRIVATE-FIELD-NOTES-\(UUID().uuidString)"
        let privateLocation = "PRIVATE-LOCATION-\(UUID().uuidString)"
        let privateMessage = "PRIVATE-ERROR-MESSAGE-\(UUID().uuidString)"
        let privateMetadata = "PRIVATE-METADATA-\(UUID().uuidString)"
        let privateMachineField =
            "PRIVATE-MACHINE-FIELD-\(UUID().uuidString) / raw"
        let mediaJSON = CapturedMediaSnapshot(items: [
            .image(.documents(privatePath)),
            .description(ObservationContext(
                freeText: privateDescription
            ))
        ]).jsonString

        let scan = OfflineQueuedScan(
            id: scanId,
            capturedMediaJSON: mediaJSON,
            coverImagePath: privatePath,
            gpsLatitude: 39.781721,
            gpsLongitude: -89.650148,
            locationName: privateLocation,
            fieldNotes: privateNotes,
            queueLastErrorCode: "upload_http_503",
            queueLastErrorMessage: privateMessage,
            queueLastHTTPStatus: 503,
            queueLastServerStatus: "failed_retryable",
            queueLastServerStage: "background_ingestion_failed"
        )
        let job = OfflineJobRecord(
            id: jobId,
            kind: .scanIngestion,
            subjectId: scanId,
            status: .waiting,
            lastErrorCode: "upload_http_503",
            lastErrorMessage: privateMessage,
            lastHTTPStatus: 503,
            serverStatus: privateMachineField,
            serverStage: privateMachineField,
            metadataJSON: #"{"private":"\#(privateMetadata)"}"#
        )
        let event = OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .retryScheduled,
            message: privateMessage,
            errorCode: privateMachineField,
            httpStatus: 503,
            metadataJSON: #"{"private":"\#(privateMetadata)"}"#
        )
        context.insert(scan)
        context.insert(job)
        context.insert(event)
        try context.save()

        let exportURL = try manager.writeQueueDiagnosticsExport()
        defer {
            try? FileManager.default.removeItem(at: exportURL)
        }
        let exportData = try Data(contentsOf: exportURL)
        let exportText = try #require(String(
            data: exportData,
            encoding: .utf8
        ))
        let exportObject = try #require(
            JSONSerialization.jsonObject(with: exportData) as? [String: Any]
        )

        for privateValue in [
            privatePath,
            privateDescription,
            privateNotes,
            privateLocation,
            privateMessage,
            privateMetadata,
            privateMachineField,
            "39.781721",
            "-89.650148"
        ] {
            #expect(!exportText.contains(privateValue))
        }
        #expect(exportText.contains(scanId))
        #expect(exportObject["formatVersion"] as? Int == 1)
        #expect(exportText.contains("upload_http_503"))
        #expect(exportText.contains("failed_retryable"))
        #expect(exportText.contains("background_ingestion_failed"))
        #expect(exportText.contains(OfflineQueueEventKind.retryScheduled.rawValue))
        for provenanceKey in [
            "version",
            "build",
            "sourceRevision",
            "sourceFingerprint",
            "sourceState"
        ] {
            #expect(exportText.contains(#""\#(provenanceKey)""#))
        }
    }

    @Test func queueDiagnosticsRowLimitsAlwaysStayWithinOneThroughFiveHundred() throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        defer {
            manager.modelContext = originalContext
        }

        let context = try createIsolatedContext()
        for index in 0..<510 {
            context.insert(OfflineJobRecord(
                id: "diagnostics-job-\(index)",
                kind: .future,
                updatedAt: Date(
                    timeIntervalSince1970: TimeInterval(index)
                )
            ))
            context.insert(OfflineQueuedScan(
                id: UUID().uuidString.lowercased(),
                timestamp: Date(
                    timeIntervalSince1970: TimeInterval(index)
                )
            ))
            context.insert(OfflineQueueEvent(
                kind: .diagnostics,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        try context.save()

        let maximumURL = try manager.writeQueueDiagnosticsExport(
            eventLimit: .max
        )
        defer {
            try? FileManager.default.removeItem(at: maximumURL)
        }
        let maximumData = try Data(contentsOf: maximumURL)
        let maximumObject = try #require(
            JSONSerialization.jsonObject(with: maximumData) as? [String: Any]
        )
        let maximumEvents = try #require(
            maximumObject["events"] as? [[String: Any]]
        )
        let maximumJobs = try #require(
            maximumObject["jobs"] as? [[String: Any]]
        )
        let maximumScans = try #require(
            maximumObject["scans"] as? [[String: Any]]
        )
        #expect(maximumEvents.count == 500)
        #expect(maximumJobs.count == 500)
        #expect(maximumScans.count == 500)

        let minimumURL = try manager.writeQueueDiagnosticsExport(eventLimit: 0)
        defer {
            try? FileManager.default.removeItem(at: minimumURL)
        }
        let minimumData = try Data(contentsOf: minimumURL)
        let minimumObject = try #require(
            JSONSerialization.jsonObject(with: minimumData) as? [String: Any]
        )
        let minimumEvents = try #require(
            minimumObject["events"] as? [[String: Any]]
        )
        #expect(minimumEvents.count == 1)
    }

    @MainActor
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        OfflineQueueManager.shared.modelContext = context
        return context
    }

    @Test func testInferencePreparationIsSingleFlightAndCompareCleared() throws {
        let manager = OfflineQueueManager.shared
        let scanId = "preparation-generation-test"
        manager.inferencePreparationGenerations[scanId] = nil
        defer {
            manager.inferencePreparationGenerations[scanId] = nil
        }

        let firstGeneration = try #require(
            manager.beginInferencePreparation(scanId: scanId)
        )
        let replacementAttempt = manager.beginInferencePreparation(scanId: scanId)

        #expect(replacementAttempt == nil)

        manager.clearInferencePreparation(
            scanId: scanId,
            generation: UUID()
        )
        #expect(manager.inferencePreparationGenerations[scanId] == firstGeneration)

        manager.clearInferencePreparation(
            scanId: scanId,
            generation: firstGeneration
        )
        #expect(manager.inferencePreparationGenerations[scanId] == nil)
    }

    @Test func testRetryQueuedScanNow_MakesFailedVisualScanRunnable() async throws {
        let ctx = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalIsOnline = manager.isOnline
        defer { manager.isOnline = originalIsOnline }
        manager.isOnline = false

        let scanId = UUID().uuidString
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .failed,
            inferenceImagePaths: ["retry-image.webp"],
            queueAttemptCount: 2,
            queueNextRetryAt: Date().addingTimeInterval(600),
            queueLastErrorCode: "upload_failed",
            queueLastErrorMessage: "Upload failed.",
            queueNeedsAttention: true
        )
        ctx.insert(scan)
        try ctx.save()

        let didRetry = manager.retryQueuedScanNow(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(didRetry)
        #expect(fetched.queueState == .pending, "Visual failed scans must become runnable pending uploads")
        #expect(fetched.queueNextRetryAt == nil)
        #expect(fetched.queueLastErrorCode == nil)
        #expect(fetched.queueLastErrorMessage == nil)
        #expect(fetched.queueAttemptCount == 0)
        #expect(!fetched.queueNeedsAttention)
    }

    @Test func consentReapprovalResumesOnlyNewestOwnedFundedScan() throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let ctx = try createIsolatedContext()
        defer {
            manager.isOnline = originalIsOnline
            manager.modelContext = originalContext
        }
        manager.isOnline = false

        let accountId = UUID()
        let otherAccountId = UUID()
        let olderOwnedId = UUID().uuidString.lowercased()
        let newestOwnedId = UUID().uuidString.lowercased()
        let newerOtherAccountId = UUID().uuidString.lowercased()
        let newestUnrelatedId = UUID().uuidString.lowercased()

        let candidates = [
            ConsentResumeCandidate(
                scanID: olderOwnedId,
                ownerID: accountId,
                errorCode: "ai_consent_required",
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            ConsentResumeCandidate(
                scanID: newestOwnedId,
                ownerID: accountId,
                errorCode: "ai_consent_required",
                updatedAt: Date(timeIntervalSince1970: 200)
            ),
            ConsentResumeCandidate(
                scanID: newerOtherAccountId,
                ownerID: otherAccountId,
                errorCode: "ai_consent_required",
                updatedAt: Date(timeIntervalSince1970: 300)
            ),
            ConsentResumeCandidate(
                scanID: newestUnrelatedId,
                ownerID: accountId,
                errorCode: "upload_http_403",
                updatedAt: Date(timeIntervalSince1970: 400)
            )
        ]
        for candidate in candidates {
            let scan = OfflineQueuedScan(
                id: candidate.scanID,
                scanState: .failed,
                inferenceImagePaths: ["\(candidate.scanID).webp"],
                queueLastErrorCode: candidate.errorCode,
                queueUpdatedAt: candidate.updatedAt,
                queueNeedsAttention: true
            )
            let funding = ScanFundingReservation(
                accountId: candidate.ownerID,
                scanId: candidate.scanID,
                source: .complimentaryPro,
                createdAt: candidate.updatedAt
            )
            let job = OfflineJobRecord(
                id: OfflineQueueManager.scanIngestionJobId(
                    scanId: candidate.scanID
                ),
                kind: .scanIngestion,
                subjectId: candidate.scanID,
                status: .needsAttention,
                updatedAt: candidate.updatedAt,
                lastErrorCode: candidate.errorCode,
                metadataJSON: try #require(
                    OfflineScanJobMetadataContract.json(
                        generation: nil,
                        funding: funding
                    )
                )
            )
            ctx.insert(scan)
            ctx.insert(job)
        }
        try ctx.save()

        let resumedScanId = manager.resumeMostRecentConsentBlockedScan(
            accountId: accountId
        )

        let scans = try ctx.fetch(FetchDescriptor<OfflineQueuedScan>())
        let scansById = Dictionary(uniqueKeysWithValues: scans.map { ($0.id, $0) })
        #expect(resumedScanId == newestOwnedId)
        #expect(scansById[newestOwnedId]?.queueState == .pending)
        #expect(scansById[newestOwnedId]?.queueLastErrorCode == nil)
        #expect(scansById[newestOwnedId]?.queueNeedsAttention == false)
        #expect(scansById[olderOwnedId]?.queueState == .failed)
        #expect(scansById[olderOwnedId]?.queueNeedsAttention == true)
        #expect(scansById[newerOtherAccountId]?.queueState == .failed)
        #expect(scansById[newerOtherAccountId]?.queueNeedsAttention == true)
        #expect(scansById[newestUnrelatedId]?.queueState == .failed)
        #expect(scansById[newestUnrelatedId]?.queueNeedsAttention == true)
    }

    @Test func consentReapprovalSkipsUnownedOrUnfundedScans() throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let ctx = try createIsolatedContext()
        defer {
            manager.isOnline = originalIsOnline
            manager.modelContext = originalContext
        }
        manager.isOnline = false

        let accountId = UUID()
        let releasedId = UUID().uuidString.lowercased()
        let missingFundingId = UUID().uuidString.lowercased()
        let mismatchedId = UUID().uuidString.lowercased()
        let deferredId = UUID().uuidString.lowercased()
        let fundedMetadata = try #require(
            OfflineScanJobMetadataContract.json(
                generation: nil,
                funding: ScanFundingReservation(
                    accountId: accountId,
                    scanId: releasedId,
                    source: .complimentaryPro
                )
            )
        )
        let releasedMetadata = try #require(
            OfflineScanJobMetadataContract.markingFundingReleased(
                in: fundedMetadata
            )
        )
        let rows = [
            ConsentBlockedRow(
                scanID: releasedId,
                metadataJSON: releasedMetadata,
                updatedAt: Date(timeIntervalSince1970: 400)
            ),
            ConsentBlockedRow(
                scanID: missingFundingId,
                metadataJSON: nil,
                updatedAt: Date(timeIntervalSince1970: 300)
            ),
            ConsentBlockedRow(
                scanID: mismatchedId,
                metadataJSON: try #require(
                    OfflineScanJobMetadataContract.json(
                        generation: nil,
                        funding: ScanFundingReservation(
                            accountId: accountId,
                            scanId: UUID().uuidString,
                            source: .complimentaryPro
                        )
                    )
                ),
                updatedAt: Date(timeIntervalSince1970: 200)
            ),
            ConsentBlockedRow(
                scanID: deferredId,
                metadataJSON: try #require(
                    OfflineScanJobMetadataContract.json(
                        generation: nil,
                        funding: ScanFundingReservation(
                            accountId: accountId,
                            scanId: deferredId,
                            source: .deferredFlash
                        )
                    )
                ),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        ]
        for row in rows {
            ctx.insert(OfflineQueuedScan(
                id: row.scanID,
                scanState: .failed,
                inferenceImagePaths: ["\(row.scanID).webp"],
                queueLastErrorCode: "ai_consent_required",
                queueUpdatedAt: row.updatedAt,
                queueNeedsAttention: true
            ))
            ctx.insert(OfflineJobRecord(
                id: OfflineQueueManager.scanIngestionJobId(
                    scanId: row.scanID
                ),
                kind: .scanIngestion,
                subjectId: row.scanID,
                status: .needsAttention,
                updatedAt: row.updatedAt,
                lastErrorCode: "ai_consent_required",
                metadataJSON: row.metadataJSON
            ))
        }
        try ctx.save()

        let resumedScanId = manager.resumeMostRecentConsentBlockedScan(
            accountId: accountId
        )

        let scans = try ctx.fetch(FetchDescriptor<OfflineQueuedScan>())
        #expect(resumedScanId == nil)
        #expect(scans.allSatisfy { $0.queueState == .failed })
        #expect(scans.allSatisfy { $0.queueNeedsAttention })
    }

    @Test func testRetryQueuedScanNowRejectsLegacyExternalImport() throws {
        let ctx = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        let scanId = UUID().uuidString.lowercased()
        let retryAt = Date().addingTimeInterval(600)
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .externalImport,
            queueAttemptCount: 2,
            queueNextRetryAt: retryAt,
            queueLastErrorCode: "legacy_external_import",
            queueLastErrorMessage: "This legacy row cannot be replayed.",
            queueNeedsAttention: true
        )
        ctx.insert(scan)
        try ctx.save()

        let didRetry = manager.retryQueuedScanNow(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(!didRetry)
        #expect(fetched.queueState == .externalImport)
        #expect(fetched.queueAttemptCount == 2)
        #expect(fetched.queueNextRetryAt == retryAt)
        #expect(fetched.queueLastErrorCode == "legacy_external_import")
        #expect(fetched.queueNeedsAttention)
    }

    @Test func testManualRetryResetsBudgetForDescriptionOnlyScan() async throws {
        let ctx = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalIsOnline = manager.isOnline
        defer { manager.isOnline = originalIsOnline }
        manager.isOnline = false

        let scanId = UUID().uuidString.lowercased()
        let capturedMediaJSON = try #require(
            CapturedMediaSnapshot(items: [
                .description(
                    ObservationContext(freeText: "Perched beside the trail")
                )
            ]).jsonString
        )
        let scan = OfflineQueuedScan(
            id: scanId,
            capturedMediaJSON: capturedMediaJSON,
            scanState: .failed,
            queueAttemptCount:
                OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts,
            queueLastErrorCode: "automatic_retry_limit_reached",
            queueNeedsAttention: true
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .needsAttention,
            attemptCount:
                OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts,
            lastErrorCode: "automatic_retry_limit_reached"
        )
        ctx.insert(scan)
        ctx.insert(job)
        try ctx.save()

        let didRetry = manager.retryQueuedScanNow(scanId: scanId)

        let fetchedScan = try #require(
            ctx.fetch(
                FetchDescriptor<OfflineQueuedScan>(
                    predicate: #Predicate { $0.id == scanId }
                )
            ).first
        )
        let jobId = job.id
        let fetchedJob = try #require(
            ctx.fetch(
                FetchDescriptor<OfflineJobRecord>(
                    predicate: #Predicate { $0.id == jobId }
                )
            ).first
        )
        #expect(didRetry)
        #expect(fetchedScan.queueState == .staged)
        #expect(fetchedScan.queueAttemptCount == 0)
        #expect(fetchedScan.queueLastErrorCode == nil)
        #expect(!fetchedScan.queueNeedsAttention)
        #expect(fetchedJob.status == .pending)
        #expect(fetchedJob.attemptCount == 0)
        #expect(fetchedJob.lastErrorCode == nil)
    }

    @Test func testManualRetryResumesCompletedServerResultRecovery() async throws {
        let ctx = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalIsOnline = manager.isOnline
        defer { manager.isOnline = originalIsOnline }
        manager.isOnline = false

        let scanId = UUID().uuidString
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .failed,
            inferenceImagePaths: ["already-analyzed.webp"],
            queueAttemptCount: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts,
            queueLastErrorCode:
                OfflineQueueManager.completedServerResultContractMismatchCode,
            queueLastErrorMessage: "Local recovery paused.",
            queueNeedsAttention: true
        )
        scan.queueLastServerStatus = "complete"
        ctx.insert(scan)
        try ctx.save()

        let didRetry = manager.retryQueuedScanNow(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(didRetry)
        #expect(fetched.queueState == .inferencing)
        #expect(fetched.queueLastServerStatus == "complete")
        #expect(
            fetched.queueLastErrorCode
                == OfflineQueueManager.completedServerResultRecoveryCode
        )
        #expect(manager.hasDurableCompletedServerResult(scanId: scanId))
        #expect(!fetched.queueNeedsAttention)
    }

    @Test func persistedScanRetryRestoresAnActualSchedulerWake() throws {
        let manager = OfflineQueueManager.shared
        let scheduler = OfflineJobScheduler.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let context = try createIsolatedContext()
        let now = Date()
        let retryAt = now.addingTimeInterval(90)
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.isOnline = originalIsOnline
            manager.modelContext = originalContext
        }

        manager.modelContext = context
        manager.isOnline = true
        scheduler.cancelScheduledWake()

        let scheduled = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            timestamp: now,
            scanState: .staged,
            queueNextRetryAt: retryAt
        )
        let ignoredNeedsAttention = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            timestamp: now,
            scanState: .staged,
            queueNextRetryAt: now.addingTimeInterval(10),
            queueNeedsAttention: true
        )
        let ignoredFailed = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            timestamp: now,
            scanState: .failed,
            queueNextRetryAt: now.addingTimeInterval(5)
        )
        context.insert(scheduled)
        context.insert(ignoredNeedsAttention)
        context.insert(ignoredFailed)
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(
                scanId: ignoredNeedsAttention.id
            ),
            kind: .scanIngestion,
            subjectId: ignoredNeedsAttention.id,
            status: .waiting,
            nextRunAt: now.addingTimeInterval(10)
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(
                scanId: ignoredFailed.id
            ),
            kind: .scanIngestion,
            subjectId: ignoredFailed.id,
            status: .waiting,
            nextRunAt: now.addingTimeInterval(5)
        ))
        context.insert(OfflineJobRecord(
            id: "test-collection-retry",
            kind: .collectionSync,
            status: .waiting,
            nextRunAt: now.addingTimeInterval(120)
        ))
        try context.save()

        let persistedWake = try #require(
            scheduler.nextPersistedWakeDate(using: manager)
        )
        #expect(abs(persistedWake.timeIntervalSince(retryAt)) < 0.1)

        scheduler.scheduleNextPersistedWake(using: manager, now: now)

        let wakeDate = try #require(scheduler.scheduledWakeDate)
        #expect(abs(wakeDate.timeIntervalSince(retryAt)) < 0.1)
        #expect(QueuedScanContext(from: scheduled).canRetryNow)
    }

    @Test func retryUpdateReportsOnlyCommittedPersistence() throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        defer { manager.modelContext = originalContext }

        manager.modelContext = nil
        #expect(
            manager.updateQueuedScanForRetry(
                scanId: UUID().uuidString.lowercased(),
                code: "test_retry",
                message: "Test retry",
                delay: 5,
                resetTo: .pending
            ) == nil
        )

        let context = try createIsolatedContext()
        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            timestamp: Date(),
            scanState: .uploading
        )
        context.insert(scan)
        try context.save()

        let attempt = manager.updateQueuedScanForRetry(
            scanId: scan.id,
            code: "test_retry",
            message: "Test retry",
            delay: 5,
            resetTo: .pending
        )
        #expect(attempt == 1)
        #expect(scan.queueAttemptCount == 1)
        #expect(scan.queueState == .pending)
        #expect(scan.queueNextRetryAt != nil)
    }

    @Test func stalePersistedRetrySchedulesImmediateBoundedWake() throws {
        let manager = OfflineQueueManager.shared
        let scheduler = OfflineJobScheduler.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let context = try createIsolatedContext()
        let now = Date()
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.isOnline = originalIsOnline
            manager.modelContext = originalContext
        }

        manager.modelContext = context
        manager.isOnline = true
        scheduler.cancelScheduledWake()
        context.insert(OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            timestamp: now,
            scanState: .staged,
            queueNextRetryAt: now.addingTimeInterval(-60)
        ))
        try context.save()

        scheduler.scheduleNextPersistedWake(using: manager, now: now)

        let wakeDate = try #require(scheduler.scheduledWakeDate)
        #expect(wakeDate.timeIntervalSince(now) >= 0.9)
        #expect(wakeDate.timeIntervalSince(now) <= 1.1)
    }

    @Test func testDeleteQueuedScan_RemovesDatabaseRecord() async throws {
        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString

        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        )
        ctx.insert(scan)
        try ctx.save()

        await OfflineQueueManager.shared.deleteQueuedScan(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched == nil, "Scan record must be deleted from the context")
    }

}
