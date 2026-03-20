import Foundation
import Network
import Combine
import SwiftData
import ImageIO
#if canImport(UIKit)
import UIKit

/// A generic, thread-safe wrapper for managing UIBackgroundTaskIdentifier
/// Ensures strict Sendable conformance avoiding iOS strict concurrency crashes natively.
public final class BackgroundTaskWrapper: @unchecked Sendable {
    private let lock = NSLock()
    private var _id: UIBackgroundTaskIdentifier = .invalid
    
    public var id: UIBackgroundTaskIdentifier {
        get { lock.withLock { _id } }
        set { lock.withLock { _id = newValue } }
    }
    
    public init() {}
    
    public func safeEnd() {
        let currentId = id
        if currentId != .invalid {
            DispatchQueue.main.async {
                UIApplication.shared.endBackgroundTask(currentId)
            }
            id = .invalid
        }
    }
    
    @discardableResult
    public static func execute(
        name: String,
        expirationHandler: (@Sendable () -> Void)? = nil,
        operation: @escaping @Sendable (BackgroundTaskWrapper) async -> Void
    ) -> Task<Void, Never> {
        let task = BackgroundTaskWrapper()
        #if os(iOS)
        let taskId = UIApplication.shared.beginBackgroundTask(withName: name) {
            expirationHandler?()
            task.safeEnd()
        }
        task.id = taskId
        #endif
        
        return Task.detached(priority: .background) {
            await operation(task)
            task.safeEnd()
        }
    }
}
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
    
    func enqueueCapture(imageData: Data, telemetry: CaptureTelemetry, blurScore: Double? = nil) {
        let fileName = "\(UUID().uuidString).jpg"
        let documentsDirectory = URL.documentsDirectory
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        BackgroundTaskWrapper.execute(name: "OfflineQueueCaptureWrite") { _ in
            do {
                try imageData.write(to: fileURL)
                
                await MainActor.run {
                    let scan = OfflineQueuedScan(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        localImagePaths: [fileName],
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
                    guard let ctx = OfflineQueueManager.shared.modelContext else { return }
                    ctx.insert(scan)
                    do {
                        try ctx.save()
                        OfflineQueueManager.shared.updateUnsyncedItemCount()
                    } catch {
                        print("Failed to save offline queue record. Cleaning up abandoned local image footprint.")
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            } catch {
                print("Failed to enqueue capture: \(error)")
                await MainActor.run {
                }
            }
        }
    }
    
    func syncPendingScans() {
        guard !HardwareOrchestrator.shared.isExpeditionModeActive else { return }
        guard isOnline else { return }
        guard RevenueCatManager.shared.isProActive else { return }
        guard !isSyncing else { return } 
        guard let container = modelContext?.container else { return }
        
        isSyncing = true
        
        syncTask = BackgroundTaskWrapper.execute(
            name: "OfflineQueueSync",
            expirationHandler: {
                print("Offline Queue background expiration triggered")
                Task { @MainActor in SyncStateManager.shared.completeSync() }
            }
        ) { _ in
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            let scanData = await dbActor.fetchPendingScans(limit: 50)
            let backgroundSession = await MainActor.run { self.backgroundSession }
            let activeTasks = await backgroundSession.allTasks
            let activeScanIDs = Set(activeTasks.compactMap { $0.taskDescription?.components(separatedBy: "_").first ?? $0.taskDescription })
            
            let filteredScans = Array(scanData.filter { !activeScanIDs.contains($0.id) }.prefix(5))
            
            guard !filteredScans.isEmpty else {
                await MainActor.run {
                    self.isSyncing = false
                    if scanData.isEmpty {
                        SyncStateManager.shared.completeSync()
                    }
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
                        
                        // NEW FIX: Infinite queue race condition protection
                        if !FileManager.default.fileExists(atPath: originalFileURL.path) {
                            print("⚠️ Offline Queue: Original file \(originalFileURL.lastPathComponent) went missing! Tombstoning this scan globally.")
                            Task { @MainActor in
                                OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId)
                            }
                            continue
                        }
                        
                        let tempFileURL = URL.cachesDirectory.appendingPathComponent("\(scanId)_\(index)_temp_upload.jpg")
                        
                        // CRITICAL FIX: Explicitly remove orphaned files to prevent copyItem from silently failing
                        try? FileManager.default.removeItem(at: tempFileURL)
                        try? FileManager.default.copyItem(at: originalFileURL, to: tempFileURL)
                        
                        // Enqueue to the iOS Background URLSession cleanly using the physical file
                        let uploadTask = backgroundSession.uploadTask(with: request, fromFile: tempFileURL)
                        uploadTask.taskDescription = "\(scanId)_\(index)"
                        uploadTask.resume()
                    }
                    
                    // The backend will handle the actual Gemini inference asynchronously via a Supabase Storage Webhook once the file lands in the R2 staging bucket.
                    
                } catch {
                    print("Failed to request Background staging URLs natively: \(error)")
                }
                
                await MainActor.run {
                    self.isSyncing = false
                    SyncStateManager.shared.completeSync()
                }
            }
            
        SyncStateManager.shared.completeSync()
    }
    
    /// Triggered exclusively when the Background Networking Queue finishes physical transmission of the bytes natively
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        BackgroundTaskWrapper.execute(
            name: "OfflineInference",
            expirationHandler: {
                print("Offline inference background task expired")
            }
        ) { _ in
            
            guard let taskDesc = task.taskDescription else {
            return
        }
        
        let components = taskDesc.components(separatedBy: "_")
        let scanId = components[0]
        let indexPart = components.count > 1 ? components[1] : ""
        
        let tempFileURL = URL.cachesDirectory.appendingPathComponent(indexPart.isEmpty ? "\(scanId)_temp_upload.jpg" : "\(scanId)_\(indexPart)_temp_upload.jpg")
        try? FileManager.default.removeItem(at: tempFileURL)
        
        guard error == nil else {
            print("Background upload hard failed: \(error!)")
            return
        }
        
        guard let response = task.response as? HTTPURLResponse, response.statusCode == 200 else {
            let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            let recoverableCodes = [403, 500, 502, 503, 504]
            
            if recoverableCodes.contains(statusCode) {
                print("Background upload failed with recoverable status (\(statusCode)). Retaining in queue.")
            } else {
                print("Background upload rejected physically by boundary constraints. Server returned an error.")
                await MainActor.run {
                    OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId)
                }
            }
            return
        }
        
        struct ExtractedScanData {
            let telemetry: CaptureTelemetry
            let localImagePaths: [String]
            let container: ModelContainer
        }
        
        guard let urlPath = task.originalRequest?.url?.path, let range = urlPath.range(of: "staging/") else {
            return
        }
        let r2ObjectKey = String(urlPath[range.lowerBound...])

        let scanData = await MainActor.run { () -> ExtractedScanData? in
            guard let modelContext = OfflineQueueManager.shared.modelContext,
                  let container = OfflineQueueManager.shared.modelContext?.container else {
                return nil
            }
            let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            guard let scan = try? modelContext.fetch(descriptor).first else { return nil }
            
            let telemetry = CaptureTelemetry(
                subjectDistanceInMeters: scan.subjectDistanceInMeters,
                gpsLatitude: scan.gpsLatitude,
                gpsLongitude: scan.gpsLongitude,
                gpsElevation: scan.gpsElevation,
                locationName: scan.locationName,
                weatherCondition: scan.weatherCondition,
                weatherTemperatureF: scan.weatherTemperatureF,
                timeOfDay: nil
            )
            
            return ExtractedScanData(telemetry: telemetry, localImagePaths: scan.localImagePaths, container: container)
        }
        
        guard let extracted = scanData else {
            return
        }
        
        do {
            let resultData = try await MerianNetworkClient.shared.analyzeSubject(
                r2ObjectKey: r2ObjectKey,
                base64ImageData: nil,
                telemetry: extracted.telemetry
            )
            
            let backgroundActor = BackgroundDatabaseActor(modelContainer: extracted.container)
            await backgroundActor.processAndCleanupOfflineScan(
                resultData: resultData,
                originalImagePaths: extracted.localImagePaths,
                scanId: scanId
            )
            
            await MainActor.run {
                OfflineQueueManager.shared.updateUnsyncedItemCount()
                CircuitBreakerManager.shared.recordSuccess()
            }
        } catch {
            print("Failed downstream inference on offline queued scan: \(error)")
        }
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
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.isDeleted == false })
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
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.isDeleted == true })
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
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.isDeleted == false })
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
            var mappedData = SpeciesData(fromEdgeResponse: edgeRes, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)
            
            if mappedData.confidenceScore > 0.0 {
                // Retain exactly the original image paths to prevent sandbox leaks natively on SwiftData failures
                let newlyCopiedPaths: [String] = originalImagePaths

                let targetName = mappedData.scientificName
                let fetchDescriptor = FetchDescriptor<LocalScanRecord>(
                    predicate: #Predicate<LocalScanRecord> { $0.scientificName == targetName }
                )
                
                let existingRecords = (try? modelContext.fetch(fetchDescriptor)) ?? []
                let activeSpeciesId = existingRecords.first?.speciesId ?? UUID().uuidString
                
                if existingRecords.isEmpty {
                    mappedData.isNewDiscovery = true
                    // Offline updates to Gamification are safely recorded once synced securely
                    Task { @MainActor in
                        GamificationManager.shared.recordNewSpeciesDiscovered()
                    }
                }
                
                let record = LocalScanRecord(
                    id: mappedData.scanId ?? UUID().uuidString,
                    speciesId: activeSpeciesId,
                    scientificName: mappedData.scientificName,
                    commonName: mappedData.commonName,
                    insightDescription: mappedData.insightData.description,
                    timestamp: Date(),
                    localImagePath: newlyCopiedPaths.first,
                    semanticTags: [mappedData.commonName, mappedData.scientificName] + (mappedData.colors ?? []),
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
                    taxonomyGenus: mappedData.taxonomy?.genus,
                    diagnosticPrimaryRationale: mappedData.diagnosticComparison?.primaryMatchRationale,
                    diagnosticLookalikeName: mappedData.diagnosticComparison?.confusingLookalikeName,
                    diagnosticDifferentiatorsJson: {
                        guard let diffs = mappedData.diagnosticComparison?.keyDifferentiators, let data = try? JSONEncoder().encode(diffs) else { return nil }
                        return String(data: data, encoding: .utf8)
                    }(),
                    iucnRedListStatus: mappedData.iucnRedListStatus
                )
                modelContext.insert(record)
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
            
            // CRITICAL FIX: Explicitly drop the local .jpg payloads off the physical iOS SSD preventing gigabytes of storage leaks
            // because the successful record resolves its Base64/Network trace safely inside the cloud loop.
            let documentsDirectory = URL.documentsDirectory
            for path in originalImagePaths {
                let fileURL = documentsDirectory.appendingPathComponent(path)
                try? FileManager.default.removeItem(at: fileURL)
            }
            
        } catch {
            print("Background cleanup logic explicitly failed out of process offline trace natively: \(error)")
        }
    }
    
    /// Handles native UI ingestions safely inside the Actor Thread isolated entirely away from UI and Detached Task loops
    func saveLiveScanRecord(mappedData: SpeciesData, compressedData: Data) -> Bool {
        var newDiscovery = false
        if mappedData.confidenceScore > 0.0 {
            let filename = "\(UUID().uuidString)_scan.jpg"
            let url = URL.documentsDirectory.appendingPathComponent(filename)
            try? compressedData.write(to: url, options: .atomic)
            
            let targetName = mappedData.scientificName
            let fetchDescriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.scientificName == targetName }
            )
            
            let existingRecords = (try? modelContext.fetch(fetchDescriptor)) ?? []
            let activeSpeciesId = existingRecords.first?.speciesId ?? UUID().uuidString
            
            if existingRecords.isEmpty {
                newDiscovery = true
            }
            
            let record = LocalScanRecord(
                id: mappedData.scanId ?? UUID().uuidString,
                speciesId: activeSpeciesId,
                scientificName: mappedData.scientificName,
                commonName: mappedData.commonName,
                insightDescription: mappedData.insightData.description,
                timestamp: Date(),
                localImagePath: filename,
                semanticTags: [mappedData.commonName, mappedData.scientificName] + (mappedData.colors ?? []),
                isPoisonous: mappedData.insightData.isPoisonous,
                isBiological: mappedData.isBiological,
                isLiveCapture: mappedData.isLiveCapture,
                isInvasive: mappedData.isInvasive,
                ecologyType: mappedData.ecologyType,
                wikipediaUrl: mappedData.wikipediaUrl,
                referenceImageUrl: mappedData.referenceImageUrl,
                confidenceScore: mappedData.confidenceScore,
                taxonomyKingdom: mappedData.taxonomy?.kingdom,
                taxonomyPhylum: mappedData.taxonomy?.phylum,
                taxonomyClass: mappedData.taxonomy?.className,
                taxonomyOrder: mappedData.taxonomy?.order,
                taxonomyFamily: mappedData.taxonomy?.family,
                taxonomyGenus: mappedData.taxonomy?.genus,
                locationName: mappedData.locationName,
                weatherCondition: mappedData.weatherCondition,
                weatherTemperatureF: mappedData.weatherTemperatureF,
                diagnosticPrimaryRationale: mappedData.diagnosticComparison?.primaryMatchRationale,
                diagnosticLookalikeName: mappedData.diagnosticComparison?.confusingLookalikeName,
                diagnosticDifferentiatorsJson: {
                    guard let diffs = mappedData.diagnosticComparison?.keyDifferentiators, let data = try? JSONEncoder().encode(diffs) else { return nil }
                    return String(data: data, encoding: .utf8)
                }(),
                iucnRedListStatus: mappedData.iucnRedListStatus
            )
            modelContext.insert(record)
            try? modelContext.save()
        }
        return newDiscovery
    }
}
