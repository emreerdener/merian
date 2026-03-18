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

    /// Re-hydration protocol binding historical Ghost/Pro cloud scans back down onto the iOS SwiftData Scans locally natively
    func syncHistoricalScansDown(modelContext: ModelContext) async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        struct CloudSpeciesDictionary: Decodable, Sendable {
            let scientific_name: String?
            let kingdom: String?
            let phylum: String?
            let `class`: String?
            let order: String?
            let family: String?
            let genus: String?
            let wikipedia_url: String?
            let reference_image_url: String?
            let is_poisonous: Bool?
            let common_names: [String: String?]?
            let descriptions: [String: String?]?
        }
        
        struct HistoricalScanResponse: Decodable, Sendable {
            let id: String
            let image_storage_urls: [String]?
            let timestamp: String?
            let weather_condition: String?
            let weather_temperature_f: Double?
            let ai_confidence_score: Double?
            let ecology_type: String?
            let is_invasive: Bool?
            let is_live_capture: Bool?
            let colors: [String]?
            let species_dictionary: CloudSpeciesDictionary?
        }
        
        do {
            let response: [HistoricalScanResponse] = try await SupabaseManager.shared.client
                .from("scans")
                .select("id, image_storage_urls, timestamp, weather_condition, weather_temperature_f, ai_confidence_score, ecology_type, is_invasive, is_live_capture, colors, species_dictionary(*)")
                .execute()
                .value
            
            // Reconcile and buffer diff bounds cleanly out of SwiftData
            let descriptor = FetchDescriptor<LocalScanRecord>()
            let existingLocalScans = (try? modelContext.fetch(descriptor)) ?? []
            let existingIds = Set(existingLocalScans.map { $0.id })
            
            let missingScans = response.filter { !existingIds.contains($0.id) }
            guard !missingScans.isEmpty else { return }
            
            print("🔄 Merian Sync: Restoring \(missingScans.count) historical scan payloads natively...")
            
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            
            for scan in missingScans {
                let parsedDate = scan.timestamp.flatMap { isoFormatter.date(from: $0) ?? fallbackFormatter.date(from: $0) } ?? Date()
                
                let dict = scan.species_dictionary
                let sciName = dict?.scientific_name ?? "Unknown Subject"
                let cName = dict?.common_names?.compactMap { $0.value }.first ?? sciName
                let desc = dict?.descriptions?.compactMap { $0.value }.first ?? "No ecological description available for this subject."
                
                // If it exists safely mapped in R2, explicitly ingest the clean public Cloudflare Web URL natively
                let rawR2Image = scan.image_storage_urls?.first
                
                let record = LocalScanRecord(
                    id: scan.id,
                    speciesId: UUID().uuidString,
                    scientificName: sciName,
                    commonName: cName,
                    insightDescription: desc,
                    timestamp: parsedDate,
                    localImagePath: nil, // We enforce physical absence here, dropping cleanly onto the R2 payload URL below natively
                    semanticTags: [cName, sciName] + (scan.colors ?? []),
                    isPoisonous: dict?.is_poisonous ?? false,
                    isBiological: true,
                    isLiveCapture: scan.is_live_capture ?? true,
                    isInvasive: scan.is_invasive ?? false,
                    ecologyType: scan.ecology_type ?? "unknown",
                    wikipediaUrl: dict?.wikipedia_url,
                    referenceImageUrl: rawR2Image ?? dict?.reference_image_url,
                    additionalImagePaths: nil,
                    confidenceScore: scan.ai_confidence_score,
                    isLocallyArchived: false,
                    taxonomyKingdom: dict?.kingdom,
                    taxonomyPhylum: dict?.phylum,
                    taxonomyClass: dict?.class,
                    taxonomyOrder: dict?.order,
                    taxonomyFamily: dict?.family,
                    taxonomyGenus: dict?.genus,
                    locationName: nil,
                    weatherCondition: scan.weather_condition,
                    weatherTemperatureF: scan.weather_temperature_f
                )
                
                modelContext.insert(record)
            }
            
            try? modelContext.save()
            print("✅ Merian Sync: Restored Historical payload records.")
            
        } catch {
            print("🚨 Failed strictly reconciling Offline Historical Scans from Edge bounds: \(error)")
        }
    }
    
    /// Prompts a force flush of any local queues. Typically managed automatically via Network observing limits.
    func syncPendingScans() {
        offlineQueue.syncPendingScans()
    }
    
    /// Purge any dynamically soft-deleted records from Local Storage persistently
    func purgeSoftDeletedRecords() {
        offlineQueue.purgeSoftDeletedRecords()
    }
    
    /// Brutally obliterates a physical scan entirely from the local disk, Local Scans, and guarantees eventual execution against Cloudflare and Postgres instances natively.
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
    
    /// Completely eradicates all local database caches and queued data. Use only for full account deletion or hard resets.
    func purgeAllData(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: LocalScanRecord.self)
            try modelContext.delete(model: ScanCollection.self)
            try modelContext.delete(model: OfflineQueuedScan.self)
            try modelContext.delete(model: PendingCloudDeletionTask.self)
            try modelContext.save()
            print("✅ Successfully purged all SwiftData records natively.")
        } catch {
            print("🚨 Failed to erase local ModelContainer: \(error.localizedDescription)")
        }
    }
}
