import Foundation
import SwiftData

enum OfflineQueueRetryDisposition: Equatable {
    case success
    case retry(after: TimeInterval, code: String, message: String?)
    case waitForServer(after: TimeInterval, code: String, message: String?)
    case needsAttention(code: String, message: String?)
    case terminal(code: String, message: String?)
}

enum OfflineQueueRetryPolicy {
    static let maximumAutomaticRetryAttempts = 10
    static let maximumRetryDelay: TimeInterval = 15 * 60
    static let retryJitterFraction = 0.2

    static func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt)
        let base = pow(2.0, Double(exponent))
        return min(maximumRetryDelay, max(5, base))
    }

    static func jitteredDelay(forAttempt attempt: Int) -> TimeInterval {
        let baseDelay = delay(forAttempt: attempt)
        let multiplier = Double.random(in: (1 - retryJitterFraction)...(1 + retryJitterFraction))
        return min(maximumRetryDelay, max(5, baseDelay * multiplier))
    }

    static func canScheduleAutomaticRetry(currentAttempt: Int) -> Bool {
        currentAttempt < maximumAutomaticRetryAttempts
    }

    static func automaticRetryLimitMessage() -> String {
        [
            "Naturebook retried this scan several times and paused automatic retry.",
            "You can retry manually when the connection or Naturebook service is stable."
        ].joined(separator: " ")
    }

    static func classifyUpload(error: Error?, statusCode: Int?, currentAttempt: Int) -> OfflineQueueRetryDisposition {
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorFileDoesNotExist, NSURLErrorCannotOpenFile:
                    return .needsAttention(
                        code: "local_media_missing",
                        message: "A local media file is missing. Keep the queued scan so the user can retry after restoring or cancel it."
                    )
                case NSURLErrorTimedOut,
                     NSURLErrorNetworkConnectionLost,
                     NSURLErrorNotConnectedToInternet,
                     NSURLErrorDataNotAllowed,
                     NSURLErrorInternationalRoamingOff:
                    return retryOrPause(
                        currentAttempt: currentAttempt,
                        code: "network_unavailable",
                        message: error.localizedDescription
                    )
                default:
                    return retryOrPause(
                        currentAttempt: currentAttempt,
                        code: "upload_transport_error",
                        message: error.localizedDescription
                    )
                }
            }
            return retryOrPause(
                currentAttempt: currentAttempt,
                code: "upload_error",
                message: error.localizedDescription
            )
        }

        guard let statusCode else {
            return retryOrPause(
                currentAttempt: currentAttempt,
                code: "upload_missing_status",
                message: "The upload finished without an HTTP status."
            )
        }

        if statusCode == 200 { return .success }
        if [408, 409, 425, 429, 500, 502, 503, 504].contains(statusCode) {
            return retryOrPause(
                currentAttempt: currentAttempt,
                code: "upload_http_\(statusCode)",
                message: "The media upload endpoint returned HTTP \(statusCode)."
            )
        }

        return .needsAttention(
            code: "upload_rejected_http_\(statusCode)",
            message: "The media upload endpoint permanently rejected the queued media with HTTP \(statusCode)."
        )
    }

    private static func retryOrPause(
        currentAttempt: Int,
        code: String,
        message: String?
    ) -> OfflineQueueRetryDisposition {
        guard canScheduleAutomaticRetry(currentAttempt: currentAttempt) else {
            return .needsAttention(
                code: "automatic_retry_limit_reached",
                message: automaticRetryLimitMessage()
            )
        }
        return .retry(
            after: jitteredDelay(forAttempt: currentAttempt + 1),
            code: code,
            message: message
        )
    }
}

enum OfflineQueueStoragePolicy {
    static func canAdmitNewPayload(estimatedBytes: Int64, documentsDirectory: URL = .documentsDirectory) -> Bool {
        guard estimatedBytes <= MerianConfig.offlineQueueSinglePayloadSoftLimitBytes else { return false }
        let available = availableBytes(at: documentsDirectory)
        guard available > 0 else { return true }
        return available - estimatedBytes >= MerianConfig.offlineQueueMinimumFreeDiskBytes
    }

    private static func availableBytes(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return 0
        }
        return available
    }
}

enum OfflineQueueDiagnosticsExportError: LocalizedError {
    case missingModelContext

    var errorDescription: String? {
        switch self {
        case .missingModelContext:
            return "The offline queue database is not available."
        }
    }
}

private struct OfflineQueueDiagnosticsExport: Encodable {
    let exportedAt: Date
    let jobs: [OfflineQueueDiagnosticsJob]
    let scans: [OfflineQueueDiagnosticsScan]
    let events: [OfflineQueueDiagnosticsEvent]
}

private struct OfflineQueueDiagnosticsJob: Encodable {
    let id: String
    let kind: String
    let subjectId: String?
    let priority: Int
    let status: String
    let createdAt: Date
    let updatedAt: Date
    let lastAttemptAt: Date?
    let nextRunAt: Date?
    let attemptCount: Int
    let lastErrorCode: String?
    let lastErrorMessage: String?
    let lastHTTPStatus: Int?
    let serverStatus: String?
    let serverStage: String?
    let serverRetryAfter: Date?
    let requiresUnconstrainedNetwork: Bool
    let allowsCellular: Bool
    let approximateBytes: Int64
}

private struct OfflineQueueDiagnosticsScan: Encodable {
    let id: String
    let queueState: String
    let timestamp: Date
    let attemptCount: Int
    let lastAttemptAt: Date?
    let nextRetryAt: Date?
    let lastErrorCode: String?
    let lastErrorMessage: String?
    let lastHTTPStatus: Int?
    let lastServerStatus: String?
    let lastServerStage: String?
    let lastServerRetryAfter: Date?
    let updatedAt: Date
    let needsAttention: Bool
    let mediaKinds: [String]
    let approximateBytes: Int64
}

private struct OfflineQueueDiagnosticsEvent: Encodable {
    let id: String
    let jobId: String?
    let scanId: String?
    let kind: String
    let createdAt: Date
    let message: String?
    let errorCode: String?
    let httpStatus: Int?
    let hasMetadata: Bool
}

extension ModelContext {
    @discardableResult
    func ensureOfflineJobRecord(
        id: String,
        kind: OfflineJobKind,
        subjectId: String? = nil,
        priority: Int = 0,
        approximateBytes: Int64 = 0,
        requiresUnconstrainedNetwork: Bool = false,
        allowsCellular: Bool = true,
        metadataJSON: String? = nil
    ) throws -> OfflineJobRecord {
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let existing = try fetch(descriptor).first {
            existing.kind = kind
            existing.subjectId = subjectId
            existing.priority = priority
            existing.status = existing.status == .complete ? .pending : existing.status
            existing.updatedAt = Date()
            existing.approximateBytes = approximateBytes
            existing.requiresUnconstrainedNetwork = requiresUnconstrainedNetwork
            existing.allowsCellular = allowsCellular
            existing.metadataJSON = metadataJSON
            return existing
        }

        let record = OfflineJobRecord(
            id: id,
            kind: kind,
                subjectId: subjectId,
                priority: priority,
                requiresUnconstrainedNetwork: requiresUnconstrainedNetwork,
                allowsCellular: allowsCellular,
                approximateBytes: approximateBytes,
                metadataJSON: metadataJSON
            )
        insert(record)
        return record
    }
}

@MainActor
extension OfflineQueueManager {
    static var completedServerResultRecoveryCode: String {
        "server_result_local_recovery_pending"
    }

    static var completedServerResultRecoveryMessage: String {
        "The completed cloud analysis could not be restored locally yet."
    }

    static func isCompletedServerResultRecoveryCode(_ code: String?) -> Bool {
        code?.hasPrefix("server_result_local_recovery") == true
    }

    func hasDurableCompletedServerResult(scanId: String) -> Bool {
        guard let context = modelContext else { return false }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard let scan = (try? context.fetch(descriptor))?.first else {
            return false
        }
        return Self.isCompletedServerResultRecoveryCode(
            scan.queueLastErrorCode
        )
    }

    nonisolated static func scanIngestionJobId(scanId: String) -> String {
        "scan-ingestion:\(scanId)"
    }

    nonisolated static var collectionSyncJobId: String {
        "collection-sync"
    }

    func bootstrapOfflineJobBridgeIfNeeded() {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync) else { return }
        markCollectionSyncPending()
    }

    func recordQueueEvent(
        scanId: String? = nil,
        jobId: String? = nil,
        kind: OfflineQueueEventKind,
        message: String? = nil,
        errorCode: String? = nil,
        httpStatus: Int? = nil,
        metadataJSON: String? = nil
    ) {
        guard let context = modelContext else { return }
        let event = OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: kind,
            message: message,
            errorCode: errorCode,
            httpStatus: httpStatus,
            metadataJSON: metadataJSON
        )
        context.insert(event)
        pruneOfflineQueueEvents(in: context)
        do {
            try context.save()
        } catch {
            context.rollback()
            MerianLog.data.debug("recordQueueEvent: save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func writeQueueDiagnosticsExport(eventLimit: Int = 500) throws -> URL {
        guard let context = modelContext else {
            throw OfflineQueueDiagnosticsExportError.missingModelContext
        }

        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )).map { job in
            OfflineQueueDiagnosticsJob(
                id: job.id,
                kind: job.kindRaw,
                subjectId: job.subjectId,
                priority: job.priority,
                status: job.statusRaw,
                createdAt: job.createdAt,
                updatedAt: job.updatedAt,
                lastAttemptAt: job.lastAttemptAt,
                nextRunAt: job.nextRunAt,
                attemptCount: job.attemptCount,
                lastErrorCode: job.lastErrorCode,
                lastErrorMessage: job.lastErrorMessage,
                lastHTTPStatus: job.lastHTTPStatus,
                serverStatus: job.serverStatus,
                serverStage: job.serverStage,
                serverRetryAfter: job.serverRetryAfter,
                requiresUnconstrainedNetwork: job.requiresUnconstrainedNetwork,
                allowsCellular: job.allowsCellular,
                approximateBytes: job.approximateBytes
            )
        }

        let scans = try context.fetch(FetchDescriptor<OfflineQueuedScan>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )).map { scan in
            OfflineQueueDiagnosticsScan(
                id: scan.id,
                queueState: String(scan.queueState.rawValue),
                timestamp: scan.timestamp,
                attemptCount: scan.queueAttemptCount,
                lastAttemptAt: scan.queueLastAttemptAt,
                nextRetryAt: scan.queueNextRetryAt,
                lastErrorCode: scan.queueLastErrorCode,
                lastErrorMessage: scan.queueLastErrorMessage,
                lastHTTPStatus: scan.queueLastHTTPStatus,
                lastServerStatus: scan.queueLastServerStatus,
                lastServerStage: scan.queueLastServerStage,
                lastServerRetryAfter: scan.queueLastServerRetryAfter,
                updatedAt: scan.queueUpdatedAt,
                needsAttention: scan.queueNeedsAttention,
                mediaKinds: QueuedScanContext(
                    from: scan
                ).mediaKinds,
                approximateBytes: QueuedScanContext.approximateQueuedBytes(
                    mediaItems: scan.serializedCapturedMediaItems,
                    inferenceImagePaths: scan.inferenceImagePaths
                )
            )
        }

        var eventDescriptor = FetchDescriptor<OfflineQueueEvent>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        eventDescriptor.fetchLimit = eventLimit
        let events = try context.fetch(eventDescriptor).map { event in
            OfflineQueueDiagnosticsEvent(
                id: event.id,
                jobId: event.jobId,
                scanId: event.scanId,
                kind: event.kindRaw,
                createdAt: event.createdAt,
                message: event.message,
                errorCode: event.errorCode,
                httpStatus: event.httpStatus,
                hasMetadata: event.metadataJSON != nil
            )
        }

        let export = OfflineQueueDiagnosticsExport(
            exportedAt: Date(),
            jobs: jobs,
            scans: scans,
            events: events
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "merian-offline-queue-diagnostics-\(Int(Date().timeIntervalSince1970)).json"
        )
        try data.write(to: fileURL, options: Data.WritingOptions.atomic)
        recordQueueEvent(
            kind: .diagnostics,
            message: "Wrote offline queue diagnostics export.",
            metadataJSON: #"{"redacted_media":true}"#
        )
        return fileURL
    }

    private func pruneOfflineQueueEvents(in context: ModelContext, keeping limit: Int = 500) {
        var descriptor = FetchDescriptor<OfflineQueueEvent>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit + 100
        guard let events = try? context.fetch(descriptor), events.count > limit else { return }
        for event in events.dropFirst(limit) {
            context.delete(event)
        }
    }

    @discardableResult
    func ensureScanIngestionJob(
        scanId: String,
        approximateBytes: Int64 = 0,
        requiresUnconstrainedNetwork: Bool = false,
        allowsCellular: Bool = true
    ) -> OfflineJobRecord? {
        guard let context = modelContext else { return nil }
        do {
            let job = try context.ensureOfflineJobRecord(
                id: Self.scanIngestionJobId(scanId: scanId),
                kind: .scanIngestion,
                subjectId: scanId,
                priority: 100,
                approximateBytes: approximateBytes,
                requiresUnconstrainedNetwork: requiresUnconstrainedNetwork,
                allowsCellular: allowsCellular
            )
            try context.save()
            return job
        } catch {
            context.rollback()
            MerianLog.data.error("ensureScanIngestionJob: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return nil
        }
    }

    @discardableResult
    func updateQueuedScanForRetry(
        scanId: String,
        code: String,
        message: String?,
        httpStatus: Int? = nil,
        serverStatus: String? = nil,
        serverStage: String? = nil,
        serverRetryAfter: Date? = nil,
        delay: TimeInterval,
        resetTo state: ScanQueueState?
    ) -> Int? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        let scan: OfflineQueuedScan?
        do {
            scan = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.error(
                "updateQueuedScanForRetry: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return nil
        }
        guard let scan else { return nil }
        let attempt = scan.queueAttemptCount + 1
        let now = Date()
        scan.queueAttemptCount = attempt
        scan.queueLastAttemptAt = now
        scan.queueNextRetryAt = now.addingTimeInterval(max(1, delay))
        scan.queueLastErrorCode = code
        scan.queueLastErrorMessage = message
        scan.queueLastHTTPStatus = httpStatus
        scan.queueLastServerStatus = serverStatus
        scan.queueLastServerStage = serverStage
        scan.queueLastServerRetryAfter = serverRetryAfter
        scan.queueUpdatedAt = now
        scan.queueNeedsAttention = false
        if let state {
            scan.queueState = state
        }
        updateJobForRetry(
            scanId: scanId,
            attempt: attempt,
            nextRunAt: scan.queueNextRetryAt,
            code: code,
            message: message,
            httpStatus: httpStatus,
            serverStatus: serverStatus,
            serverStage: serverStage,
            serverRetryAfter: serverRetryAfter,
            in: context
        )
        do {
            try context.save()
        } catch {
            context.rollback()
            MerianLog.data.error("updateQueuedScanForRetry: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return nil
        }
        recordQueueEvent(
            scanId: scanId,
            jobId: Self.scanIngestionJobId(scanId: scanId),
            kind: .retryScheduled,
            message: message,
            errorCode: code,
            httpStatus: httpStatus
        )
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        return attempt
    }

    func queueAttemptCount(for scanId: String) -> Int {
        guard let context = modelContext else { return 0 }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor).first)?.queueAttemptCount) ?? 0
    }

    @discardableResult
    func retryQueuedScanNow(scanId: String) -> Bool {
        guard let context = modelContext else { return false }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard let scan = (try? context.fetch(descriptor))?.first else { return false }

        let snapshot = scan.capturedMediaSnapshot
        let shouldRecoverCompletedServerResult =
            Self.isCompletedServerResultRecoveryCode(
                scan.queueLastErrorCode
            )
        let hasUploadableMedia = !(scan.inferenceImagePaths ?? snapshot.thumbnailImagePaths).isEmpty
            || !snapshot.audioPaths.isEmpty
            || !snapshot.videoPaths.isEmpty
        scan.queueNextRetryAt = nil
        scan.queueNeedsAttention = false
        scan.queueLastErrorCode = shouldRecoverCompletedServerResult
            ? Self.completedServerResultRecoveryCode
            : nil
        scan.queueLastErrorMessage = shouldRecoverCompletedServerResult
            ? Self.completedServerResultRecoveryMessage
            : nil
        scan.queueUpdatedAt = Date()
        if scan.queueState == .failed {
            scan.queueState = shouldRecoverCompletedServerResult
                ? .inferencing
                : (hasUploadableMedia ? .pending : .staged)
        }
        if !snapshot.videoPaths.isEmpty {
            userRequestedLargeUploadScanIds.insert(scanId)
        }
        if let job = fetchScanJob(scanId: scanId, in: context) {
            job.status = .pending
            job.updatedAt = Date()
            job.nextRunAt = nil
            if shouldRecoverCompletedServerResult {
                job.lastErrorCode =
                    Self.completedServerResultRecoveryCode
                job.lastErrorMessage =
                    Self.completedServerResultRecoveryMessage
            } else {
                job.lastErrorCode = nil
                job.lastErrorMessage = nil
            }
        }
        context.insert(OfflineQueueEvent(
            jobId: Self.scanIngestionJobId(scanId: scanId),
            scanId: scanId,
            kind: .retryScheduled,
            message: "User requested an immediate retry."
        ))
        do {
            try context.save()
            updateUnsyncedItemCount()
            ScanLibraryEvents.postLibraryDidUpdate()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
            if scan.queueState == .pending {
                syncPendingScans()
            } else {
                replayInferenceForUploadedScans()
            }
            return true
        } catch {
            context.rollback()
            MerianLog.data.error("retryQueuedScanNow: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
    }

    func markQueuedScanNeedsAttention(
        scanId: String,
        code: String,
        message: String?,
        httpStatus: Int? = nil
    ) {
        guard let context = modelContext else { return }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard let scan = (try? context.fetch(descriptor))?.first else { return }
        let now = Date()
        scan.queueLastAttemptAt = now
        scan.queueNextRetryAt = nil
        scan.queueLastErrorCode = code
        scan.queueLastErrorMessage = message
        scan.queueLastHTTPStatus = httpStatus
        scan.queueNeedsAttention = true
        scan.queueUpdatedAt = now
        scan.queueState = .failed
        if let job = fetchScanJob(scanId: scanId, in: context) {
            job.status = .needsAttention
            job.updatedAt = now
            job.lastAttemptAt = now
            job.nextRunAt = nil
            job.lastErrorCode = code
            job.lastErrorMessage = message
            job.lastHTTPStatus = httpStatus
        }
        context.insert(OfflineQueueEvent(
            jobId: Self.scanIngestionJobId(scanId: scanId),
            scanId: scanId,
            kind: .needsAttention,
            message: message,
            errorCode: code,
            httpStatus: httpStatus
        ))
        do {
            try context.save()
            updateUnsyncedItemCount()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.error("markQueuedScanNeedsAttention: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }

    func persistServerStatus(scanId: String, response: ScanStatusResponse) {
        guard let context = modelContext else { return }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard let scan = (try? context.fetch(descriptor))?.first else { return }
        let retryAfterDate = response.retryAfter.flatMap(Self.parseRetryAfterDate)
        scan.queueLastServerStatus = response.jobStatus?.rawValue
        scan.queueLastServerStage = response.jobStage
        scan.queueLastServerRetryAfter = retryAfterDate
        scan.queueUpdatedAt = Date()
        if response.isFound {
            // Persist the owner-row observation before local hydration. If the
            // app terminates or the next status probe is unavailable, this
            // marker keeps orphan reconciliation from moving a known-complete
            // scan back to provider-dispatch eligibility.
            scan.queueLastErrorCode =
                Self.completedServerResultRecoveryCode
            scan.queueLastErrorMessage =
                Self.completedServerResultRecoveryMessage
        }
        if let retryAfterDate {
            scan.queueNextRetryAt = retryAfterDate
        }
        if let job = fetchScanJob(scanId: scanId, in: context) {
            job.serverStatus = response.jobStatus?.rawValue
            job.serverStage = response.jobStage
            job.serverRetryAfter = retryAfterDate
            job.updatedAt = Date()
            if response.isFound {
                job.lastErrorCode =
                    Self.completedServerResultRecoveryCode
                job.lastErrorMessage =
                    Self.completedServerResultRecoveryMessage
            }
            if let retryAfterDate {
                job.nextRunAt = retryAfterDate
                job.status = .waiting
            }
        }
        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.debug("persistServerStatus: save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func parseRetryAfterDate(_ rawValue: String) -> Date? {
        if let seconds = TimeInterval(rawValue) {
            return Date().addingTimeInterval(seconds)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: rawValue) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }

    private func updateJobForRetry(
        scanId: String,
        attempt: Int,
        nextRunAt: Date?,
        code: String,
        message: String?,
        httpStatus: Int?,
        serverStatus: String?,
        serverStage: String?,
        serverRetryAfter: Date?,
        in context: ModelContext
    ) {
        let job: OfflineJobRecord
        if let existing = fetchScanJob(scanId: scanId, in: context) {
            job = existing
        } else {
            job = OfflineJobRecord(
                id: Self.scanIngestionJobId(scanId: scanId),
                kind: .scanIngestion,
                subjectId: scanId,
                priority: 100
            )
            context.insert(job)
        }
        job.status = .waiting
        job.updatedAt = Date()
        job.lastAttemptAt = Date()
        job.nextRunAt = nextRunAt
        job.attemptCount = attempt
        job.lastErrorCode = code
        job.lastErrorMessage = message
        job.lastHTTPStatus = httpStatus
        job.serverStatus = serverStatus
        job.serverStage = serverStage
        job.serverRetryAfter = serverRetryAfter
    }

    private func fetchScanJob(scanId: String, in context: ModelContext) -> OfflineJobRecord? {
        let jobId = Self.scanIngestionJobId(scanId: scanId)
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
