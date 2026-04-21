import Foundation
import SwiftData

// MARK: - Audio Enqueue

extension OfflineQueueManager {

    /// Persists a finished audio recording and inserts a `.staged` `OfflineQueuedScan` record
    /// for background bioacoustic inference once the `audio_spec` edge function is deployed.
    ///
    /// The audio file is moved from the `tmp` directory into `Documents` so it survives app
    /// restarts. The queue record carries `audioFilePath` in place of `observationContextJSON`
    /// or `localImagePaths`, which causes `replayInferenceStagedScans` to skip it (audio scans
    /// require a dedicated dispatch path, not the image/describe inference routes).
    ///
    /// Quota is consumed at enqueue time, mirroring `enqueueCapture` and `enqueueDescribe`.
    /// Moves the finished audio recording to Documents and inserts a `.staged` queue record.
    /// Returns `true` on success; `false` if the file move, quota check, or DB save fails.
    /// The caller must not invoke `analyzeAudio` or clear UI state when `false` is returned.
    @MainActor
    @discardableResult
    func enqueueAudio(audioFileName: String, telemetry: CaptureTelemetry, observationContext: ObservationContext? = nil, scanId: String? = nil) -> Bool {
        guard !audioFileName.isEmpty else { return false }

        // Move tmp → Documents so the file outlives the OS temporary storage eviction window.
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(audioFileName)
        let destURL = URL.documentsDirectory.appendingPathComponent(audioFileName)

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destURL)
        } catch {
            MerianLog.data.error("enqueueAudio: failed to persist audio file — scan not queued: \(error, privacy: .private)")
            return false
        }

        if !RevenueCatManager.shared.isProActive {
            guard UsageManager.shared.canPerformScan(isProActive: false) else {
                try? FileManager.default.moveItem(at: destURL, to: tempURL)
                MerianLog.data.debug("enqueueAudio: free user scan quota exhausted — audio not queued")
                return false
            }
            UsageManager.shared.consumeScan()
        }

        let contextJSON: String? = observationContext.flatMap { ctx in
            guard !ctx.isEmpty else { return nil }
            return (try? JSONEncoder().encode(ctx)).flatMap { String(data: $0, encoding: .utf8) }
        }

        let resolvedScanId = scanId ?? UUID().uuidString.lowercased()
        let scan = OfflineQueuedScan(
            id: resolvedScanId,
            timestamp: Date(),
            localImagePaths: [],
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude,
            gpsElevation: telemetry.gpsElevation,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            locationName: telemetry.locationName,
            zoomFactor: telemetry.zoomFactor.map { Double($0) },
            scanState: .staged,
            audioFilePath: audioFileName,
            observationContextJSON: contextJSON
        )

        guard let modelContext else {
            MerianLog.data.error("enqueueAudio: modelContext unavailable — scan not queued")
            try? FileManager.default.removeItem(at: destURL)
            return false
        }
        modelContext.insert(scan)
        do {
            try modelContext.save()
            updateUnsyncedItemCount()
            AppTelemetry.trackOfflineQueued()
            return true
        } catch {
            MerianLog.data.error("enqueueAudio: context.save() failed: \(error, privacy: .private)")
            try? FileManager.default.removeItem(at: destURL)
            return false
        }
    }
}
