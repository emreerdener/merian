import Foundation
import SwiftData
import os

// MARK: - Scan Repository

/// Facade over `OfflineQueueManager` and SwiftData for scan persistence and sync.
///
/// Keeps UI components and view models decoupled from `ModelContext` and queue internals.
/// Inject the `ModelContext` once at startup via `configure(with:)`.
@MainActor
final class ScanRepository {

    // MARK: - Singleton

    static let shared = ScanRepository()

    // MARK: - Dependencies

    private let offlineQueue = OfflineQueueManager.shared

    // MARK: - Lifecycle

    private init() {}

    /// Injects the SwiftData context and seeds the default "Favorites" collection if absent.
    ///
    /// The Favorites check is deferred to a `Task` so the synchronous launch path is never
    /// blocked by a SQLite fetch. On large libraries the original synchronous fetch caused a
    /// visible hitch before the first frame rendered.
    func configure(with modelContext: ModelContext) {
        offlineQueue.modelContext = modelContext
        Task { @MainActor in
            self.seedFavoritesIfNeeded(modelContext: modelContext)
        }
    }

    private func seedFavoritesIfNeeded(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<ScanCollection>(
            predicate: #Predicate { $0.name == "Favorites" }
        )
        descriptor.fetchLimit = 1
        guard let count = try? modelContext.fetchCount(descriptor) else { return }
        guard count == 0 else { return }

        let favorites = ScanCollection(name: "Favorites")
        modelContext.insert(favorites)
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("configure: Favorites seed save failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Local Fetching

    /// Fetches `LocalScanRecord` entries, optionally filtered by a search string matched against common and scientific name.
    func fetchLocalScans(modelContext: ModelContext, filter: String? = nil) -> [LocalScanRecord] {
        var descriptor = FetchDescriptor<LocalScanRecord>()

        if let searchText = filter, !searchText.isEmpty {
            // SwiftData evaluates localizedStandardContains in SQLite directly with smart case matching
            descriptor.predicate = #Predicate { record in
                record.commonName.localizedStandardContains(searchText) || record.scientificName.localizedStandardContains(searchText)
            }
        }

        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.error("Failed to fetch LocalScans from generic repository: \(error, privacy: .private)")
            return []
        }
    }

    // MARK: - Capture Persistence

    /// Enqueues a capture for upload, writing image data to disk and buffering offline if connectivity is absent.
    func saveScan(
        imageData: Data,
        telemetry: CaptureTelemetry,
        blurScore: Double? = nil
    ) {
        offlineQueue.enqueueCapture(
            imageDatas: [imageData],
            telemetry: telemetry,
            blurScore: blurScore
        )
    }

    // MARK: - Remote Sync

    /// Pulls the authenticated user's scan and collection history from Supabase and reconciles it with the local SwiftData store.
    ///
    /// Fetches are paginated (`MerianConfig.historicalSyncPageSize` / `collectionsSyncPageSize`) to
    /// prevent OOM on accounts with large histories. All reconciliation work runs on a single
    /// `HistoricalDatabaseActor` invocation to minimise actor-boundary crossings.
    func syncHistoricalScansDown(modelContext: ModelContext) async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id.uuidString else { return }

        do {
            let container = modelContext.container
            let dbActor = HistoricalDatabaseActor(modelContainer: container)

            // --- Push local collections before pulling ---
            // Local collections created while offline (or before auth completed) are never
            // uploaded by the on-demand syncCollections() path. If we reconcile against
            // the cloud first, those unsynced collections will be deleted during the sync pass.
            // Pushing here ensures every local collection reaches Supabase before we treat
            // the cloud as the source of truth for the delete pass.
            let pushActor = BackgroundDatabaseActor(modelContainer: container)
            await pushActor.pushCollectionsToEdge()

            // --- Paginated scans — streamed page-by-page through the actor ---
            // Never accumulate the full history into memory. For power users with 10k+ scans
            // the full allScans[] array can exceed 100 MB before any processing begins,
            // causing OOM kills on 3GB devices under memory pressure.
            var scanOffset = 0
            let scanPageSize = MerianConfig.historicalSyncPageSize
            var totalNewRecords = 0

            while true {
                let page: [HistoricalScanResponse] = try await SupabaseManager.shared.client
                    .from("scans")
                    .select("id, image_storage_urls, timestamp, weather_condition, weather_temperature_f, ai_confidence_score, ecology_type, is_invasive, is_live_capture, colors, semantic_location, gps_lat_exact, gps_long_exact, gps_elevation, species_dictionary(*)")
                    .eq("user_id", value: userId)
                    .order("timestamp", ascending: false)
                    .range(from: scanOffset, to: scanOffset + scanPageSize - 1)
                    .execute()
                    .value
                if !page.isEmpty {
                    if scanOffset == 0 {
                        MerianLog.data.debug("🔄 Merian Sync: Streaming remote scan pages (page size: \(scanPageSize, privacy: .public))…")
                    }
                    totalNewRecords += await dbActor.reconcileScanPage(responses: page)
                }
                if page.count < scanPageSize { break }
                scanOffset += scanPageSize
            }

            // --- Paginated collections fetch ---
            var allCollections: [CloudCollectionResponse] = []
            var colOffset = 0
            let colPageSize = MerianConfig.collectionsSyncPageSize
            while true {
                let page: [CloudCollectionResponse] = try await SupabaseManager.shared.client
                    .from("collections")
                    .select("id, name, created_at, collection_scans(scan_id)")
                    .eq("user_id", value: userId)
                    .range(from: colOffset, to: colOffset + colPageSize - 1)
                    .execute()
                    .value
                allCollections.append(contentsOf: page)
                if page.count < colPageSize { break }
                colOffset += colPageSize
            }

            // Reconcile collections after all scan pages have been ingested so that
            // collection → scan relationships can resolve against the full local set.
            await dbActor.syncCollectionsDown(remoteCollections: allCollections)

            if totalNewRecords > 0 {
                MerianLog.data.debug("✅ Merian Sync: Restored \(totalNewRecords, privacy: .public) new historical records.")
            }

        } catch {
            MerianLog.data.error("🚨 Failed reconciling historical scans from Supabase: \(error, privacy: .private)")
        }
    }

    // MARK: - Queue Control

    /// Triggers an immediate upload flush. Normally managed automatically on connectivity change.
    func syncPendingScans() {
        offlineQueue.syncPendingScans()
    }

    /// Permanently removes all soft-deleted queue records and their associated image files from disk.
    func purgeSoftDeletedRecords() {
        offlineQueue.purgeSoftDeletedRecords()
    }

    // MARK: - Deletion

    /// Fully deletes a scan: queues a cloud deletion task, removes the `LocalScanRecord` from
    /// SwiftData, tombstones any in-flight upload, then asynchronously purges local image files.
    ///
    /// Database operations are committed first so that a file-deletion failure (non-fatal, cleanable)
    /// can never leave the database in an inconsistent state. The cloud deletion
    /// (`delete-scan` Edge function) is attempted immediately and retried on subsequent
    /// connectivity cycles via `PendingCloudDeletionTask`.
    func eradicateScan(record: LocalScanRecord, modelContext: ModelContext) {
        // Collect image paths before deleting the record.
        var imagesToErase: [String] = []
        if let primaryPath = record.localImagePath { imagesToErase.append(primaryPath) }
        if let extras = record.additionalImagePaths { imagesToErase.append(contentsOf: extras) }

        // 1. Tombstone any in-flight upload.
        offlineQueue.softDeleteQueuedScan(scanId: record.id)

        // 2. Queue cloud deletion task + remove SwiftData record atomically.
        let backgroundErasure = PendingCloudDeletionTask(scanId: record.id)
        modelContext.insert(backgroundErasure)
        modelContext.delete(record)

        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("🚨 eradicateScan: modelContext save failed — aborting file deletion to preserve consistency: \(error, privacy: .private)")
            // Do not proceed to file deletion; the record still exists and the queue task
            // was not persisted, so state remains consistent.
            return
        }

        // 3. Purge local image files through the dedicated I/O actor — only after DB commit succeeds.
        let localPaths = imagesToErase.filter { !$0.starts(with: "http") }
        if !localPaths.isEmpty {
            Task {
                await FileIOActor.shared.deleteImages(at: localPaths)
            }
        }

        // 4. Push the cloud deletion immediately.
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
            MerianLog.data.debug("✅ Successfully purged all SwiftData records natively.")
        } catch {
            MerianLog.data.error("🚨 Failed to erase local ModelContainer: \(error.localizedDescription, privacy: .private)")
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

/// Executes bulk background SwiftData sync boundaries entirely detached from the Main UI Thread.
@ModelActor
actor HistoricalDatabaseActor {

    // MARK: - Cached sync state

    /// Local scan ID set, pre-computed once per sync session and updated incrementally as
    /// new records are inserted. Avoids a full-library fetch on every page call.
    private var cachedLocalIds: Set<String>? = nil

    // MARK: - Paged API (primary entry points from syncHistoricalScansDown)

    /// Reconciles a single page of remote scan responses against local state.
    ///
    /// On the first call `cachedLocalIds` is computed from the database. Subsequent calls
    /// reuse and update the cached set so the full-library fetch runs exactly once per session
    /// regardless of how many pages are streamed.
    ///
    /// - Returns: The number of new `LocalScanRecord` rows inserted from this page.
    @discardableResult
    func reconcileScanPage(responses: [HistoricalScanResponse]) -> Int {
        if cachedLocalIds == nil {
            var desc = FetchDescriptor<LocalScanRecord>()
            desc.propertiesToFetch = [\.id]
            let existing = (try? modelContext.fetch(desc)) ?? []
            cachedLocalIds = Set(existing.map { $0.id })
        }
        var existingIds = cachedLocalIds!

        updateExistingScans(responses: responses, existingIds: existingIds)

        let missingScans = responses.filter { !existingIds.contains($0.id) }
        if !missingScans.isEmpty {
            ingestScans(missingScans: missingScans)
            for scan in missingScans { existingIds.insert(scan.id) }
            cachedLocalIds = existingIds
        }

        return missingScans.count
    }

    /// Reconciles the full remote collection list against local state, then resets the
    /// cached ID set so the next sync session starts fresh.
    func syncCollectionsDown(remoteCollections: [CloudCollectionResponse]) {
        syncCollections(remoteCollections: remoteCollections)
        cachedLocalIds = nil
    }

    // MARK: - Legacy bulk API (kept for test compatibility)

    /// Single entry point for all historical reconciliation work.
    ///
    /// Delegates to the paged helpers so behaviour is identical. Prefer calling
    /// `reconcileScanPage` + `syncCollectionsDown` directly to avoid accumulating
    /// the full history in the caller's memory.
    ///
    /// - Returns: The number of new `LocalScanRecord` rows inserted.
    @discardableResult
    func reconcileAllHistoricalData(
        responses: [HistoricalScanResponse],
        collections: [CloudCollectionResponse]
    ) -> Int {
        cachedLocalIds = nil  // Reset so reconcileScanPage recomputes existingIds from DB
        let newCount = reconcileScanPage(responses: responses)
        syncCollectionsDown(remoteCollections: collections)
        return newCount
    }

    // MARK: - Private Helpers

    private func updateExistingScans(responses: [HistoricalScanResponse], existingIds: Set<String>) {
        // Only fetch records that are both local and in the remote response.
        let responseIds = responses.map { $0.id }.filter { existingIds.contains($0) }
        guard !responseIds.isEmpty else { return }

        // Batch into chunks of 500 to keep SQLite IN-clause sizes within efficient planner range.
        // Large IN lists (>500 entries) degrade the query planner from index-seek to table-scan.
        let chunkSize = 500
        var allExistingScans: [LocalScanRecord] = []
        allExistingScans.reserveCapacity(responseIds.count)

        for chunkStart in stride(from: 0, to: responseIds.count, by: chunkSize) {
            let chunk = Array(responseIds[chunkStart..<min(chunkStart + chunkSize, responseIds.count)])
            var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { chunk.contains($0.id) })
            descriptor.propertiesToFetch = [\.id, \.localImagePath, \.additionalImagePaths,
                                             \.referenceImageUrl, \.locationName,
                                             \.gpsLatitude, \.gpsLongitude, \.gpsElevation]
            let chunk_records: [LocalScanRecord] = {
                do { return try modelContext.fetch(descriptor) }
                catch { MerianLog.data.error("🚨 updateExistingScans: fetch failed: \(error, privacy: .private)"); return [] }
            }()
            allExistingScans.append(contentsOf: chunk_records)
        }

        let lookup: [String: LocalScanRecord] = Dictionary(uniqueKeysWithValues: allExistingScans.map { ($0.id, $0) })

        var didUpdate = false
        for res in responses {
            guard let existing = lookup[res.id] else { continue }
            let rawR2Image = res.image_storage_urls?.first
            let additionalUrls = res.image_storage_urls.flatMap { urls in urls.count > 1 ? Array(urls.dropFirst()) : nil }
            let dictRefImage = res.species_dictionary?.reference_image_url

            if existing.localImagePath == nil && rawR2Image != nil {
                existing.localImagePath = rawR2Image; didUpdate = true
            }
            if existing.additionalImagePaths == nil && additionalUrls != nil {
                existing.additionalImagePaths = additionalUrls; didUpdate = true
            }
            if existing.referenceImageUrl != dictRefImage {
                existing.referenceImageUrl = dictRefImage; didUpdate = true
            }
            if let newLoc = res.semantic_location, existing.locationName != newLoc {
                existing.locationName = newLoc; didUpdate = true
            }
            if existing.gpsLatitude == nil, let remoteLat = res.gps_lat_exact, let remoteLon = res.gps_long_exact {
                existing.gpsLatitude = remoteLat
                existing.gpsLongitude = remoteLon
                existing.gpsElevation = res.gps_elevation
                didUpdate = true
            }
        }

        if didUpdate {
            do { try modelContext.save() }
            catch { MerianLog.data.error("🚨 updateExistingScans: save failed: \(error, privacy: .private)") }
        }
    }

    private func ingestScans(missingScans: [HistoricalScanResponse]) {
        let checkpointInterval = MerianConfig.ingestCheckpointInterval
        for (index, scan) in missingScans.enumerated() {
            if Task.isCancelled { break }
            let parsedDate = scan.timestamp.flatMap {
                DateUtilities.iso8601FractionalFormatter.date(from: $0) ?? DateUtilities.iso8601Formatter.date(from: $0)
            } ?? Date()

            let dict = scan.species_dictionary
            let sciName = dict?.scientific_name ?? "Unknown Subject"
            let cName = dict?.common_names?.compactMap { $0.value }.first ?? sciName
            let desc = dict?.descriptions?["insight"]?.flatMap { $0 } ?? "No ecological description available for this subject."
            let wikiExtract = dict?.descriptions?["wikipedia"]?.flatMap { $0 }

            let rawR2Image = scan.image_storage_urls?.first
            let additionalUrls = scan.image_storage_urls.flatMap { urls in urls.count > 1 ? Array(urls.dropFirst()) : nil }

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
                referenceImageUrl: dict?.reference_image_url,
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

            if (index + 1).isMultiple(of: checkpointInterval) {
                do { try modelContext.save() }
                catch { MerianLog.data.error("🚨 ingestScans: checkpoint save failed at index \(index): \(error, privacy: .private)") }
            }
        }

        do { try modelContext.save() }
        catch { MerianLog.data.error("🚨 ingestScans: final save failed: \(error, privacy: .private)") }
    }

    private func syncCollections(remoteCollections: [CloudCollectionResponse]) {
        let collectionsDescriptor = FetchDescriptor<ScanCollection>()
        let existingCollections: [ScanCollection] = {
            do { return try modelContext.fetch(collectionsDescriptor) }
            catch { MerianLog.data.error("🚨 syncCollections: collections fetch failed: \(error, privacy: .private)"); return [] }
        }()
        var existingLookup = Dictionary(uniqueKeysWithValues: existingCollections.map { ($0.id, $0) })

        // Fetch only the local scan records referenced by the incoming collections.
        let referencedScanIds = remoteCollections.compactMap { $0.collection_scans }.flatMap { $0 }.map { $0.scan_id }
        var allScansDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { referencedScanIds.contains($0.id) })
        allScansDescriptor.propertiesToFetch = [\.id]
        let localScans: [LocalScanRecord] = referencedScanIds.isEmpty ? [] : {
            do { return try modelContext.fetch(allScansDescriptor) }
            catch { MerianLog.data.error("🚨 syncCollections: local scans fetch failed: \(error, privacy: .private)"); return [] }
        }()
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

        for (_, obsolete) in existingLookup where obsolete.name != "Favorites" {
            modelContext.delete(obsolete)
        }

        do { try modelContext.save() }
        catch { MerianLog.data.error("🚨 syncCollections: save failed: \(error, privacy: .private)") }
    }
}
