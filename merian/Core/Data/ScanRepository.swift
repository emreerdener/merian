import Foundation
import SwiftData

// MARK: - Core Database Orchestrator
/// The generic logical abstraction over Database operations.
/// Prevents UI Components and ViewModels from directly importing SwiftData ModelContext or OfflineQueue singletons.
@MainActor
final class ScanRepository {
    // MARK: - Singleton Architecture
    static let shared = ScanRepository()
    
    // MARK: - Core Dependencies
    private let offlineQueue = OfflineQueueManager.shared
    
    // MARK: - Lifecycle
    private init() {}
    
    func configure(with modelContext: ModelContext) {
        offlineQueue.modelContext = modelContext
        
        let descriptor = FetchDescriptor<ScanCollection>()
        let collections = (try? modelContext.fetch(descriptor)) ?? []
        if !collections.contains(where: { $0.name == "Favorites" }) {
            let favorites = ScanCollection(name: "Favorites")
            modelContext.insert(favorites)
            try? modelContext.save()
        }
    }
    
    // MARK: - Local Context Fetching
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
    
    // MARK: - Async Capture Persistence
    /// Securely bridges the bytes directly to the networking infrastructure seamlessly buffering them offline if the network is absent
    func saveScan(
        imageData: Data,
        telemetry: CaptureTelemetry,
        blurScore: Double? = nil
    ) {
        offlineQueue.enqueueCapture(
            imageData: imageData,
            telemetry: telemetry,
            blurScore: blurScore
        )
    }

    // MARK: - Remote Edge Syncing
    /// Re-hydration protocol binding historical Ghost/Pro cloud scans back down onto the iOS SwiftData Scans locally natively
    func syncHistoricalScansDown(modelContext: ModelContext) async {
        guard SupabaseManager.shared.isAuthenticated, 
              let userId = SupabaseManager.shared.currentUser?.id.uuidString else { return }
        
        do {
            let response: [HistoricalScanResponse] = try await SupabaseManager.shared.client
                .from("scans")
                .select("id, image_storage_urls, timestamp, weather_condition, weather_temperature_f, ai_confidence_score, ecology_type, is_invasive, is_live_capture, colors, semantic_location, gps_lat_exact, gps_long_exact, gps_elevation, species_dictionary(*)")
                .eq("user_id", value: userId)
                .execute()
                .value
            
            // Reconcile and buffer diff bounds cleanly out of SwiftData
            let descriptor = FetchDescriptor<LocalScanRecord>()
            let existingLocalScans = (try? modelContext.fetch(descriptor)) ?? []
            let existingIds = Set(existingLocalScans.map { $0.id })
            
            let missingScans = response.filter { !existingIds.contains($0.id) }
            
            if !missingScans.isEmpty {
                print("🔄 Merian Sync: Restoring \(missingScans.count) historical scan payloads natively...")
            }
            
            let collectionsResponse: [CloudCollectionResponse] = try await SupabaseManager.shared.client
                .from("collections")
                .select("id, name, created_at, collection_scans(scan_id)")
                .eq("user_id", value: userId)
                .execute()
                .value

            let container = modelContext.container
            await Task.detached(priority: .userInitiated) {
                let dbActor = HistoricalDatabaseActor(modelContainer: container)
                await dbActor.updateExistingScans(responses: response)
                
                if !missingScans.isEmpty {
                    await dbActor.ingestHistoricalScans(missingScans: missingScans)
                }
                
                await dbActor.syncCollectionsDown(remoteCollections: collectionsResponse)
            }.value
            
            if !missingScans.isEmpty {
                print("✅ Merian Sync: Restored Historical payload records.")
            }
            
        } catch {
            print("🚨 Failed strictly reconciling Offline Historical Scans from Edge bounds: \(error)")
        }
    }
    
    // MARK: - Queue Orchestration
    /// Prompts a force flush of any local queues. Typically managed automatically via Network observing limits.
    func syncPendingScans() {
        offlineQueue.syncPendingScans()
    }
    
    /// Purge any dynamically soft-deleted records from Local Storage persistently
    func purgeSoftDeletedRecords() {
        offlineQueue.purgeSoftDeletedRecords()
    }
    
    // MARK: - Destructive Hard Erasure
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

// MARK: - Cloud Data Transfer Objects (DTOs)
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
    let iucn_red_list_status: String?
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
    let semantic_location: String?
    let gps_lat_exact: Double?
    let gps_long_exact: Double?
    let gps_elevation: Double?
    let species_dictionary: CloudSpeciesDictionary?
}

struct CloudCollectionResponse: Decodable, Sendable {
    let id: String
    let name: String
    let created_at: String
    let collection_scans: [CloudCollectionScan]?
}

struct CloudCollectionScan: Decodable, Sendable {
    let scan_id: String
}

// MARK: - SwiftData Asynchronous Actors
/// Executes massive background SwiftData sync boundaries entirely detached from the Main UI Thread 
@ModelActor
actor HistoricalDatabaseActor {
    func ingestHistoricalScans(missingScans: [HistoricalScanResponse]) {
        for scan in missingScans {
            if Task.isCancelled { break }
            let parsedDate = scan.timestamp.flatMap { DateUtilities.iso8601FractionalFormatter.date(from: $0) ?? DateUtilities.iso8601Formatter.date(from: $0) } ?? Date()
            
            let dict = scan.species_dictionary
            let sciName = dict?.scientific_name ?? "Unknown Subject"
            let cName = dict?.common_names?.compactMap { $0.value }.first ?? sciName
            let desc = dict?.descriptions?["insight"]?.flatMap { $0 } ?? "No ecological description available for this subject."
            let wikiExtract = dict?.descriptions?["wikipedia"]?.flatMap { $0 }
            
            let rawR2Image = scan.image_storage_urls?.first
            let additionalUrls = (scan.image_storage_urls?.count ?? 0) > 1 ? Array(scan.image_storage_urls!.dropFirst()) : nil
            
            let dictRefImage = dict?.reference_image_url
            
            let record = LocalScanRecord(
                id: scan.id,
                speciesId: UUID().uuidString,
                scientificName: sciName,
                commonName: cName,
                insightDescription: desc,
                timestamp: parsedDate,
                localImagePath: rawR2Image,
                semanticTags: [cName, sciName] + (scan.colors ?? []),
                isPoisonous: dict?.is_poisonous ?? false,
                isBiological: true,
                isLiveCapture: scan.is_live_capture ?? true,
                isInvasive: scan.is_invasive ?? false,
                ecologyType: scan.ecology_type ?? "unknown",
                wikipediaUrl: dict?.wikipedia_url,
                wikipediaExtract: wikiExtract,
                referenceImageUrl: dictRefImage,
                additionalImagePaths: additionalUrls,
                confidenceScore: scan.ai_confidence_score,
                isLocallyArchived: false,
                taxonomyKingdom: dict?.kingdom,
                taxonomyPhylum: dict?.phylum,
                taxonomyClass: dict?.class,
                taxonomyOrder: dict?.order,
                taxonomyFamily: dict?.family,
                taxonomyGenus: dict?.genus,
                locationName: scan.semantic_location,
                weatherCondition: scan.weather_condition,
                weatherTemperatureF: scan.weather_temperature_f,
                iucnRedListStatus: dict?.iucn_red_list_status,
                gpsLatitude: scan.gps_lat_exact,
                gpsLongitude: scan.gps_long_exact,
                gpsElevation: scan.gps_elevation
            )
            
            modelContext.insert(record)
        }
        
        try? modelContext.save()
    }
    
    func updateExistingScans(responses: [HistoricalScanResponse]) {
        let descriptor = FetchDescriptor<LocalScanRecord>()
        let existingScans = (try? modelContext.fetch(descriptor)) ?? []
        var lookup: [String: LocalScanRecord] = [:]
        for scan in existingScans {
            lookup[scan.id] = scan
        }
        
        var didUpdate = false
        for res in responses {
            if let existing = lookup[res.id] {
                let rawR2Image = res.image_storage_urls?.first
                let additionalUrls = (res.image_storage_urls?.count ?? 0) > 1 ? Array(res.image_storage_urls!.dropFirst()) : nil
                let dictRefImage = res.species_dictionary?.reference_image_url
                
                if existing.localImagePath == nil && rawR2Image != nil {
                    existing.localImagePath = rawR2Image
                    didUpdate = true
                }
                
                if existing.additionalImagePaths == nil && additionalUrls != nil {
                    existing.additionalImagePaths = additionalUrls
                    didUpdate = true
                }
                
                if existing.referenceImageUrl != dictRefImage {
                    existing.referenceImageUrl = dictRefImage
                    didUpdate = true
                }
                
                if let newLoc = res.semantic_location, existing.locationName != newLoc {
                    existing.locationName = newLoc
                    didUpdate = true
                }
                
                if existing.gpsLatitude == nil, let remoteLat = res.gps_lat_exact, let remoteLon = res.gps_long_exact {
                    existing.gpsLatitude = remoteLat
                    existing.gpsLongitude = remoteLon
                    existing.gpsElevation = res.gps_elevation
                    didUpdate = true
                }
            }
        }
        
        if didUpdate {
            try? modelContext.save()
        }
    }
    
    func syncCollectionsDown(remoteCollections: [CloudCollectionResponse]) {
        let descriptor = FetchDescriptor<ScanCollection>()
        let existingCollections = (try? modelContext.fetch(descriptor)) ?? []
        var existingLookup = Dictionary(uniqueKeysWithValues: existingCollections.map { ($0.id, $0) })
        
        let allScansDescriptor = FetchDescriptor<LocalScanRecord>()
        let localScans = (try? modelContext.fetch(allScansDescriptor)) ?? []
        let localScansLookup = Dictionary(uniqueKeysWithValues: localScans.map { ($0.id, $0) })
        
        for remote in remoteCollections {
            if Task.isCancelled { break }
            let col: ScanCollection
            if let existing = existingLookup[remote.id] {
                col = existing
                existingLookup.removeValue(forKey: remote.id)
            } else {
                col = ScanCollection(name: remote.name)
                col.id = remote.id
                if let parsedDate = DateUtilities.iso8601FractionalFormatter.date(from: remote.created_at) ?? DateUtilities.iso8601Formatter.date(from: remote.created_at) {
                    col.createdAt = parsedDate
                }
                modelContext.insert(col)
            }
            
            col.name = remote.name
            
            col.scans?.removeAll()
            if let scans = remote.collection_scans {
                for scanMapping in scans {
                    if let localScan = localScansLookup[scanMapping.scan_id] {
                        if col.scans == nil { col.scans = [] }
                        col.scans?.append(localScan)
                    }
                }
            }
        }
        
        for remainingId in existingLookup.keys {
            if let obsoleteCollection = existingLookup[remainingId], obsoleteCollection.name != "Favorites" {
                modelContext.delete(obsoleteCollection)
            }
        }
        
        try? modelContext.save()
    }
}
