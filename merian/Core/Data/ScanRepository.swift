import Foundation
import SwiftData

/// The generic logical abstraction over Database operations.
/// Prevents UI Components and VIewModels from directly importing SwiftData ModelContext or OfflineQueue singletons.
@MainActor
final class ScanRepository {
    static let shared = ScanRepository()
    
    private let offlineQueue = OfflineQueueManager.shared
    
    private init() {}
    
    /// Binds the system ModelContext to the repository infrastructure.
    func configure(with modelContext: ModelContext) {
        offlineQueue.modelContext = modelContext
    }
    
    /// Resolves and fetches all local scans explicitly matching a given filter scope
    func fetchLocalScans(modelContext: ModelContext, filter: String? = nil) -> [LocalScanRecord] {
        var descriptor = FetchDescriptor<LocalScanRecord>()
        
        if let searchText = filter, !searchText.isEmpty {
            let token = searchText.lowercased()
            // In a real query, we would use NSPredicate or SwiftData #Predicate based on tags
            descriptor.predicate = #Predicate { record in
                record.commonName.contains(token) || record.scientificName.contains(token)
            }
        }
        
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch LocalScans from generic repository: \(error)")
            return []
        }
    }
    
    /// Securely bridges the bytes directly to the networking infrastructure seamlessly buffering them offline if the network is absent
    func saveScan(
        imageData: Data,
        latitude: Double? = nil,
        longitude: Double? = nil,
        elevation: Double? = nil,
        weatherCondition: String? = nil,
        weatherTemperatureF: Double? = nil,
        blurScore: Double? = nil
    ) {
        offlineQueue.enqueueCapture(
            imageData: imageData,
            gpsLatitude: latitude,
            gpsLongitude: longitude,
            gpsElevation: elevation,
            weatherCondition: weatherCondition,
            weatherTemperatureF: weatherTemperatureF,
            blurScore: blurScore
        )
    }
    
    /// Prompts a force flush of any local queues. Typically managed automatically via Network observing limits.
    func syncPendingScans() {
        offlineQueue.syncPendingScans()
    }
    
    /// Purge any dynamically soft-deleted records from Local Storage persistently
    func purgeSoftDeletedRecords() {
        offlineQueue.purgeSoftDeletedRecords()
    }
    
    /// Brutally obliterates a physical scan entirely from the local disk, Local Life List, and guarantees eventual execution against Cloudflare and Postgres instances natively.
    func eradicateScan(record: LocalScanRecord, modelContext: ModelContext) {
        // 1. Wipe local image bytes physically from DocumentDirectory
        let docs = URL.documentsDirectory
        var imagesToErase: [String] = []
        if let primaryPath = record.localImagePath { imagesToErase.append(primaryPath) }
        if let extras = record.additionalImagePaths { imagesToErase.append(contentsOf: extras) }
        
        for p in imagesToErase {
            let fp = docs.appendingPathComponent(p)
            try? FileManager.default.removeItem(at: fp)
        }
        
        // 2. Halt an upload if it's unfortunately caught midway in the upload buffer queue
        offlineQueue.softDeleteQueuedScan(scanId: record.id)
        
        // 3. Queue a Task bound for the `delete-scan` Edge function securely purging Postgres/R2 bytes natively
        let backgroundErasure = PendingCloudDeletionTask(scanId: record.id)
        modelContext.insert(backgroundErasure)
        
        // 4. Destroy the immediate core SwiftData record for an optimistic-UI instantaneous disappear
        modelContext.delete(record)
        
        try? modelContext.save()
        
        // Push the delete-scan execution immediately
        Task {
            await offlineQueue.syncPendingDeletions()
        }
    }
}
