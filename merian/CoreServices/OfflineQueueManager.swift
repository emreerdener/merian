import Foundation
import Network
import Combine
import SwiftData
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

/// Uses NWPathMonitor for a zero-data loss offline queue automatically syncing securely when a link is confirmed.
@MainActor
final class OfflineQueueManager: NSObject, ObservableObject, URLSessionTaskDelegate {
    static let shared = OfflineQueueManager()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "MerianOfflineSyncQueue")
    
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.merian.OfflineSyncBackground")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    @Published var isOnline: Bool = false
    @Published var unsyncedItemsCount: Int = 0
    
    var backgroundCompletionHandler: (() -> Void)?
    
    private var isSyncing: Bool = false
    private var syncTask: Task<Void, Never>?
    
    var modelContext: ModelContext?
    
    private override init() {
        super.init()
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let newStatus = path.status == .satisfied
                
                // Only act on actual state changes to avoid redundant thrashing
                if newStatus != self?.isOnline {
                    self?.isOnline = newStatus
                    print("NWPathMonitor Status Changed: \(newStatus ? "Online" : "Offline")")
                    
                    if newStatus {
                        // Debounce slightly to allow the OS network stack to fully resolve
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        self?.syncPendingScans()
                    } else {
                        // Immediately circuit-break any active uploads if we drop off-grid
                        self?.syncTask?.cancel()
                        self?.isSyncing = false
                        SyncStateManager.shared.completeSync()
                    }
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    func enqueueCapture(imageData: Data,
                        gpsLatitude: Double? = nil,
                        gpsLongitude: Double? = nil,
                        gpsElevation: Double? = nil,
                        weatherCondition: String? = nil,
                        weatherTemperatureF: Double? = nil,
                        blurScore: Double? = nil) {
        
        guard let modelContext = modelContext else {
            print("ModelContext not set on OfflineQueueManager")
            return
        }
        
        let fileName = "\(UUID().uuidString).jpg"
        let documentsDirectory = URL.documentsDirectory
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL)
            let scan = OfflineQueuedScan(
                id: UUID().uuidString,
                timestamp: Date(),
                localImagePaths: [fileName],
                gpsLatitude: gpsLatitude,
                gpsLongitude: gpsLongitude,
                gpsElevation: gpsElevation,
                weatherCondition: weatherCondition,
                weatherTemperatureF: weatherTemperatureF,
                blurScore: blurScore,
                isDeleted: false
            )
            modelContext.insert(scan)
            try modelContext.save()
            updateUnsyncedItemCount()
        } catch {
            print("Failed to enqueue capture: \(error)")
        }
    }
    
    func syncPendingScans() {
        guard isOnline else { return }
        guard !isSyncing else { return } // Prevent parallel overlap attacks
        guard let modelContext = modelContext else { return }
        
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { !$0.isDeleted })
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        descriptor.fetchLimit = 5 // Strictly limit background upload chunks to prevent Edge Function timeout execution limits
        
        
        do {
            let pendingScans = try modelContext.fetch(descriptor)
            guard !pendingScans.isEmpty else { return }
            
            isSyncing = true
            SyncStateManager.shared.beginSync(itemCount: pendingScans.count)
            
            #if os(iOS)
            // Critical: Request explicit background execution time from iOS to wrap up field uploads while the device is in the user's pocket
            var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "OfflineQueueSync") {
                // Strict expirationHandler that safely suspends the queue without corrupting the data if the OS runs out of time.
                self.syncTask?.cancel()
                self.isSyncing = false
                SyncStateManager.shared.completeSync()
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
            #endif
            
            syncTask = Task {
                let documentsDirectory = URL.documentsDirectory
                
                var fileNames: [String] = []
                var fileURLs: [URL] = []
                var scanIDs: [String] = []
                
                // Aggregating all files to get Pre-Signed URLs in one batch
                for scan in pendingScans {
                    for path in scan.localImagePaths {
                        let fileURL = documentsDirectory.appendingPathComponent(path)
                        let rawName = "\(scan.id)_\(path)"
                        fileNames.append(rawName)
                        fileURLs.append(fileURL)
                        scanIDs.append(scan.id)
                    }
                }
                
                guard !fileNames.isEmpty else {
                    await MainActor.run {
                        self.isSyncing = false
                        SyncStateManager.shared.completeSync()
                    }
                    return
                }
                
                do {
                    // Fetch Cloudflare R2 staging URLs (not chaining the Inference analyze API afterwards)
                    let presignedUrls = try await MerianNetworkClient.shared.generateUploadURLs(fileNames: fileNames)
                    
                    for (index, presignedURL) in presignedUrls.enumerated() {
                        if Task.isCancelled { break } // Block loop execution instantly upon strict OS-level thread suspension
                        
                        guard index < fileURLs.count else { continue }
                        guard let remoteUrl = URL(string: presignedURL.signedUrl) else { continue }
                        
                        var request = URLRequest(url: remoteUrl)
                        request.httpMethod = "PUT"
                        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
                        
                        let scanId = scanIDs[index]
                        let originalFileURL = fileURLs[index]
                        let tempFileURL = URL.cachesDirectory.appendingPathComponent("\\(scanId)_temp_upload.jpg")
                        
                        if let downsampledData = self.downsampleLocalPayload(fileURL: originalFileURL) {
                            try? downsampledData.write(to: tempFileURL)
                        } else {
                            try? FileManager.default.copyItem(at: originalFileURL, to: tempFileURL)
                        }
                        
                        // Enqueue to the iOS Background URLSession cleanly using the downsampled physical file
                        let uploadTask = self.backgroundSession.uploadTask(with: request, fromFile: tempFileURL)
                        uploadTask.taskDescription = scanId
                        uploadTask.resume()
                    }
                    
                    // The backend will handle the actual Gemini inference asynchronously via a Supabase Storage Webhook once the file lands in the R2 staging bucket.
                    
                } catch {
                    print("Failed to request Background staging URLs natively: \(error)")
                }
                
                await MainActor.run {
                    self.isSyncing = false
                    SyncStateManager.shared.completeSync()
                    
                    #if os(iOS)
                    if backgroundTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    }
                    #endif
                }
            }
            
        } catch {
            print("Failed to fetch pending scans: \(error)")
            isSyncing = false
            SyncStateManager.shared.completeSync()
        }
    }
    
    /// Triggered exclusively when the Background Networking Queue finishes physical transmission of the bytes natively
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let scanId = task.taskDescription else { return }
        
        let tempFileURL = URL.cachesDirectory.appendingPathComponent("\(scanId)_temp_upload.jpg")
        try? FileManager.default.removeItem(at: tempFileURL)
        
        guard error == nil else {
            print("Background upload hard failed: \(error!)")
            return
        }
        
        guard let response = task.response as? HTTPURLResponse, response.statusCode == 200 else {
            print("Background upload rejected physically by boundary constraints.")
            return
        }
        
        Task { @MainActor in
            guard let modelContext = OfflineQueueManager.shared.modelContext else { return }
            let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            
            guard let scan = try? modelContext.fetch(descriptor).first else { return }
            
            guard let urlPath = task.originalRequest?.url?.path, let range = urlPath.range(of: "staging/") else { return }
            let r2ObjectKey = String(urlPath[range.lowerBound...])
            
            #if os(iOS)
            var inferenceTaskID: UIBackgroundTaskIdentifier = .invalid
            inferenceTaskID = UIApplication.shared.beginBackgroundTask(withName: "OfflineInference") {
                UIApplication.shared.endBackgroundTask(inferenceTaskID)
            }
            #endif
            
            do {
                _ = try await MerianNetworkClient.shared.analyzeSubject(
                    r2ObjectKey: r2ObjectKey,
                    depthScaleText: nil,
                    gpsLatitude: scan.gpsLatitude,
                    gpsLongitude: scan.gpsLongitude,
                    weatherCondition: scan.weatherCondition
                )
                OfflineQueueManager.shared.finalizeScanCleanup(scanId: scanId)
            } catch {
                print("Failed downstream inference on offline queued scan: \(error)")
            }
            
            #if os(iOS)
            UIApplication.shared.endBackgroundTask(inferenceTaskID)
            #endif
        }
    }
    
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            guard let handler = OfflineQueueManager.shared.backgroundCompletionHandler else { return }
            OfflineQueueManager.shared.backgroundCompletionHandler = nil
            handler()
        }
    }
    
    private func finalizeScanCleanup(scanId: String) {
        guard let modelContext = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        
        do {
            let matches = try modelContext.fetch(descriptor)
            for scan in matches {
                let documentsDirectory = URL.documentsDirectory
                for path in scan.localImagePaths {
                    let fileURL = documentsDirectory.appendingPathComponent(path)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                modelContext.delete(scan)
            }
            try modelContext.save()
            updateUnsyncedItemCount()
            CircuitBreakerManager.shared.recordSuccess()
        } catch {
            print("Cleanup of Sync \(scanId) completely failed natively: \(error)")
        }
    }
    
    func purgeSoftDeletedRecords() {
        guard let modelContext = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.isDeleted })
        let documentsDirectory = URL.documentsDirectory
        
        do {
            let deletedScans = try modelContext.fetch(descriptor)
            for scan in deletedScans {
                // Clear the cache completely out of the local device storage
                for path in scan.localImagePaths {
                    let fileURL = documentsDirectory.appendingPathComponent(path)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                modelContext.delete(scan)
            }
            try modelContext.save()
            updateUnsyncedItemCount()
        } catch {
            print("Failed to purge soft deleted records: \(error)")
        }
    }
    
    private func updateUnsyncedItemCount() {
        guard let modelContext = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { !$0.isDeleted })
        if let count = try? modelContext.fetchCount(descriptor) {
            self.unsyncedItemsCount = count
        }
    }
    
    // Internal generic mapping to shrink original 12MP arrays securely before uploading
    private func downsampleLocalPayload(fileURL: URL, maxDimension: CGFloat = 1024.0) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        
        let thumbnail = UIImage(cgImage: cgImage)
        return thumbnail.jpegData(compressionQuality: 0.7)
    }
}
