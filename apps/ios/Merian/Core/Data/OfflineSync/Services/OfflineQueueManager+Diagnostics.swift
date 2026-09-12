import Foundation
import SwiftData

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
    let formatVersion: Int
    let exportedAt: Date
    let app: OfflineQueueDiagnosticsApp
    let jobs: [OfflineQueueDiagnosticsJob]
    let scans: [OfflineQueueDiagnosticsScan]
    let events: [OfflineQueueDiagnosticsEvent]
}

private struct OfflineQueueDiagnosticsApp: Encodable {
    let version: String
    let build: String
    let sourceRevision: String
    let sourceFingerprint: String
    let sourceState: String
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

private enum OfflineQueueDiagnosticsExportPolicy {
    static let maximumRowsPerSection = 500

    static func boundedEventLimit(_ requestedLimit: Int) -> Int {
        min(max(1, requestedLimit), maximumRowsPerSection)
    }

    static func canonicalMachineToken(_ value: String?) -> String? {
        guard let value,
              value.range(
                of: #"^[a-z][a-z0-9_]{1,63}$"#,
                options: .regularExpression
              ) != nil else {
            return nil
        }
        return value
    }
}

@MainActor
extension OfflineQueueManager {
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
            MerianLog.data.debug("recordQueueEvent: save failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    @discardableResult
    func writeQueueDiagnosticsExport(eventLimit: Int = 500) throws -> URL {
        guard let context = modelContext else {
            throw OfflineQueueDiagnosticsExportError.missingModelContext
        }
        let boundedEventLimit =
            OfflineQueueDiagnosticsExportPolicy.boundedEventLimit(eventLimit)

        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        jobDescriptor.fetchLimit =
            OfflineQueueDiagnosticsExportPolicy.maximumRowsPerSection
        let jobs = try context.fetch(jobDescriptor).map { job in
            OfflineQueueDiagnosticsJob(
                id: job.id,
                kind: job.kind.rawValue,
                subjectId: job.subjectId,
                priority: job.priority,
                status: job.status.rawValue,
                createdAt: job.createdAt,
                updatedAt: job.updatedAt,
                lastAttemptAt: job.lastAttemptAt,
                nextRunAt: job.nextRunAt,
                attemptCount: job.attemptCount,
                lastErrorCode:
                    OfflineQueueDiagnosticsExportPolicy.canonicalMachineToken(
                        job.lastErrorCode
                    ),
                lastErrorMessage: nil,
                lastHTTPStatus: job.lastHTTPStatus,
                serverStatus:
                    OfflineQueueDiagnosticsExportPolicy.canonicalMachineToken(
                        job.serverStatus
                    ),
                serverStage:
                    OfflineQueueDiagnosticsExportPolicy.canonicalMachineToken(
                        job.serverStage
                    ),
                serverRetryAfter: job.serverRetryAfter,
                requiresUnconstrainedNetwork: job.requiresUnconstrainedNetwork,
                allowsCellular: job.allowsCellular,
                approximateBytes: job.approximateBytes
            )
        }

        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        scanDescriptor.fetchLimit =
            OfflineQueueDiagnosticsExportPolicy.maximumRowsPerSection
        let scans = try context.fetch(scanDescriptor).map { scan in
            OfflineQueueDiagnosticsScan(
                id: scan.id,
                queueState: String(scan.queueState.rawValue),
                timestamp: scan.timestamp,
                attemptCount: scan.queueAttemptCount,
                lastAttemptAt: scan.queueLastAttemptAt,
                nextRetryAt: scan.queueNextRetryAt,
                lastErrorCode:
                    OfflineQueueDiagnosticsExportPolicy.canonicalMachineToken(
                        scan.queueLastErrorCode
                    ),
                lastErrorMessage: nil,
                lastHTTPStatus: scan.queueLastHTTPStatus,
                lastServerStatus:
                    OfflineQueueDiagnosticsExportPolicy.canonicalMachineToken(
                        scan.queueLastServerStatus
                    ),
                lastServerStage:
                    OfflineQueueDiagnosticsExportPolicy.canonicalMachineToken(
                        scan.queueLastServerStage
                    ),
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
        eventDescriptor.fetchLimit = boundedEventLimit
        let events = try context.fetch(eventDescriptor).map { event in
            OfflineQueueDiagnosticsEvent(
                id: event.id,
                jobId: event.jobId,
                scanId: event.scanId,
                kind: event.kind.rawValue,
                createdAt: event.createdAt,
                message: nil,
                errorCode:
                    OfflineQueueDiagnosticsExportPolicy.canonicalMachineToken(
                        event.errorCode
                    ),
                httpStatus: event.httpStatus,
                hasMetadata: event.metadataJSON != nil
            )
        }

        let export = OfflineQueueDiagnosticsExport(
            formatVersion: 1,
            exportedAt: Date(),
            app: OfflineQueueDiagnosticsApp(
                version: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "unavailable",
                build: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleVersion"
                ) as? String ?? "unavailable",
                sourceRevision: Bundle.main.object(
                    forInfoDictionaryKey: "MERIAN_SOURCE_REVISION"
                ) as? String ?? "unavailable",
                sourceFingerprint: Bundle.main.object(
                    forInfoDictionaryKey: "MERIAN_SOURCE_FINGERPRINT"
                ) as? String ?? "unavailable",
                sourceState: Bundle.main.object(
                    forInfoDictionaryKey: "MERIAN_SOURCE_STATE"
                ) as? String ?? "unavailable"
            ),
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
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtection]
        )
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
        let events: [OfflineQueueEvent]
        do {
            events = try context.fetch(descriptor)
        } catch {
            MerianLog.data.debug(
                "pruneOfflineQueueEvents: fetch failed: \(error, privacy: .private)"
            )
            return
        }
        guard events.count > limit else { return }
        for event in events.dropFirst(limit) {
            context.delete(event)
        }
    }
}
