import Foundation
import Network
import Combine
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Uses NWPathMonitor for a zero-data loss offline queue automatically syncing securely when a link is confirmed.
@MainActor
final class OfflineQueueManager: ObservableObject {
    static let shared = OfflineQueueManager()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "MerianOfflineSyncQueue")
    
    @Published var isOnline: Bool = false
    @Published var unsyncedItemsCount: Int = 0
    
    private var isSyncing: Bool = false
    private var syncTask: Task<Void, Never>?
    
    var modelContext: ModelContext?
    
    private init() {
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
        
        do {
            let pendingScans = try modelContext.fetch(descriptor)
            guard !pendingScans.isEmpty else { return }
            
            isSyncing = true
            SyncStateManager.shared.beginSync(itemCount: pendingScans.count)
            
            #if os(iOS)
            // Critical: Request explicit background execution time from iOS to wrap up field uploads while the device is in the user's pocket
            var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "OfflineQueueSync") {
                // Time expiring
                self.syncTask?.cancel()
                self.isSyncing = false
                SyncStateManager.shared.completeSync()
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
            #endif
            
            syncTask = Task {
                for scan in pendingScans {
                    // Pre-check the circuit breaker natively before each payload fires
                    if Task.isCancelled || !self.isOnline { break }
                    await processScan(scan)
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
    
    private func processScan(_ scan: OfflineQueuedScan) async {
        guard let modelContext = modelContext else { return }
        let documentsDirectory = URL.documentsDirectory
        let networkClient = MerianNetworkClient.shared
        
        do {
            var fileUris: [String] = []
            var fileNames: [String] = []
            var imageDataArray: [Data] = []
            
            for path in scan.localImagePaths {
                let fileURL = documentsDirectory.appendingPathComponent(path)
                let data = try Data(contentsOf: fileURL)
                imageDataArray.append(data)
                
                // Step 1: Ephemeral Upload Protocol
                let fileUri = try await networkClient.uploadToGeminiFileAPI(imageData: data)
                fileUris.append(fileUri)
                fileNames.append("\(scan.id)_\(path)") // Safely append context metadata to filename
            }
            
            // Step 2: Supabase Inference Route (Payload validation without base64 images)
            let _ = try await networkClient.analyzeSubject(
                fileUris: fileUris,
                depthScaleText: nil, // Extrapolate metadata constraints if needed later via model syncs
                gpsLatitude: scan.gpsLatitude,
                gpsLongitude: scan.gpsLongitude,
                weatherCondition: scan.weatherCondition
            )
            
            // Step 3: Pre-Signed URL Authentication
            let presignedUrls = try await networkClient.generateUploadURLs(fileNames: fileNames)
            
            // Step 4: Permanent Archive to R2
            for (index, presignedURL) in presignedUrls.enumerated() {
                if index < imageDataArray.count {
                    let data = imageDataArray[index]
                    try await networkClient.uploadToR2(url: presignedURL.signedUrl, data: data)
                }
            }
            
            // Pre-Purge Archive Safety Protocol
            // Before deleting from the volatile local cache, attempt to pull high-res into Apple Photos
            let imagesToArchive = scan.localImagePaths.map { documentsDirectory.appendingPathComponent($0) }
            await ArchiveManager.shared.initiatePrePurgeSync(pendingImages: imagesToArchive)
            
            // Clear successfully synced captures 200 OK locally 
            for path in scan.localImagePaths {
                let fileURL = documentsDirectory.appendingPathComponent(path)
                try? FileManager.default.removeItem(at: fileURL)
            }
            
            modelContext.delete(scan)
            try modelContext.save()
            updateUnsyncedItemCount()
            CircuitBreakerManager.shared.recordSuccess()
            
        } catch {
            print("Failed to process scan \(scan.id): \(error)")
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
}
