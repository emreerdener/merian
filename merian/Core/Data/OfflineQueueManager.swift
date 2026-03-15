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
        _ = backgroundSession // Force initialization so iOS can re-attach background tasks on wake
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
                        await self?.syncPendingDeletions()
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
    
    func syncPendingDeletions() async {
        guard isOnline, let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<PendingCloudDeletionTask>(sortBy: [SortDescriptor(\.timestamp)])
            let pendingTasks = try context.fetch(descriptor)
            
            for task in pendingTasks {
                do {
                    try await MerianNetworkClient.shared.deleteScan(scanId: task.scanId)
                    context.delete(task)
                    try context.save()
                    print("✅ Successfully erased \(task.scanId) securely in Edge background")
                } catch {
                    // Let it fail silently, either network jitter or it naturally succeeded already.
                    // We'll retry on next connectivity cycle naturally.
                    if case NetworkError.invalidResponse = error {
                        context.delete(task)
                        try? context.save()
                    }
                }
            }
        } catch {
            print("Failed fetching cloud deletion tasks: \(error)")
        }
    }
    
    func enqueueCapture(imageData: Data,
                        gpsLatitude: Double? = nil,
                        gpsLongitude: Double? = nil,
                        gpsElevation: Double? = nil,
                        weatherCondition: String? = nil,
                        weatherTemperatureF: Double? = nil,
                        blurScore: Double? = nil,
                        subjectDistanceInMeters: Float? = nil,
                        locationName: String? = nil,
                        isFlashFired: Bool? = nil,
                        cameraPitchDegrees: Double? = nil,
                        compassHeading: Double? = nil,
                        relativeHumidity: Double? = nil,
                        uvIndex: Int? = nil) {
        
        guard let modelContext = modelContext else {
            print("ModelContext not set on OfflineQueueManager")
            return
        }
        
        let fileName = "\(UUID().uuidString).jpg"
        let documentsDirectory = URL.documentsDirectory
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        Task.detached(priority: .userInitiated) {
            do {
                try imageData.write(to: fileURL)
                
                await MainActor.run {
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
                        subjectDistanceInMeters: subjectDistanceInMeters,
                        locationName: locationName,
                        isFlashFired: isFlashFired,
                        cameraPitchDegrees: cameraPitchDegrees,
                        compassHeading: compassHeading,
                        relativeHumidity: relativeHumidity,
                        uvIndex: uvIndex,
                        isDeleted: false
                    )
                    modelContext.insert(scan)
                    try? modelContext.save()
                    OfflineQueueManager.shared.updateUnsyncedItemCount()
                }
            } catch {
                print("Failed to enqueue capture: \(error)")
            }
        }
    }
    
    func syncPendingScans() {
        guard !HardwareOrchestrator.shared.isExpeditionModeActive else { return }
        guard isOnline else { return }
        guard !isSyncing else { return } 
        guard let container = modelContext?.container else { return }
        
        isSyncing = true
        
        #if os(iOS)
        final class SyncBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _id: UIBackgroundTaskIdentifier = .invalid
            var id: UIBackgroundTaskIdentifier {
                get { lock.withLock { _id } }
                set { lock.withLock { _id = newValue } }
            }
        }
        let syncBox = SyncBox()
        syncBox.id = UIApplication.shared.beginBackgroundTask(withName: "OfflineQueueSync") { [weak self] in
            // This expiration handler is called if we run out of time
            self?.syncTask?.cancel()
            Task { @MainActor [weak self] in
                self?.isSyncing = false
                SyncStateManager.shared.completeSync()
            }
            if syncBox.id != .invalid {
                UIApplication.shared.endBackgroundTask(syncBox.id)
                syncBox.id = .invalid
            }
        }
        let backgroundTaskID = syncBox.id
        #endif
        
        syncTask = Task.detached(priority: .background) { [backgroundTaskID] in
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            let scanData = await dbActor.fetchPendingScans(limit: 5)
            let backgroundSession = await MainActor.run { self.backgroundSession }
            let activeTasks = await backgroundSession.allTasks
            let activeScanIDs = Set(activeTasks.compactMap { $0.taskDescription })
            
            let filteredScans = scanData.filter { !activeScanIDs.contains($0.id) }
            
            guard !filteredScans.isEmpty else {
                await MainActor.run {
                    self.isSyncing = false
                    if scanData.isEmpty {
                        SyncStateManager.shared.completeSync()
                    }
                    #if os(iOS)
                    if backgroundTaskID != .invalid { UIApplication.shared.endBackgroundTask(backgroundTaskID) }
                    #endif
                }
                return
            }
            
            await MainActor.run { SyncStateManager.shared.beginSync(itemCount: filteredScans.count) }
            
            let documentsDirectory = URL.documentsDirectory
            var fileNames: [String] = []
            var fileURLs: [URL] = []
            var scanIDs: [String] = []
            
            for scan in filteredScans {
                for path in scan.localImagePaths {
                    let fileURL = documentsDirectory.appendingPathComponent(path)
                    fileNames.append("\(scan.id)_\(path)")
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
                        let tempFileURL = URL.cachesDirectory.appendingPathComponent("\(scanId)_temp_upload.jpg")
                        
                        // CRITICAL FIX: Explicitly remove orphaned files to prevent copyItem from silently failing
                        try? FileManager.default.removeItem(at: tempFileURL)
                        try? FileManager.default.copyItem(at: originalFileURL, to: tempFileURL)
                        
                        // Enqueue to the iOS Background URLSession cleanly using the physical file
                        let uploadTask = backgroundSession.uploadTask(with: request, fromFile: tempFileURL)
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
            
        SyncStateManager.shared.completeSync()
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
        
        #if os(iOS)
        final class InferenceBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _id: UIBackgroundTaskIdentifier = .invalid
            var id: UIBackgroundTaskIdentifier {
                get { lock.withLock { _id } }
                set { lock.withLock { _id = newValue } }
            }
        }
        let inferenceBox = InferenceBox()
        inferenceBox.id = UIApplication.shared.beginBackgroundTask(withName: "OfflineInference") { [weak inferenceBox] in
            // Should we timeout natively before we can handle inference
            print("Offline inference background task expired")
            if let box = inferenceBox, box.id != .invalid {
                UIApplication.shared.endBackgroundTask(box.id)
                box.id = .invalid
            }
        }
        let inferenceTaskID = inferenceBox.id
        #endif
        
        Task { @MainActor in
            guard let modelContext = OfflineQueueManager.shared.modelContext else { return }
            let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            
            guard let scan = try? modelContext.fetch(descriptor).first else { return }
            
            guard let urlPath = task.originalRequest?.url?.path, let range = urlPath.range(of: "staging/") else { return }
            let r2ObjectKey = String(urlPath[range.lowerBound...])
            
            
            do {
                let resultData = try await MerianNetworkClient.shared.analyzeSubject(
                    r2ObjectKey: r2ObjectKey,
                    depthScaleText: scan.subjectDistanceInMeters.map { String(format: "%.1f meters", $0) },
                    gpsLatitude: scan.gpsLatitude,
                    gpsLongitude: scan.gpsLongitude,
                    gpsElevation: scan.gpsElevation,
                    semanticLocation: scan.locationName,
                    weatherCondition: scan.weatherCondition,
                    weatherTemperatureF: scan.weatherTemperatureF,
                    cameraPitchDegrees: scan.cameraPitchDegrees,
                    compassHeading: scan.compassHeading,
                    relativeHumidity: scan.relativeHumidity,
                    uvIndex: scan.uvIndex,
                    isFlashFired: scan.isFlashFired
                )
                let backgroundActor = BackgroundDatabaseActor(modelContainer: modelContext.container)
                await backgroundActor.processAndCleanupOfflineScan(
                    resultData: resultData,
                    originalImagePaths: scan.localImagePaths,
                    scanId: scanId
                )
                
                OfflineQueueManager.shared.updateUnsyncedItemCount()
                CircuitBreakerManager.shared.recordSuccess()
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
    

    
    func updateUnsyncedItemCount() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { !$0.isDeleted })
        let count = (try? context.fetchCount(descriptor)) ?? 0
        Task { @MainActor in
            self.unsyncedItemsCount = count
        }
    }
    
    func softDeleteQueuedScan(scanId: String) {
        guard let modelContext = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate<OfflineQueuedScan> { $0.id == scanId })
        if let match = (try? modelContext.fetch(descriptor))?.first {
            match.isDeleted = true
            try? modelContext.save()
            updateUnsyncedItemCount()
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
    
}

@ModelActor
actor BackgroundDatabaseActor {
    struct PendingScanPayload: Sendable {
        let id: String
        let localImagePaths: [String]
    }

    func fetchPendingScans(limit: Int) -> [PendingScanPayload] {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { !$0.isDeleted })
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        descriptor.fetchLimit = limit
        
        let pending = (try? modelContext.fetch(descriptor)) ?? []
        return pending.map { PendingScanPayload(id: $0.id, localImagePaths: $0.localImagePaths) }
    }
    
    /// Called by the Offline Queue explicitly to ensure deferred scans are processed mathematically back down into the User's biological index natively.
    func processAndCleanupOfflineScan(resultData: Data, originalImagePaths: [String], scanId: String) {
        let decoder = JSONDecoder()
        if let parsedWrapper = try? decoder.decode(InferenceEngine.EdgeResponseWrapper.self, from: resultData) {
            let edgeRes = parsedWrapper.data
            
            let insight = InsightData(
                description: edgeRes.insight_data?.description ?? "No ecological description available for this subject.",
                isPoisonous: edgeRes.insight_data?.is_poisonous ?? false,
                regionalStatusRationale: edgeRes.insight_data?.regional_status_rationale
            )
            
            let taxonomyData = TaxonomyData(
                kingdom: edgeRes.taxonomy?.kingdom,
                phylum: edgeRes.taxonomy?.phylum,
                className: edgeRes.taxonomy?.class,
                order: edgeRes.taxonomy?.order,
                family: edgeRes.taxonomy?.family,
                genus: edgeRes.taxonomy?.genus
            )
            
            var mappedData = SpeciesData(
                scanId: edgeRes.scan_id,
                commonName: edgeRes.common_name ?? "Unknown Subject",
                scientificName: edgeRes.scientific_name ?? "Taxonomy Unavailable",
                insightData: insight,
                confidenceScore: edgeRes.confidence_score ?? 0.0,
                diagnosticComparison: nil,
                wikipediaUrl: edgeRes.wikipedia_url,
                wikipediaExtract: edgeRes.wikipedia_extract,
                referenceImageUrl: edgeRes.reference_image_url,
                isBiological: edgeRes.is_biological_subject ?? true,
                isLiveCapture: edgeRes.is_live_capture ?? true,
                isInvasive: edgeRes.is_invasive ?? false,
                ecologyType: edgeRes.ecology_type ?? "unknown",
                taxonomy: taxonomyData
            )
            
            if mappedData.confidenceScore > 0.0 {
                // Pre-process and securely duplicate offline image paths explicitly preventing aggressive FileManager cleanup deletions
                var newlyCopiedPaths: [String] = []
                for originalPath in originalImagePaths {
                    let sourceURL = URL.documentsDirectory.appendingPathComponent(originalPath)
                    let newFilename = "\(UUID().uuidString)_lifelist.jpg"
                    let destinationURL = URL.documentsDirectory.appendingPathComponent(newFilename)
                    
                    do {
                        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                        newlyCopiedPaths.append(newFilename)
                    } catch {
                        print("Failed to physically bridge offline queue image to persistent Life List: \(error)")
                    }
                }

                let targetName = mappedData.scientificName
                let fetchDescriptor = FetchDescriptor<LocalScanRecord>(
                    predicate: #Predicate<LocalScanRecord> { $0.scientificName == targetName }
                )
                
                if let existingRecord = try? modelContext.fetch(fetchDescriptor).first {
                    if existingRecord.additionalImagePaths == nil {
                        existingRecord.additionalImagePaths = []
                    }
                    existingRecord.additionalImagePaths?.append(contentsOf: newlyCopiedPaths)
                    existingRecord.timestamp = Date()
                    
                    existingRecord.insightDescription = mappedData.insightData.description
                    existingRecord.isPoisonous = mappedData.insightData.isPoisonous
                    existingRecord.wikipediaUrl = mappedData.wikipediaUrl ?? existingRecord.wikipediaUrl
                    existingRecord.referenceImageUrl = mappedData.referenceImageUrl ?? existingRecord.referenceImageUrl
                    existingRecord.confidenceScore = mappedData.confidenceScore
                    existingRecord.isBiological = mappedData.isBiological
                    existingRecord.isLiveCapture = mappedData.isLiveCapture
                    existingRecord.isInvasive = mappedData.isInvasive
                    existingRecord.ecologyType = mappedData.ecologyType
                    existingRecord.taxonomyKingdom = mappedData.taxonomy?.kingdom
                    existingRecord.taxonomyPhylum = mappedData.taxonomy?.phylum
                    existingRecord.taxonomyClass = mappedData.taxonomy?.className
                    existingRecord.taxonomyOrder = mappedData.taxonomy?.order
                    existingRecord.taxonomyFamily = mappedData.taxonomy?.family
                    existingRecord.taxonomyGenus = mappedData.taxonomy?.genus
                } else {
                    let record = LocalScanRecord(
                        speciesId: UUID().uuidString,
                        scientificName: mappedData.scientificName,
                        commonName: mappedData.commonName,
                        insightDescription: mappedData.insightData.description,
                        timestamp: Date(),
                        localImagePath: newlyCopiedPaths.first,
                        semanticTags: [mappedData.commonName, mappedData.scientificName],
                        isPoisonous: mappedData.insightData.isPoisonous,
                        isBiological: mappedData.isBiological,
                        isLiveCapture: mappedData.isLiveCapture,
                        isInvasive: mappedData.isInvasive,
                        ecologyType: mappedData.ecologyType,
                        wikipediaUrl: mappedData.wikipediaUrl,
                        referenceImageUrl: mappedData.referenceImageUrl,
                        additionalImagePaths: newlyCopiedPaths.count > 1 ? Array(newlyCopiedPaths.dropFirst()) : nil,
                        confidenceScore: mappedData.confidenceScore,
                        taxonomyKingdom: mappedData.taxonomy?.kingdom,
                        taxonomyPhylum: mappedData.taxonomy?.phylum,
                        taxonomyClass: mappedData.taxonomy?.className,
                        taxonomyOrder: mappedData.taxonomy?.order,
                        taxonomyFamily: mappedData.taxonomy?.family,
                        taxonomyGenus: mappedData.taxonomy?.genus
                    )
                    modelContext.insert(record)
                    mappedData.isNewDiscovery = true
                    
                    // Offline updates to Gamification are safely recorded once synced securely
                    Task { @MainActor in
                        GamificationManager.shared.recordNewSpeciesDiscovered()
                    }
                }
                try? modelContext.save()
            }
        }
        
        // Finalize cleanup explicitly ensuring UI views never hang off disk buffer purges natively
        do {
            let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            let matches = try modelContext.fetch(descriptor)
            
            for scan in matches {
                modelContext.delete(scan)
            }
            try modelContext.save()
        } catch {
            print("Background cleanup logic explicitly failed out of process offline trace natively: \(error)")
        }
    }
}
