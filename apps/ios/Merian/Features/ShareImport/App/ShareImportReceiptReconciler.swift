import Foundation
import SwiftData
import UIKit

@MainActor
enum ShareImportReceiptReconciler {
    private static var inFlightImportScanIds = Set<String>()

    static func reconcileIfNeeded(
        modelContext: ModelContext,
        scanRepository: ScanRepository
    ) async {
        let snapshot = ShareImportReceiptStore.load()
        let activeReceipts = snapshot.receipts.filter { $0.status == .queued }
        ShareImportLog.logger.debug(
            "ShareImportReceiptReconciler.reconcileIfNeeded: loaded receipts=\(snapshot.receipts.count, privacy: .public) queued=\(activeReceipts.count, privacy: .public)"
        )
        guard !activeReceipts.isEmpty else { return }

        let legacyPlaceholderPaths = deleteExternalImportPlaceholders(
            for: activeReceipts,
            modelContext: modelContext
        )
        let importResult = importShareImportsIntoOfflineQueue(
            receipts: activeReceipts,
            modelContext: modelContext
        )

        ShareImportLog.logger.debug(
            "ShareImportReceiptReconciler.reconcileIfNeeded: legacyPlaceholders=\(legacyPlaceholderPaths.count, privacy: .public) completed=\(importResult.completedScanIds.count, privacy: .public) started=\(importResult.startedImportCount, privacy: .public)"
        )

        guard !legacyPlaceholderPaths.isEmpty || !importResult.completedScanIds.isEmpty || importResult.startedImportCount > 0 else {
            ShareImportLog.logger.debug("ShareImportReceiptReconciler.reconcileIfNeeded: no actionable receipts")
            return
        }

        do {
            if !legacyPlaceholderPaths.isEmpty {
                try modelContext.save()
                await FileIOActor.shared.deleteFiles(at: legacyPlaceholderPaths)
                ShareImportLog.logger.debug(
                    "ShareImportReceiptReconciler.reconcileIfNeeded: deleted legacy placeholders=\(legacyPlaceholderPaths.count, privacy: .public)"
                )
            }
            ShareImportReceiptStore.remove(scanIds: importResult.completedScanIds)
            if !importResult.completedScanIds.isEmpty || importResult.startedImportCount > 0 {
                ShareImportLog.logger.debug("ShareImportReceiptReconciler.reconcileIfNeeded: kicking offline queue after import")
                OfflineQueueManager.shared.updateUnsyncedItemCount()
                OfflineQueueManager.shared.syncPendingScans()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    ShareImportLog.logger.debug("ShareImportReceiptReconciler.reconcileIfNeeded: delayed queue kick")
                    OfflineQueueManager.shared.syncPendingScans()
                    OfflineQueueManager.shared.replayInferenceForUploadedScans()
                }
            }
        } catch {
            modelContext.rollback()
            ShareImportLog.logger.error(
                "ShareImportReceiptReconciler.reconcileIfNeeded: save failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private struct ShareImportQueueResult {
        var completedScanIds = Set<String>()
        var startedImportCount = 0
    }

    private static func importShareImportsIntoOfflineQueue(
        receipts: [ShareImportReceipt],
        modelContext: ModelContext
    ) -> ShareImportQueueResult {
        guard let rootURL = ShareImportReceiptStore.appGroupRootURL() else {
            ShareImportLog.logger.error("ShareImportReceiptReconciler.import: missing app group root")
            return ShareImportQueueResult()
        }

        var result = ShareImportQueueResult()
        for receipt in receipts {
            ShareImportLog.logger.debug(
                "ShareImportReceiptReconciler.import: inspecting scanId=\(receipt.scanId, privacy: .public) file=\(receipt.localImageFilename ?? "nil", privacy: .public)"
            )
            if hasExistingScan(scanId: receipt.scanId, modelContext: modelContext) {
                ShareImportLog.logger.debug(
                    "ShareImportReceiptReconciler.import: scan already exists scanId=\(receipt.scanId, privacy: .public)"
                )
                result.completedScanIds.insert(receipt.scanId)
                inFlightImportScanIds.remove(receipt.scanId)
                continue
            }

            guard !inFlightImportScanIds.contains(receipt.scanId) else {
                ShareImportLog.logger.debug(
                    "ShareImportReceiptReconciler.import: already in flight scanId=\(receipt.scanId, privacy: .public)"
                )
                continue
            }

            guard let sourceURL = ShareImportReceiptStore.localImageURL(for: receipt, rootURL: rootURL),
                  FileManager.default.fileExists(atPath: sourceURL.path) else {
                ShareImportLog.logger.error(
                    "ShareImportReceiptReconciler.import: missing local image scanId=\(receipt.scanId, privacy: .public) file=\(receipt.localImageFilename ?? "nil", privacy: .public)"
                )
                continue
            }

            guard let imageData = try? Data(contentsOf: sourceURL) else {
                ShareImportLog.logger.error(
                    "ShareImportReceiptReconciler.import: unreadable local image scanId=\(receipt.scanId, privacy: .public) path=\(sourceURL.path, privacy: .public)"
                )
                continue
            }

            ShareImportLog.logger.debug(
                "ShareImportReceiptReconciler.import: enqueueing scanId=\(receipt.scanId, privacy: .public) bytes=\(imageData.count, privacy: .public)"
            )
            inFlightImportScanIds.insert(receipt.scanId)
            let telemetry = CaptureTelemetry(
                subjectDistanceInMeters: nil,
                gpsLatitude: receipt.gpsLatitude,
                gpsLongitude: receipt.gpsLongitude,
                gpsElevation: receipt.gpsElevation,
                locationName: nil,
                weatherCondition: nil,
                weatherTemperatureF: nil,
                timeOfDay: nil,
                timestamp: receipt.capturedAt
            )
            OfflineQueueManager.shared.enqueueCapture(
                imageDatas: [imageData],
                telemetry: telemetry,
                scanId: receipt.scanId,
                captureDate: capturedDate(for: receipt),
                onQueued: { didQueue in
                    ShareImportLog.logger.debug(
                        "ShareImportReceiptReconciler.import: enqueue callback scanId=\(receipt.scanId, privacy: .public) didQueue=\(didQueue, privacy: .public)"
                    )
                    inFlightImportScanIds.remove(receipt.scanId)
                    guard didQueue else {
                        ShareImportLog.logger.error(
                            "ShareImportReceiptReconciler.import: existing queue rejected scanId=\(receipt.scanId, privacy: .public)"
                        )
                        return
                    }
                    ShareImportReceiptStore.remove(scanIds: [receipt.scanId])
                    OfflineQueueManager.shared.updateUnsyncedItemCount()
                    OfflineQueueManager.shared.syncPendingScans()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        ShareImportLog.logger.debug(
                            "ShareImportReceiptReconciler.import: delayed post-enqueue kick scanId=\(receipt.scanId, privacy: .public)"
                        )
                        OfflineQueueManager.shared.syncPendingScans()
                        OfflineQueueManager.shared.replayInferenceForUploadedScans()
                    }
                }
            )
            result.startedImportCount += 1
        }

        return result
    }

    private static func hasExistingScan(scanId: String, modelContext: ModelContext) -> Bool {
        var queuedDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        queuedDescriptor.fetchLimit = 1
        if (try? modelContext.fetch(queuedDescriptor))?.isEmpty == false {
            return true
        }

        var localDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        localDescriptor.fetchLimit = 1
        return (try? modelContext.fetch(localDescriptor))?.isEmpty == false
    }

    private static func deleteExternalImportPlaceholders(
        for receipts: [ShareImportReceipt],
        modelContext: ModelContext
    ) -> [String] {
        var imagePathsToDelete: [String] = []
        for receipt in receipts {
            imagePathsToDelete.append(contentsOf: deleteQueuedPlaceholder(
                scanId: receipt.scanId,
                modelContext: modelContext
            ))
        }

        return imagePathsToDelete
    }

    private static func deleteQueuedPlaceholder(
        scanId: String,
        modelContext: ModelContext
    ) -> [String] {
        let externalImportRaw = ScanQueueState.externalImport.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId && $0.scanStateRaw == externalImportRaw }
        )
        descriptor.fetchLimit = 1
        guard let scan = (try? modelContext.fetch(descriptor))?.first else {
            return []
        }

        let imagePaths = scan.capturedMediaSnapshot.imageReferences.compactMap { reference -> String? in
            guard !reference.isRemote else { return nil }
            return reference.resolvedURL?.path ?? reference.serializedPath
        }
        modelContext.delete(scan)
        ShareImportLog.logger.debug(
            "ShareImportReceiptReconciler.deleteQueuedPlaceholder: removed legacy placeholder scanId=\(scanId, privacy: .public) files=\(imagePaths.count, privacy: .public)"
        )
        return imagePaths
    }

    private static func capturedDate(for receipt: ShareImportReceipt) -> Date {
        guard let capturedAt = receipt.capturedAt,
              let date = iso8601Formatter.date(from: capturedAt) else {
            return receipt.createdAt
        }
        return date
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
