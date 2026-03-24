import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Queue Maintenance

extension OfflineQueueManager {

    /// Refreshes `unsyncedItemsCount` by fetching the count of non-deleted `OfflineQueuedScan` records.
    func updateUnsyncedItemCount() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.isDeleted == false })
        let count: Int
        do {
            count = try context.fetchCount(descriptor)
        } catch {
            MerianLog.data.debug("updateUnsyncedItemCount: fetchCount failed: \(error, privacy: .private)")
            return
        }
        Task { @MainActor in self.unsyncedItemsCount = count }
    }

    /// Marks an `OfflineQueuedScan` as deleted without removing it from the database.
    ///
    /// Used to tombstone scans whose source files are missing or whose uploads have been permanently
    /// rejected. The record is excluded from future sync attempts and cleaned up by `purgeSoftDeletedRecords()`.
    func softDeleteQueuedScan(scanId: String) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate<OfflineQueuedScan> { $0.id == scanId })
        guard let match = (try? context.fetch(descriptor))?.first else { return }
        match.isDeleted = true
        do {
            try context.save()
        } catch {
            MerianLog.data.error("softDeleteQueuedScan: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
        updateUnsyncedItemCount()
    }

    /// Permanently removes all soft-deleted `OfflineQueuedScan` records and their associated image files from disk.
    /// Called at appropriate cleanup points (e.g., after a successful sync cycle or on app foreground).
    func purgeSoftDeletedRecords() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.isDeleted == true })
        let documentsDirectory = URL.documentsDirectory

        do {
            let deletedScans = try context.fetch(descriptor)
            for scan in deletedScans {
                for path in scan.localImagePaths {
                    do {
                        try FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(path))
                    } catch {
                        MerianLog.data.debug("purgeSoftDeletedRecords: removeItem failed: \(error, privacy: .private)")
                    }
                }
                context.delete(scan)
            }
            try context.save()
            updateUnsyncedItemCount()
        } catch {
            MerianLog.data.debug("purgeSoftDeletedRecords: operation failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Capture Enqueue

    /// Writes image data to the Documents directory and inserts a new `OfflineQueuedScan` record.
    ///
    /// All disk I/O runs inside a `BackgroundTaskWrapper` so iOS grants extended time even if
    /// the user backgrounds the app immediately after capture. On success, `syncPendingScans()`
    /// is called immediately to start uploading while the background window is still active.
    ///
    /// On any failure — disk write or context save — partial image files are cleaned up atomically.
    func enqueueCapture(imageDatas: [Data], telemetry: CaptureTelemetry, blurScore: Double? = nil) {
        let documentsDirectory = URL.documentsDirectory
        let pairs = imageDatas.map { _ -> (name: String, url: URL) in
            let name = "\(UUID().uuidString).jpg"
            return (name, documentsDirectory.appendingPathComponent(name))
        }
        let fileNames = pairs.map(\.name)
        let fileURLs = pairs.map(\.url)

        BackgroundTaskWrapper.execute(name: "OfflineQueueCaptureWrite") { _ in
            do {
                for (index, data) in imageDatas.enumerated() {
                    try data.write(to: fileURLs[index])
                }

                await MainActor.run {
                    // Free users are capped at their daily scan limit to prevent scan hoarding.
                    // If the cap is already hit, clean up the files we just wrote and bail.
                    if !RevenueCatManager.shared.isProActive,
                       let modelContext = OfflineQueueManager.shared.modelContext {
                        let capDescriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.isDeleted == false })
                        let currentCount = (try? modelContext.fetchCount(capDescriptor)) ?? 0
                        if currentCount >= UsageManager.shared.maxFreeScansPerDay {
                            MerianLog.data.debug("enqueueCapture: free user queue cap reached — scan not enqueued")
                            for url in fileURLs { try? FileManager.default.removeItem(at: url) }
                            return
                        }
                    }

                    let scan = OfflineQueuedScan(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        localImagePaths: fileNames,
                        gpsLatitude: telemetry.gpsLatitude,
                        gpsLongitude: telemetry.gpsLongitude,
                        gpsElevation: telemetry.gpsElevation,
                        weatherCondition: telemetry.weatherCondition,
                        weatherTemperatureF: telemetry.weatherTemperatureF,
                        blurScore: blurScore,
                        subjectDistanceInMeters: telemetry.subjectDistanceInMeters,
                        locationName: telemetry.locationName,
                        isFlashFired: nil,
                        cameraPitchDegrees: nil,
                        compassHeading: nil,
                        relativeHumidity: nil,
                        uvIndex: nil,
                        isDeleted: false
                    )
                    guard let modelContext = OfflineQueueManager.shared.modelContext else { return }
                    modelContext.insert(scan)
                    do {
                        try modelContext.save()
                        OfflineQueueManager.shared.updateUnsyncedItemCount()
                        // Kick off sync immediately while iOS has an active background window.
                        OfflineQueueManager.shared.syncPendingScans()
                    } catch {
                        MerianLog.data.error("enqueueCapture: context.save() failed — scan record lost, cleaning up image footprints: \(error, privacy: .private)")
                        for url in fileURLs {
                            do { try FileManager.default.removeItem(at: url) } catch {
                                MerianLog.data.debug("enqueueCapture: cleanup removeItem failed: \(error, privacy: .private)")
                            }
                        }
                    }
                }
            } catch {
                MerianLog.data.error("enqueueCapture: image write to disk failed — scan will not be queued: \(error, privacy: .private)")
                for url in fileURLs {
                    do { try FileManager.default.removeItem(at: url) } catch {
                        MerianLog.data.debug("enqueueCapture: cleanup removeItem failed: \(error, privacy: .private)")
                    }
                }
            }
        }
    }
}
