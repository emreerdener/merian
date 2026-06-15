import Foundation
import os
import SwiftData

// MARK: - Scan Repository

/// Facade over `OfflineQueueManager` and SwiftData for scan persistence and sync.
///
/// Keeps UI components and view models decoupled from `ModelContext` and queue internals.
/// Inject the `ModelContext` once at startup via `configure(with:)`.
@MainActor
final class ScanRepository {

    // MARK: - Singleton

    static let shared = ScanRepository()
    private static let historicalScanSelectColumns = "id, image_storage_urls, timestamp, weather_condition, weather_temperature_f, ai_confidence_score, ecology_type, is_invasive, is_live_capture, colors, semantic_location, gps_lat_exact, gps_long_exact, gps_elevation, ai_reasoning, estimated_size_cm, life_stage, reproductive_condition, sex, sex_confidence, sex_evidence, individual_count, ecological_interactions, inference_tier, custom_tags, candidates, user_identification_override, user_confirmed_identification, image_quality_score, species_dictionary!scans_species_id_fkey(scientific_name, kingdom, phylum, class, order, family, genus, wikipedia_url, reference_image_url, hazard_type, common_names, wikipedia_overview, iucn_red_list_status, habitat_description, group_tags)"

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
            modelContext.rollback()
            MerianLog.data.error("configure: Favorites seed save failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Local Fetching

    // MARK: - Replaced Manual Fetchers
    // `fetchLocalCollections` and `fetchLocalScans` have been deleted.
    // The MainActor UI relies natively on iOS 17 declarative @Query macros over the globally elevated LocalScanRecord structure.

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
            // uploaded until OfflineQueueManager drains pending collection sync work. If we reconcile against
            // the cloud first, those unsynced collections will be deleted during the sync pass.
            // Route this through OfflineQueueManager's shared drain so launch-time historical
            // sync cannot race a stale background upsert against a newer tombstone delete.
            if UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync) {
                let didDrainCollections = await offlineQueue.drainCollectionSyncIfPossible()
                guard didDrainCollections else {
                    MerianLog.data.debug("syncHistoricalScansDown: skipped cloud reconciliation because pending collection mutations could not be drained safely.")
                    return
                }
            }

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
                    .select(Self.historicalScanSelectColumns)
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
            // Collections must be fully accumulated before calling syncCollectionsDown because
            // syncCollections deletes local collections absent from the remote set — streaming
            // per page would incorrectly delete collections that exist on future pages.
            // Memory exposure is bounded: sync-collections enforces MAX_COLLECTIONS = 200 on
            // write, so the remote DB cannot hold more than 200 rows for this user.
            var allCollections: [CloudCollectionResponse] = []
            allCollections.reserveCapacity(MerianConfig.collectionsSyncPageSize)
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
            Task { @MainActor in
                ScanLibraryEvents.postLibraryDidUpdate()
            }

        } catch {
            MerianLog.data.error("🚨 Failed reconciling historical scans from Supabase: \(error, privacy: .private)")
        }
    }

    /// Pulls a single completed scan by ID after the outbox status endpoint confirms
    /// the server has persisted it. This avoids waiting for a full historical sync when
    /// the photo's EXIF timestamp places it deep in the user's remote history.
    func syncHistoricalScanDown(scanId: String, modelContext: ModelContext) async -> Bool {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id.uuidString else { return false }

        do {
            let container = modelContext.container
            let dbActor = HistoricalDatabaseActor(modelContainer: container)
            let response: [HistoricalScanResponse] = try await SupabaseManager.shared.client
                .from("scans")
                .select(Self.historicalScanSelectColumns)
                .eq("user_id", value: userId)
                .eq("id", value: scanId)
                .limit(1)
                .execute()
                .value

            guard !response.isEmpty else {
                MerianLog.data.debug(
                    "syncHistoricalScanDown: server had status=found but targeted fetch returned no row scanId=\(scanId, privacy: .public)"
                )
                return false
            }

            let newRecords = await dbActor.reconcileScanPage(responses: response)
            MerianLog.data.debug(
                "syncHistoricalScanDown: reconciled scanId=\(scanId, privacy: .public) newRecords=\(newRecords, privacy: .public)"
            )
            ScanLibraryEvents.postLibraryDidUpdate()
            return true
        } catch {
            MerianLog.data.error(
                "syncHistoricalScanDown: failed scanId=\(scanId, privacy: .public) error=\(error, privacy: .private)"
            )
            return false
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

    func purgeExpiredNonBiologicalScans(
        modelContainer: ModelContainer,
        referenceDate: Date = Date()
    ) async {
        guard let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -MerianConfig.nonBiologicalRetentionDays,
            to: referenceDate
        ) else { return }

        let actor = BackgroundDatabaseActor(modelContainer: modelContainer)

        do {
            let result = try await actor.purgeExpiredNonBiologicalScans(cutoffDate: cutoffDate)
            guard result.deletedRecordCount > 0 else { return }

            await FileIOActor.shared.deleteFiles(at: result.localMediaPaths)
            ScanLibraryEvents.postLibraryDidUpdate()
            await offlineQueue.syncPendingDeletions()
            MerianLog.data.debug(
                "purgeExpiredNonBiologicalScans: purged \(result.deletedRecordCount, privacy: .public) records and \(result.localMediaPaths.count, privacy: .public) local media paths"
            )
        } catch {
            MerianLog.data.error("purgeExpiredNonBiologicalScans: cleanup failed: \(error, privacy: .private)")
        }
    }

    func syncBiologicalRescue(scanId: String) async {
        struct BiologicalOverridePayload: Encodable, Sendable {
            let is_biological_subject: Bool
            let ecology_type: String
        }

        do {
            try await SupabaseManager.shared.client
                .from("scans")
                .update(BiologicalOverridePayload(is_biological_subject: true, ecology_type: "unknown"))
                .eq("id", value: scanId)
                .execute()
        } catch {
            MerianLog.network.error("Remote markAsBiological sync failed: \(error, privacy: .private)")
        }
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
        ExploreShareStateStore.setSharedPostId(nil, for: record.id)

        // Collect image paths before deleting the record.
        var imagesToErase: [String] = []
        if let jsonStr = record.capturedMediaJSON,
           let jsonData = jsonStr.data(using: .utf8),
           let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) {
            imagesToErase.append(contentsOf: items.compactMap {
                guard case .image(let reference) = $0 else { return nil }
                return reference.serializedPath
            })
        }

        // 1. Tombstone any in-flight upload.
        offlineQueue.softDeleteQueuedScan(scanId: record.id)

        // 2. Queue cloud deletion task + remove SwiftData record atomically.
        do {
            try modelContext.ensurePendingCloudDeletionTask(scanId: record.id)
            modelContext.delete(record)
            try modelContext.save()
        } catch {
            modelContext.rollback()
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
        
        ScanLibraryEvents.postLibraryDidUpdate()
    }

    /// Completely eradicates all local database caches and queued data. Use only for full account deletion or hard resets.
    func purgeAllData(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: LocalScanRecord.self)
            try modelContext.delete(model: ScanCollection.self)
            try modelContext.delete(model: OfflineQueuedScan.self)
            try modelContext.delete(model: PendingCloudDeletionTask.self)
            try modelContext.save()
            ExploreShareStateStore.clearAll()
            ScanLibraryEvents.postLibraryDidUpdate()
            MerianLog.data.debug("✅ Successfully purged all SwiftData records natively.")
        } catch {
            modelContext.rollback()
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
    let hazard_type: String?
    let common_names: [String: String?]?
    let wikipedia_overview: String?
    let iucn_red_list_status: String?
    let habitat_description: String?
    let group_tags: [String]?
}

struct HistoricalScanResponse: Decodable, Sendable {
    let id: String
    let created_at: String?
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
    let ai_reasoning: String?
    let estimated_size_cm: Double?
    let life_stage: String?
    let reproductive_condition: String?
    let sex: String?
    let sex_confidence: Double?
    let sex_evidence: String?
    let individual_count: Int?
    let ecological_interactions: [String]?
    let inference_tier: String?
    let custom_tags: [String]?
    let candidates: [CloudIdentificationCandidate]?
    let user_identification_override: String?
    let user_confirmed_identification: Bool?
    let image_quality_score: Int?
    let species_dictionary: CloudSpeciesDictionary?
}

struct CloudIdentificationCandidate: Decodable, Sendable {
    let scientific_name: String
    let common_name: String?
    let confidence_score: Double
    let distinguishing_feature: String?
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

    // MARK: - Paged API (primary entry points from syncHistoricalScansDown)

    /// Reconciles a single page of remote scan responses against local state.
    ///
    /// Computes the existing-ID set fresh each call via a chunked `FetchDescriptor` with
    /// `propertiesToFetch = [\.id]` (ID-only column projection). Delegates to
    /// `updateExistingScans` for records already present locally and `ingestScans` for new ones.
    ///
    /// - Returns: The number of new `LocalScanRecord` rows inserted from this page.
    @discardableResult
    func reconcileScanPage(responses: [HistoricalScanResponse]) -> Int {
        let responseIds = responses.map { $0.id }
        var existingIds = Set<String>()
        
        let chunkSize = 500
        for chunkStart in stride(from: 0, to: responseIds.count, by: chunkSize) {
            let chunk = Array(responseIds[chunkStart..<min(chunkStart + chunkSize, responseIds.count)])
            // propertiesToFetch: [\.id] loads only the id column — no full record fault.
            // fetchIdentifiers + model(for:) previously faulted complete LocalScanRecord objects
            // just to extract the id string, loading all columns for every existing record.
            var desc = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { chunk.contains($0.id) })
            desc.propertiesToFetch = [\.id]
            let records = (try? modelContext.fetch(desc)) ?? []
            for record in records {
                existingIds.insert(record.id)
            }
        }

        updateExistingScans(responses: responses, existingIds: existingIds)

        let missingScans = responses.filter { !existingIds.contains($0.id) }
        if !missingScans.isEmpty {
            ingestScans(missingScans: missingScans)
        }

        return missingScans.count
    }

    /// Reconciles the full remote collection list against local state
    func syncCollectionsDown(remoteCollections: [CloudCollectionResponse]) {
        syncCollections(remoteCollections: remoteCollections)
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
        let newCount = reconcileScanPage(responses: responses)
        syncCollectionsDown(remoteCollections: collections)
        return newCount
    }

    // MARK: - Private Helpers

    private func updateExistingScans(responses: [HistoricalScanResponse], existingIds: Set<String>) {
        // Only fetch records that are both local and in the remote response.
        let responseIds = responses.map { $0.id }.filter { existingIds.contains($0) }
        guard !responseIds.isEmpty else { return }

        // Build a per-chunk response lookup so each stride can resolve its own slice
        // without scanning the full responses array.
        let responseLookup: [String: HistoricalScanResponse] = Dictionary(
            uniqueKeysWithValues: responses.compactMap { existingIds.contains($0.id) ? ($0.id, $0) : nil }
        )

        // Hoist encoder above both the chunk loop and the per-record loop.
        // JSONEncoder carries Obj-C init overhead and key-strategy setup; allocating one
        // per record across an entire sync page adds measurable GC pressure on the actor thread.
        let encoder = JSONEncoder()

        // Process, modify, save, and release each chunk of 500 in strict isolation.
        // Accumulating all faulted LocalScanRecord objects before starting mutations
        // (the previous pattern) held the entire page worth of heavy ORM objects in RAM
        // simultaneously. Scoping per-chunk keeps peak heap flat at ≤500 objects regardless
        // of page size, page count, or user library depth.
        let chunkSize = 500
        for chunkStart in stride(from: 0, to: responseIds.count, by: chunkSize) {
            let chunkIds = Array(responseIds[chunkStart..<min(chunkStart + chunkSize, responseIds.count)])

            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { chunkIds.contains($0.id) })
            let chunkRecords = (try? modelContext.fetch(descriptor)) ?? []
            let chunkLookup = Dictionary(uniqueKeysWithValues: chunkRecords.map { ($0.id, $0) })

            var chunkDidUpdate = false
            for id in chunkIds {
                guard let existing = chunkLookup[id], let res = responseLookup[id] else { continue }

                let rawR2Image = res.image_storage_urls?.first
                let additionalUrls = res.image_storage_urls.flatMap { urls in urls.count > 1 ? Array(urls.dropFirst()) : nil }
                let dictRefImage = res.species_dictionary?.reference_image_url

                var paths: [String] = []
                if let jsonStr = existing.capturedMediaJSON,
                   let jsonData = jsonStr.data(using: .utf8),
                   let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) {
                    paths = items.compactMap {
                        guard case .image(let reference) = $0 else { return nil }
                        return reference.serializedPath
                    }
                }
                var newItems: [SerializedMediaItem] = []
                if let rawR2Image { newItems.append(.image(.remoteURL(rawR2Image))) }
                if let additionalUrls { newItems.append(contentsOf: additionalUrls.map { .image(.remoteURL($0)) }) }
                if !newItems.isEmpty {
                    let hasRemoteMedia = paths.contains { $0.starts(with: "http://") || $0.starts(with: "https://") }
                    let onlyLocalOrMissingMedia = paths.isEmpty || !hasRemoteMedia
                    if onlyLocalOrMissingMedia {
                        existing.replaceCapturedMedia(with: newItems)
                        chunkDidUpdate = true
                    }
                }
                if existing.referenceImageUrl != dictRefImage {
                    existing.referenceImageUrl = dictRefImage; chunkDidUpdate = true
                }
                if let newLoc = res.semantic_location, existing.locationName != newLoc {
                    existing.locationName = newLoc; chunkDidUpdate = true
                }
                if existing.gpsLatitude == nil, let remoteLat = res.gps_lat_exact, let remoteLon = res.gps_long_exact {
                    existing.gpsLatitude = remoteLat
                    existing.gpsLongitude = remoteLon
                    existing.gpsElevation = res.gps_elevation
                    chunkDidUpdate = true
                }
                if let remoteCreatedAt = parseHistoricalDate(res.created_at),
                   existing.timestamp != remoteCreatedAt {
                    existing.timestamp = remoteCreatedAt
                    chunkDidUpdate = true
                }
                if let remoteCaptureDate = parseHistoricalDate(res.timestamp),
                   existing.captureDate != remoteCaptureDate {
                    existing.captureDate = remoteCaptureDate
                    chunkDidUpdate = true
                }
                if let newReasoning = res.ai_reasoning, existing.aiReasoning != newReasoning {
                    existing.aiReasoning = newReasoning; chunkDidUpdate = true
                }
                let dict = res.species_dictionary
                if let newHabitat = dict?.habitat_description, existing.habitatDescription != newHabitat {
                    existing.habitatDescription = newHabitat; chunkDidUpdate = true
                }
                if let newSize = res.estimated_size_cm, existing.estimatedSizeCm != newSize {
                    existing.estimatedSizeCm = newSize; chunkDidUpdate = true
                }
                if let newKingdom = dict?.kingdom, existing.taxonomyKingdom != newKingdom {
                    existing.taxonomyKingdom = newKingdom; chunkDidUpdate = true
                }
                if let newPhylum = dict?.phylum, existing.taxonomyPhylum != newPhylum {
                    existing.taxonomyPhylum = newPhylum; chunkDidUpdate = true
                }
                if let newClass = dict?.`class`, existing.taxonomyClass != newClass {
                    existing.taxonomyClass = newClass; chunkDidUpdate = true
                }
                if let newOrder = dict?.order, existing.taxonomyOrder != newOrder {
                    existing.taxonomyOrder = newOrder; chunkDidUpdate = true
                }
                if let newFamily = dict?.family, existing.taxonomyFamily != newFamily {
                    existing.taxonomyFamily = newFamily; chunkDidUpdate = true
                }
                if let newGenus = dict?.genus, existing.taxonomyGenus != newGenus {
                    existing.taxonomyGenus = newGenus; chunkDidUpdate = true
                }
                if let newLife = res.life_stage, existing.lifeStage != newLife {
                    existing.lifeStage = newLife; chunkDidUpdate = true
                }
                if let newRepro = res.reproductive_condition, existing.reproductiveCondition != newRepro {
                    existing.reproductiveCondition = newRepro; chunkDidUpdate = true
                }
                if let newSex = res.sex, existing.sex != newSex {
                    existing.sex = newSex; chunkDidUpdate = true
                }
                if let newSexConfidence = res.sex_confidence, existing.sexConfidence != newSexConfidence {
                    existing.sexConfidence = newSexConfidence; chunkDidUpdate = true
                }
                if let newSexEvidence = res.sex_evidence, existing.sexEvidence != newSexEvidence {
                    existing.sexEvidence = newSexEvidence; chunkDidUpdate = true
                }
                if let newIndiv = res.individual_count, existing.individualCount != newIndiv {
                    existing.individualCount = newIndiv; chunkDidUpdate = true
                }
                if let newInter = res.ecological_interactions, existing.ecologicalInteractions != newInter {
                    existing.ecologicalInteractions = newInter; chunkDidUpdate = true
                }
                if let newTier = res.inference_tier, existing.inferenceTier != newTier {
                    existing.inferenceTier = newTier; chunkDidUpdate = true
                }
                if let newTags = res.custom_tags, existing.customTags != newTags {
                    existing.customTags = newTags; chunkDidUpdate = true
                }
                if existing.candidatesData == nil, let cloudCandidates = res.candidates, !cloudCandidates.isEmpty {
                    existing.candidatesData = try? encoder.encode(cloudCandidates.map {
                        IdentificationCandidate(scientificName: $0.scientific_name, commonName: $0.common_name, confidenceScore: $0.confidence_score, distinguishingFeature: $0.distinguishing_feature)
                    })
                    chunkDidUpdate = true
                }
                if let cloudOverride = res.user_identification_override,
                   existing.userIdentificationOverride != cloudOverride {
                    existing.userIdentificationOverride = cloudOverride
                    chunkDidUpdate = true
                }
                if res.user_confirmed_identification == true, !existing.userConfirmedIdentification {
                    existing.userConfirmedIdentification = true
                    chunkDidUpdate = true
                }
                if existing.imageQualityScore == nil, let newScore = res.image_quality_score {
                    existing.imageQualityScore = newScore
                    chunkDidUpdate = true
                }
            }

            // Save and drop all chunk object references so ARC can immediately reclaim
            // the faulted LocalScanRecord heap before the next stride loads its 500 objects.
            if chunkDidUpdate {
                _ = saveHistoricalContext("updateExistingScans chunk")
            }
        }
    }

    private func ingestScans(missingScans: [HistoricalScanResponse]) {
        let checkpointInterval = MerianConfig.ingestCheckpointInterval
        // Hoist encoder outside the loop — JSONEncoder allocation is non-trivial (Obj-C init,
        // key strategy setup, etc.) and creating one per scan across thousands of records adds
        // measurable GC pressure on the @ModelActor thread.
        let encoder = JSONEncoder()
        for (index, scan) in missingScans.enumerated() {
            if Task.isCancelled { break }
            let exifDate = parseHistoricalDate(scan.timestamp)
            guard let parsedDate = exifDate else {
                MerianLog.data.error("ingestScans: unparseable timestamp '\(scan.timestamp ?? "nil")' for scan \(scan.id) — skipping")
                continue
            }
            let discoveryDate = parseHistoricalDate(scan.created_at) ?? parsedDate

            let dict = scan.species_dictionary
            let sciName = dict?.scientific_name ?? "Unknown Subject"
            let cName: String = {
                guard let names = dict?.common_names else { return sciName }
                return names["en"].flatMap { $0 } ?? names.compactMap { $0.value }.first ?? sciName
            }()
            let wikiExtract = dict?.wikipedia_overview

            let rawR2Image = scan.image_storage_urls?.first
            let additionalUrls = scan.image_storage_urls.flatMap { urls in urls.count > 1 ? Array(urls.dropFirst()) : nil }
            let semanticTags: [String] = [cName, sciName] + (scan.colors ?? []) + (dict?.group_tags ?? [])
            let candidatesData: Data? = scan.candidates.flatMap { entries in
                try? encoder.encode(entries.map {
                    IdentificationCandidate(scientificName: $0.scientific_name, commonName: $0.common_name, confidenceScore: $0.confidence_score, distinguishingFeature: $0.distinguishing_feature)
                })
            }

            let record = LocalScanRecord(
                id: scan.id,
                speciesId: UUID().uuidString,
                scientificName: sciName,
                commonName: cName,
                timestamp: discoveryDate,
                captureDate: parsedDate,
                semanticTags: semanticTags,
                hazardType: dict?.hazard_type ?? "none",
                isBiological: true,
                isLiveCapture: scan.is_live_capture ?? true,
                isInvasive: scan.is_invasive ?? false,
                ecologyType: scan.ecology_type ?? "unknown",
                wikipediaUrl: dict?.wikipedia_url,
                wikipediaOverview: wikiExtract,
                referenceImageUrl: dict?.reference_image_url,
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
                candidatesData: candidatesData,
                iucnRedListStatus: dict?.iucn_red_list_status,
                gpsLatitude: scan.gps_lat_exact,
                gpsLongitude: scan.gps_long_exact,
                gpsElevation: scan.gps_elevation,
                aiReasoning: scan.ai_reasoning,
                habitatDescription: dict?.habitat_description,
                estimatedSizeCm: scan.estimated_size_cm,
                lifeStage: scan.life_stage,
                reproductiveCondition: scan.reproductive_condition,
                sex: scan.sex,
                sexConfidence: scan.sex_confidence,
                sexEvidence: scan.sex_evidence,
                individualCount: scan.individual_count,
                ecologicalInteractions: scan.ecological_interactions,
                inferenceTier: scan.inference_tier ?? "flash",
                customTags: scan.custom_tags ?? [],
                hasBeenViewed: true,
                userIdentificationOverride: scan.user_identification_override,
                userConfirmedIdentification: scan.user_confirmed_identification ?? false,
                imageQualityScore: scan.image_quality_score
            )
            
            var newItems: [SerializedMediaItem] = []
            if let primary = rawR2Image { newItems.append(.image(.remoteURL(primary))) }
            if let urls = additionalUrls { newItems.append(contentsOf: urls.map { .image(.remoteURL($0)) }) }
            // Note: Cloud dictionary might have audio file paths or observation contexts depending on the API mapping,
            // but the original code did not pass them here, so we only handle images.
            record.replaceCapturedMedia(with: newItems)

            modelContext.insert(record)

            if (index + 1).isMultiple(of: checkpointInterval) {
                _ = saveHistoricalContext("ingestScans checkpoint at index \(index)")
            }
        }

        _ = saveHistoricalContext("ingestScans final")
    }

    private func syncCollections(remoteCollections: [CloudCollectionResponse]) {
        // fetchLimit: 500 is a defensive ceiling — an unbounded full-table scan can fault orphaned
        // or schema-migrated collection records into memory before sync begins.
        var collectionsDescriptor = FetchDescriptor<ScanCollection>()
        collectionsDescriptor.fetchLimit = 500
        let existingCollections = (try? modelContext.fetch(collectionsDescriptor)) ?? []
        var existingLookup = Dictionary(existingCollections.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        
        // Fetch only the local scan records referenced by the incoming collections.
        let referencedScanIds = remoteCollections.compactMap { $0.collection_scans }.flatMap { $0 }.map { $0.scan_id }
        let allScansDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { referencedScanIds.contains($0.id) })
        let localScans: [LocalScanRecord] = referencedScanIds.isEmpty ? [] : {
            return (try? modelContext.fetch(allScansDescriptor)) ?? []
        }()
        let localScansLookup = Dictionary(localScans.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // Read membership from the `LocalScanRecord.collections` side in bounded batches to
        // avoid faulting every `ScanCollection.scans` array or the entire scan library at once.
        let relevantCollectionIDs = Set(remoteCollections.map { $0.id.lowercased() })
        var collectionMembersByID = fetchCollectionMembersByID(
            relevantCollectionIDs: relevantCollectionIDs,
            modelContext: modelContext
        )

        for remote in remoteCollections {
            if Task.isCancelled { break }
            let col: ScanCollection
            let remoteIdLower = remote.id.lowercased()
            if let existing = existingLookup[remoteIdLower] {
                col = existing
                existingLookup.removeValue(forKey: remoteIdLower)
                
                // --- INBOUND SHIELD ---
                // If a collection is marked as deleted locally, aggressively ignore any remote
                // representations of it. This prevents an obsolete or delayed remote state
                // from "resurrecting" the collection locally or wiping its tombstone status.
                if existing.isDeleted {
                    continue
                }
            } else {
                col = ScanCollection(name: remote.name)
                col.id = remote.id
                if let parsedDate = DateUtilities.iso8601FractionalFormatter.date(from: remote.created_at) ?? DateUtilities.iso8601Formatter.date(from: remote.created_at) {
                    col.createdAt = parsedDate
                }
                modelContext.insert(col)
            }

            col.name = remote.name
            
            let remoteScanIds = Set(remote.collection_scans?.map { $0.scan_id } ?? [])
            
            // Remove local scans that are NOT in the remote list,
            // EXCEPT for those that are still pending upload (offline captures).
            // A reliable heuristic: if the image path is local (doesn't start with http/https), it hasn't synced yet.
            let currentScans = collectionMembersByID[remoteIdLower] ?? []
            for scan in currentScans where !remoteScanIds.contains(scan.id) {
                let isSynced = scan.coverImagePath?.starts(with: "http") == true || scan.coverImagePath?.starts(with: "https") == true || scan.coverImagePath == nil
                if isSynced {
                    // Drive the removal from the inverse side via reassignment — in-place
                    // mutation on optional SwiftData arrays can fail to notify the context.
                    var updatedCollections = scan.collections ?? []
                    let originalCount = updatedCollections.count
                    updatedCollections.removeAll(where: { $0.id == col.id })
                    if updatedCollections.count != originalCount {
                        scan.collections = updatedCollections
                    }
                }
            }
            
            if let scans = remote.collection_scans {
                for scanMapping in scans {
                    if let localScan = localScansLookup[scanMapping.scan_id.lowercased()] {
                        // Drive the relationship from the inverse side to avoid the static type
                        // mismatch between ScanCollection.scans ([V12.LocalScanRecord]) and
                        // the current-schema LocalScanRecord (V13). SwiftData propagates the
                        // inverse automatically.
                        var updatedCollections = localScan.collections ?? []
                        if !updatedCollections.contains(where: { $0.id == col.id }) {
                            updatedCollections.append(col)
                            localScan.collections = updatedCollections
                            collectionMembersByID[remoteIdLower, default: []].append(localScan)
                        }
                    }
                }
            }
        }

        for (_, obsolete) in existingLookup where obsolete.name != "Favorites" {
            modelContext.delete(obsolete)
        }

        _ = saveHistoricalContext("syncCollections inbound reconciliation")
    }

    @discardableResult
    private func saveHistoricalContext(_ logContext: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error("\(logContext, privacy: .public): save failed; rolled back context: \(error, privacy: .private)")
            return false
        }
    }

    private func parseHistoricalDate(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        if timestamp.contains(".") {
            return DateUtilities.iso8601FractionalFormatter.date(from: timestamp)
                ?? DateUtilities.iso8601Formatter.date(from: timestamp)
        }
        return DateUtilities.iso8601Formatter.date(from: timestamp)
            ?? DateUtilities.iso8601FractionalFormatter.date(from: timestamp)
    }

    private func fetchCollectionMembersByID(
        relevantCollectionIDs: Set<String>,
        modelContext: ModelContext
    ) -> [String: [LocalScanRecord]] {
        guard !relevantCollectionIDs.isEmpty else { return [:] }

        let batchSize = 200
        var offset = 0
        var collectionMembersByID: [String: [LocalScanRecord]] = [:]

        while true {
            var descriptor = FetchDescriptor<LocalScanRecord>(
                sortBy: [SortDescriptor(\.timestamp)]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            descriptor.relationshipKeyPathsForPrefetching = [\.collections]

            guard let batch = try? modelContext.fetch(descriptor), !batch.isEmpty else {
                break
            }

            for scan in batch {
                for attachedCollection in scan.collections ?? [] {
                    let attachedID = attachedCollection.id.lowercased()
                    guard relevantCollectionIDs.contains(attachedID) else { continue }
                    collectionMembersByID[attachedID, default: []].append(scan)
                }
            }

            offset += batch.count
            if batch.count < batchSize { break }
        }

        return collectionMembersByID
    }
}
