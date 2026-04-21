import CoreLocation
import Foundation
import os
import Supabase
import SwiftData

// MARK: - Background Database Actor

/// Swift 6-safe actor that performs all SwiftData reads and writes off the main thread.
///
/// Conforms to `@ModelActor`, which provides an isolated `modelContext` bound to this actor.
/// All methods are safe to call from `Task { }` or `BackgroundTaskWrapper.execute` contexts.
///
/// Shared data transfer objects (`ExtractedScanData`, `OfflineScanProcessingResult`,
/// `PendingScanPayload`, `ScanUploadItem`) live in `OfflineSyncTypes.swift`.
@ModelActor
actor BackgroundDatabaseActor {

    // MARK: - Pending Scan Fetching

    /// Returns up to `limit` `.pending` (state 0) `OfflineQueuedScan` records sorted oldest-first.
    ///
    /// Scans in `.uploading`, `.staged`, `.inferencing`, or `.failed` states are excluded —
    /// they are either already in flight or terminal, and handled by separate recovery paths.
    func fetchPendingScans(limit: Int) -> [PendingScanPayload] {
        let pendingRaw = ScanQueueState.pending.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == pendingRaw }
        )
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        descriptor.fetchLimit = limit

        let pending: [OfflineQueuedScan]
        do {
            pending = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.error("fetchPendingScans: fetch failed: \(error, privacy: .private)")
            return []
        }
        return pending.map { PendingScanPayload(id: $0.id, localImagePaths: $0.localImagePaths) }
    }

    // MARK: - State Transitions

    /// Atomically transitions a scan from `.staged` to `.inferencing`.
    ///
    /// Returns `true` if the claim succeeded (scan was in `.staged` state and is now `.inferencing`).
    /// Returns `false` if the scan was already `.inferencing` or not found — caller must skip.
    ///
    /// This is the distributed lock that prevents two concurrent inference pipelines
    /// from running for the same scan: only one actor can win the `.staged → .inferencing`
    /// transition because `BackgroundDatabaseActor` serializes writes through its executor.
    func tryClaimForInference(scanId: String) -> Bool {
        let stagedRaw     = ScanQueueState.staged.rawValue
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let scan = (try? modelContext.fetch(descriptor))?.first else { return false }
        guard scan.scanStateRaw == stagedRaw else { return false }
        scan.scanStateRaw = inferencingRaw
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("tryClaimForInference: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
        return true
    }

    /// Transitions a scan back to `.staged` from `.inferencing` and persists.
    ///
    /// **Only valid for the transient-error retry path** (`handleInferenceRetry` transient catch).
    /// Guarded to `.inferencing` as source state so a concurrent `softDeleteQueuedScan` on
    /// the MainActor that already tombstoned the scan to `.failed` cannot be overwritten —
    /// the last-writer-wins nature of two separate `ModelContext`s would otherwise resurrect
    /// a tombstoned scan back into the inference replay queue.
    func transitionScanToStaged(id scanId: String) {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        let stagedRaw      = ScanQueueState.staged.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let scan = (try? modelContext.fetch(descriptor))?.first else { return }
        // Only retreat from .inferencing — do not overwrite a concurrent tombstone (.failed).
        guard scan.scanStateRaw == inferencingRaw else { return }
        scan.scanStateRaw = stagedRaw
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("transitionScanToStaged: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }

    /// Persists the confirmed R2 object keys on the scan record and transitions it to `.staged`.
    ///
    /// Called once the last image upload for a scan is confirmed (HTTP 200).
    /// Storing keys here eliminates auth-dependent key reconstruction at inference time.
    ///
    /// Guards: only transitions from `.uploading`. If the scan was tombstoned (`.failed`) while
    /// a subset of its images were still in transit — e.g., one source file was missing —
    /// this prevents the completed uploads from resurrecting the scan into the inference pipeline
    /// with partial image data.
    func markScanAsStaged(scanId: String, r2Keys: [String]) {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let scan = (try? modelContext.fetch(descriptor))?.first else { return }
        // Only advance from .uploading — do not resurrect tombstoned (.failed) scans.
        guard scan.scanStateRaw == ScanQueueState.uploading.rawValue else { return }
        scan.stagedR2Keys  = r2Keys
        scan.scanStateRaw  = ScanQueueState.staged.rawValue
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("markScanAsStaged: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }

    /// Marks scans in `.uploading` state that have no active URLSession task as `.pending`,
    /// so `syncPendingScans` re-dispatches them on the next sync cycle.
    ///
    /// Returns `true` if at least one orphan was reset, `false` if nothing changed.
    /// Callers that need to react to an actual state change (e.g. triggering a new sync)
    /// can use the return value; all other call sites may discard it.
    ///
    /// Called once per process lifetime on first connectivity restore. Safe because no
    /// URLSession tasks are dispatched during the window between process start and this call.
    @discardableResult
    func reconcileOrphanedUploadingScans(activeScanIds: Set<String>) -> Bool {
        let uploadingRaw = ScanQueueState.uploading.rawValue
        let pendingRaw   = ScanQueueState.pending.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == uploadingRaw }
        )
        let scans: [OfflineQueuedScan]
        do {
            scans = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.debug("reconcileOrphanedUploadingScans: fetch failed: \(error, privacy: .private)")
            return false
        }
        var changed = false
        for scan in scans where !activeScanIds.contains(scan.id) {
            scan.scanStateRaw = pendingRaw
            changed = true
        }
        if changed {
            do {
                try modelContext.save()
            } catch {
                MerianLog.data.error("reconcileOrphanedUploadingScans: save failed: \(error, privacy: .private)")
            }
        }
        return changed
    }

    /// Resets `.inferencing` scans that have no active background URLSession inference task
    /// back to `.staged` so `replayInferenceForUploadedScans` can re-claim them.
    ///
    /// Replaces `resetOrphanedInferencingScans` with a cross-reference against the live
    /// URLSession task list so that background download tasks still owned by the OS are
    /// not blindly reset — which would cause a duplicate inference dispatch on relaunch.
    func reconcileOrphanedInferencingScans(activeInferenceScanIds: Set<String>) {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        let stagedRaw      = ScanQueueState.staged.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == inferencingRaw }
        )
        let scans: [OfflineQueuedScan]
        do {
            scans = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.debug("reconcileOrphanedInferencingScans: fetch failed: \(error, privacy: .private)")
            return
        }
        var changed = false
        for scan in scans where !activeInferenceScanIds.contains(scan.id) {
            scan.scanStateRaw = stagedRaw
            changed = true
        }
        if changed {
            do {
                try modelContext.save()
                MerianLog.data.debug("reconcileOrphanedInferencingScans: reset orphaned .inferencing scans to .staged")
            } catch {
                MerianLog.data.error("reconcileOrphanedInferencingScans: save failed: \(error, privacy: .private)")
            }
        }
    }

    /// Persists weather backfill data onto the queued scan record before the inference
    /// request is dispatched as a background download task.
    ///
    /// Called after WeatherKit resolves so the delegate can read hydrated telemetry from
    /// SwiftData on result delivery — even if the app was suspended between dispatch and receipt.
    func updateScanTelemetry(
        scanId: String,
        weatherCondition: String?,
        weatherTemperatureF: Double?,
        locationName: String?
    ) {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let scan = (try? modelContext.fetch(descriptor))?.first else { return }
        if let wc = weatherCondition { scan.weatherCondition = wc }
        if let wt = weatherTemperatureF { scan.weatherTemperatureF = wt }
        if scan.locationName == nil, let ln = locationName { scan.locationName = ln }
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("updateScanTelemetry: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }

    /// Transitions scans to `.uploading` state and persists, preventing `syncPendingScans`
    /// from re-dispatching upload tasks for these scans after an app restart.
    func markScansAsUploading(scanIds: [String]) {
        guard !scanIds.isEmpty else { return }
        let idSet = Set(scanIds)
        let pendingRaw   = ScanQueueState.pending.rawValue
        let uploadingRaw = ScanQueueState.uploading.rawValue
        // Predicate-filter to .pending only — avoids loading tombstoned (.failed) and in-flight
        // records into memory when the queue has accumulated a large backlog of failed scans.
        // #Predicate cannot express "id IN set", so ID-set filtering still happens in memory,
        // but the row count is now bounded by the number of pending scans (typically tiny).
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == pendingRaw }
        )
        let scans: [OfflineQueuedScan]
        do {
            scans = try modelContext.fetch(descriptor).filter { idSet.contains($0.id) }
        } catch {
            MerianLog.data.debug("markScansAsUploading: fetch failed: \(error, privacy: .private)")
            return
        }
        // All fetched scans are already .pending (predicate-guaranteed), so no per-scan state
        // check is needed here. The predicate itself acts as the source-state guard.
        for scan in scans { scan.scanStateRaw = uploadingRaw }
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("markScansAsUploading: save failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Offline Scan Processing

    /// Decodes edge inference results and persists a `LocalScanRecord` (when confidence > 0).
    ///
    /// The `OfflineQueuedScan` is intentionally **not** deleted here — that is delegated to
    /// the main actor's `flushOfflineQueuedScan` so the main `ModelContext` always has a real
    /// pending change on its save, which is the only reliable `@Query` re-evaluation trigger
    /// in a presented sheet (SwiftData platform limitation).
    func processAndCleanupOfflineScan(
        resultData: Data,
        originalImagePaths: [String],
        scanId: String,
        originalTimestamp: Date,
        telemetry: CaptureTelemetry? = nil,
        observationContextsJSON: [String]? = nil
    ) -> OfflineScanProcessingResult {
        var inferenceFailed = true
        var resolvedSpeciesName: String?
        var finalIsNewDiscovery = false
        var resultingScanId: String?
        var resultSpeciesData: SpeciesData?

        // --- Step 1: Decode Edge Response ---
        
        let parsedWrapper: EdgeResponseWrapper?
        do {
            parsedWrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: resultData)
        } catch {
            MerianLog.data.debug("processAndCleanupOfflineScan: JSON decode failed: \(error, privacy: .private)")
            parsedWrapper = nil
        }

        // --- Step 2: Map Data and Resolve Identifiers ---
        
        if let parsedWrapper {
            var mappedData = SpeciesData(
                fromEdgeResponse: parsedWrapper.data,
                locationName: telemetry?.locationName,
                weatherCondition: telemetry?.weatherCondition,
                weatherTemperatureF: telemetry?.weatherTemperatureF,
                gpsElevation: telemetry?.gpsElevation,
                gpsLatitude: telemetry?.gpsLatitude,
                gpsLongitude: telemetry?.gpsLongitude
            )
            mappedData.zoomFactor = telemetry?.zoomFactor.map { Double($0) }

            if mappedData.confidenceScore > 0.0 {
                inferenceFailed = false
                resolvedSpeciesName = mappedData.commonName

                let (activeSpeciesId, isNew) = resolveSpeciesIdAndDiscoveryStatus(for: mappedData.scientificName)
                
                if isNew {
                    mappedData.isNewDiscovery = true
                    finalIsNewDiscovery = true
                }

                // Capture mappedData (with isNewDiscovery set) to hydrate the live InferenceEngine.
                resultSpeciesData = mappedData

                let recordId = mappedData.scanId ?? scanId
                
                // --- Step 3: Atomic Record Insertion ---
                insertLocalScanRecordIfMissing(
                    mappedData: mappedData,
                    recordId: recordId,
                    activeSpeciesId: activeSpeciesId,
                    originalTimestamp: originalTimestamp,
                    originalImagePaths: originalImagePaths,
                    observationContextsJSON: observationContextsJSON
                )
                
                resultingScanId = recordId
            }
        }

        // --- Step 4: Commit LocalScanRecord ---
        //
        // The `OfflineQueuedScan` is intentionally NOT deleted here. Delegation to the main
        // actor's `flushOfflineQueuedScan` ensures the main `ModelContext` always has a real
        // pending deletion when it saves. SwiftData's `@Query` in a presented sheet only
        // re-evaluates reliably when the *main* context performs a save with actual pending
        // changes; background-context saves propagate via `NSPersistentStoreRemoteChangeNotification`
        // but do not reliably trigger `@Query` in open sheets (SwiftData platform limitation).
        let commitSuccess: Bool
        do {
            try modelContext.save()
            commitSuccess = true
        } catch {
            MerianLog.data.error("processAndCleanupOfflineScan: save failed — rolling back.")
            modelContext.rollback()
            resolvedSpeciesName = nil
            resultingScanId = nil
            resultSpeciesData = nil
            commitSuccess = false
        }

        if commitSuccess && inferenceFailed {
            // HTTP 200 response but confidence == 0: no LocalScanRecord was inserted.
            // The OfflineQueuedScan cleanup is still delegated to the main actor.
            // Delete source image files here since they will never be referenced by a record.
            Task { await FileIOActor.shared.deleteImages(at: originalImagePaths) }
        }

        return OfflineScanProcessingResult(
            resolvedSpeciesName: resolvedSpeciesName,
            isNewDiscovery: finalIsNewDiscovery,
            finalScanId: resultingScanId,
            speciesData: resultSpeciesData,
            wasCleaned: commitSuccess
        )
    }

    // MARK: - Offline Queue Processing Helpers

    /// Determines the correct speciesId and whether this is a new discovery for the user.
    private func resolveSpeciesIdAndDiscoveryStatus(for targetName: String) -> (speciesId: String, isNewDiscovery: Bool) {
        var fetchDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate<LocalScanRecord> { $0.scientificName == targetName }
        )
        fetchDescriptor.fetchLimit = 1
        fetchDescriptor.propertiesToFetch = [\.speciesId]
        
        let existingRecords: [LocalScanRecord]
        do {
            existingRecords = try modelContext.fetch(fetchDescriptor)
        } catch {
            MerianLog.data.debug("resolveSpeciesIdAndDiscoveryStatus: lookup failed: \(error, privacy: .private)")
            existingRecords = []
        }

        let activeSpeciesId = existingRecords.first?.speciesId ?? UUID().uuidString
        let isNewDiscovery = existingRecords.isEmpty
        return (activeSpeciesId, isNewDiscovery)
    }

    /// Idempotently inserts a new LocalScanRecord.
    private func insertLocalScanRecordIfMissing(
        mappedData: SpeciesData,
        recordId: String,
        activeSpeciesId: String,
        originalTimestamp: Date,
        originalImagePaths: [String],
        observationContextsJSON: [String]? = nil
    ) {
        var existingIdDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate<LocalScanRecord> { $0.id == recordId }
        )
        existingIdDescriptor.fetchLimit = 1
        let alreadyExists = (try? modelContext.fetch(existingIdDescriptor))?.isEmpty == false

        if !alreadyExists {
            let record = LocalScanRecord(
                id: recordId,
                speciesId: activeSpeciesId,
                scientificName: mappedData.scientificName,
                commonName: mappedData.commonName,
                timestamp: Date(),
                captureDate: originalTimestamp,
                localImagePath: originalImagePaths.first,
                semanticTags: [mappedData.commonName, mappedData.scientificName] + (mappedData.colors ?? []) + (mappedData.groupTags ?? []),
                hazardType: mappedData.insightData.hazardType,
                isBiological: mappedData.isBiological,
                isLiveCapture: mappedData.isLiveCapture,
                isInvasive: mappedData.isInvasive,
                ecologyType: mappedData.ecologyType,
                wikipediaUrl: mappedData.wikipediaUrl,
                referenceImageUrl: mappedData.referenceImageUrl,
                additionalImagePaths: originalImagePaths.count > 1 ? Array(originalImagePaths.dropFirst()) : nil,
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
                similarSpecies: mappedData.similarSpecies?.lookalikes,
                candidatesData: mappedData.candidates.flatMap { try? JSONEncoder().encode($0) },
                iucnRedListStatus: mappedData.iucnRedListStatus,
                gpsLatitude: mappedData.gpsLatitude,
                gpsLongitude: mappedData.gpsLongitude,
                gpsElevation: mappedData.gpsElevation,
                zoomFactor: mappedData.zoomFactor,
                aiReasoning: mappedData.aiReasoning,
                habitatDescription: mappedData.habitatDescription,
                gbifTaxonKey: mappedData.gbifTaxonKey,
                estimatedSizeCm: mappedData.estimatedSizeCm,
                lifeStage: mappedData.lifeStage,
                reproductiveCondition: mappedData.reproductiveCondition,
                individualCount: mappedData.individualCount,
                ecologicalInteractions: mappedData.ecologicalInteractions,
                inferenceTier: mappedData.inferenceTier,
                imageQualityScore: mappedData.imageQualityScore,
                alternativeCommonNames: mappedData.alternativeCommonNames,
                observationContextsJSON: observationContextsJSON,
                audioFilePaths: mappedData.audioFilePaths
            )
            modelContext.insert(record)
        }
    }

    // MARK: - Live Scan Recording

    /// Persists a real-time scan result to SwiftData on the actor thread.
    func saveLiveScanRecord(mappedData: SpeciesData, localImagePaths: [String], observationContextsJSON: [String]? = nil, audioFilePaths: [String]? = nil) -> Bool {
        guard mappedData.confidenceScore > 0.0, let firstPath = localImagePaths.first else {
            return false
        }

        let additionalPaths: [String]? = localImagePaths.count > 1 ? Array(localImagePaths.dropFirst()) : nil

        let targetName = mappedData.scientificName
        var fetchDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.scientificName == targetName }
        )
        fetchDescriptor.fetchLimit = 1
        fetchDescriptor.propertiesToFetch = [\.speciesId]
        let existingRecords: [LocalScanRecord]
        do {
            existingRecords = try modelContext.fetch(fetchDescriptor)
        } catch {
            MerianLog.data.debug("saveLiveScanRecord: species lookup failed: \(error, privacy: .private)")
            existingRecords = []
        }

        let activeSpeciesId = existingRecords.first?.speciesId ?? UUID().uuidString
        let isNewDiscovery = existingRecords.isEmpty

        let record = LocalScanRecord(
            id: mappedData.scanId ?? UUID().uuidString,
            speciesId: activeSpeciesId,
            scientificName: mappedData.scientificName,
            commonName: mappedData.commonName,
            timestamp: Date(),
            captureDate: Date(), // Live captures always match current time
            localImagePath: firstPath,
            semanticTags: [mappedData.commonName, mappedData.scientificName] + (mappedData.colors ?? []),
            hazardType: mappedData.insightData.hazardType,
            isBiological: mappedData.isBiological,
            isLiveCapture: mappedData.isLiveCapture,
            isInvasive: mappedData.isInvasive,
            ecologyType: mappedData.ecologyType,
            wikipediaUrl: mappedData.wikipediaUrl,
            referenceImageUrl: mappedData.referenceImageUrl,
            additionalImagePaths: additionalPaths,
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
            similarSpecies: mappedData.similarSpecies?.lookalikes,
            candidatesData: mappedData.candidates.flatMap { try? JSONEncoder().encode($0) },
            iucnRedListStatus: mappedData.iucnRedListStatus,
            gpsLatitude: mappedData.gpsLatitude,
            gpsLongitude: mappedData.gpsLongitude,
            gpsElevation: mappedData.gpsElevation,
            zoomFactor: mappedData.zoomFactor,
            aiReasoning: mappedData.aiReasoning,
            habitatDescription: mappedData.habitatDescription,
            gbifTaxonKey: mappedData.gbifTaxonKey,
            estimatedSizeCm: mappedData.estimatedSizeCm,
            lifeStage: mappedData.lifeStage,
            reproductiveCondition: mappedData.reproductiveCondition,
            individualCount: mappedData.individualCount,
            ecologicalInteractions: mappedData.ecologicalInteractions,
            imageQualityScore: mappedData.imageQualityScore,
            observationContextsJSON: observationContextsJSON,
            audioFilePaths: audioFilePaths
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("saveLiveScanRecord: save failed: \(error, privacy: .private)")
        }
        return isNewDiscovery
    }

    // MARK: - Describe Recording

    /// Persists a Describe scan result — a text-description-based identification with no local image.
    ///
    /// Mirrors `saveLiveScanRecord` but omits the `localImagePath` requirement. Describes are
    /// saved with `is_live_capture = false` and nil image paths so the library renders them
    /// without a thumbnail until reference images arrive via GBIF hydration.
    func saveDescribeRecord(mappedData: SpeciesData, observationContextsJSON: [String]? = nil, audioFilePaths: [String]? = nil) -> Bool {
        guard mappedData.confidenceScore > 0.0 else { return false }

        let targetName = mappedData.scientificName
        var fetchDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.scientificName == targetName }
        )
        fetchDescriptor.fetchLimit = 1
        fetchDescriptor.propertiesToFetch = [\.speciesId]
        let existingRecords: [LocalScanRecord]
        do {
            existingRecords = try modelContext.fetch(fetchDescriptor)
        } catch {
            MerianLog.data.debug("saveDescribeRecord: species lookup failed: \(error, privacy: .private)")
            existingRecords = []
        }

        let activeSpeciesId = existingRecords.first?.speciesId ?? UUID().uuidString
        let isNewDiscovery = existingRecords.isEmpty

        let record = LocalScanRecord(
            id: mappedData.scanId ?? UUID().uuidString,
            speciesId: activeSpeciesId,
            scientificName: mappedData.scientificName,
            commonName: mappedData.commonName,
            timestamp: Date(),
            captureDate: Date(),
            localImagePath: nil,
            semanticTags: [mappedData.commonName, mappedData.scientificName] + (mappedData.colors ?? []),
            hazardType: mappedData.insightData.hazardType,
            isBiological: mappedData.isBiological,
            isLiveCapture: false,
            isInvasive: mappedData.isInvasive,
            ecologyType: mappedData.ecologyType,
            wikipediaUrl: mappedData.wikipediaUrl,
            referenceImageUrl: mappedData.referenceImageUrl,
            additionalImagePaths: nil,
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
            similarSpecies: mappedData.similarSpecies?.lookalikes,
            candidatesData: mappedData.candidates.flatMap { try? JSONEncoder().encode($0) },
            iucnRedListStatus: mappedData.iucnRedListStatus,
            gpsLatitude: mappedData.gpsLatitude,
            gpsLongitude: mappedData.gpsLongitude,
            gpsElevation: mappedData.gpsElevation,
            zoomFactor: nil,
            aiReasoning: mappedData.aiReasoning,
            habitatDescription: mappedData.habitatDescription,
            gbifTaxonKey: mappedData.gbifTaxonKey,
            estimatedSizeCm: nil,
            lifeStage: mappedData.lifeStage,
            reproductiveCondition: mappedData.reproductiveCondition,
            individualCount: mappedData.individualCount,
            ecologicalInteractions: mappedData.ecologicalInteractions,
            imageQualityScore: nil,
            observationContextsJSON: observationContextsJSON,
            audioFilePaths: audioFilePaths
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("saveDescribeRecord: save failed: \(error, privacy: .private)")
        }
        return isNewDiscovery
    }

    // MARK: - Wikipedia Enrichment

    /// Retroactively hydrates a scan record with Wikipedia data post-inference.
    func updateScanWithWikipedia(scanId: String, extract: String?, url: String?, imageUrl: String?) {
        var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.wikipediaOverview, \.wikipediaUrl, \.referenceImageUrl]
        let record: LocalScanRecord?
        do {
            record = try modelContext.fetch(descriptor).first
        } catch {
            MerianLog.data.debug("updateScanWithWikipedia: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return
        }
        guard let record else { return }

        if let extract { record.wikipediaOverview = extract }
        if let url { record.wikipediaUrl = url }
        if let img = imageUrl, !img.isEmpty {
            record.referenceImageUrl = img
        }
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("updateScanWithWikipedia: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }

    // MARK: - Record Mutation

    /// Fetches a single `LocalScanRecord` by ID, applies `mutation`, and saves.
    /// All point-update methods below delegate here to keep fetch-mutate-save DRY.
    private func mutateScan(id: String, mutation: (LocalScanRecord) -> Void) {
        var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        mutation(record)
        do { try modelContext.save() } catch {
            MerianLog.data.error("mutateScan: save failed for \(id, privacy: .private): \(error, privacy: .private)")
        }
    }

    // MARK: - Species Enrichment

    /// Patches a scan record with post-inference enrichment data from the `enrich-scan` Edge function.
    /// Each parameter is optional — callers pass only the fields their scope resolved, nil fields are skipped.
    func updateScanWithEnrichment(
        scanId: String,
        habitatDescription: String?,
        gbifTaxonKey: Int?,
        similarSpeciesJsonData: Data?,
        taxonomy: EdgeResponse.Taxonomy?,
        alternativeCommonNames: [String]? = nil
    ) {
        mutateScan(id: scanId) { record in
            if let habitat = habitatDescription { record.habitatDescription = habitat }
            if let key = gbifTaxonKey { record.gbifTaxonKey = key }
            if let jsonData = similarSpeciesJsonData { record.lookalikesData = jsonData }
            if let tax = taxonomy {
                record.taxonomyKingdom = tax.kingdom
                record.taxonomyPhylum = tax.phylum
                record.taxonomyClass = tax.`class`
                record.taxonomyOrder = tax.order
                record.taxonomyFamily = tax.family
                record.taxonomyGenus = tax.genus
            }
            if let names = alternativeCommonNames { record.alternativeCommonNames = names }
        }
    }

    // MARK: - Identification Override Persistence

    /// Persists the user's identification review action to the local SwiftData store.
    /// - Parameters:
    ///   - scanId: The scan record to update.
    ///   - override: The scientific name the user selected, or nil to clear.
    ///   - newConfirmedSpeciesId: The definitive species UUID (either the AI original or an override candidate).
    func updateScanWithOverride(
        scanId: String,
        override: String?,
        confirmed: Bool,
        newConfirmedSpeciesId: String?,
        userReviewState: UserReviewState
    ) {
        mutateScan(id: scanId) { record in
            record.userIdentificationOverride = override
            record.userConfirmedIdentification = confirmed
            record.confirmedSpeciesId = newConfirmedSpeciesId
            record.userReviewState = userReviewState
        }
    }

    /// Persists the species-dictionary data fetched for an identification override or reset,
    /// so the corrected species fields survive sheet dismissal and reopen.
    ///
    /// `scientificName` is deliberately excluded — that column is preserved as the authoritative
    /// original-AI identifier and is reused as `aiScientificName` on `load(from:)`. This allows
    /// `resetIdentificationReview` to recover the original name without a separate schema field.
    func updateScanWithOverrideSpeciesData(
        scanId: String,
        commonName: String,
        hazardType: String,
        wikipediaOverview: String?,
        wikipediaUrl: String?,
        referenceImageUrl: String?,
        iucnRedListStatus: String?,
        habitatDescription: String?,
        gbifTaxonKey: Int?,
        taxonomy: TaxonomyData?
    ) {
        mutateScan(id: scanId) { record in
            record.commonName = commonName
            record.hazardType = hazardType
            record.wikipediaOverview = wikipediaOverview
            record.wikipediaUrl = wikipediaUrl
            record.referenceImageUrl = referenceImageUrl
            record.iucnRedListStatus = iucnRedListStatus
            record.habitatDescription = habitatDescription
            record.gbifTaxonKey = gbifTaxonKey
            if let tax = taxonomy {
                record.taxonomyKingdom = tax.kingdom
                record.taxonomyPhylum = tax.phylum
                record.taxonomyClass = tax.className
                record.taxonomyOrder = tax.order
                record.taxonomyFamily = tax.family
                record.taxonomyGenus = tax.genus
            }
        }
    }

    /// Persists the user's manual review flag to the local SwiftData store.
    func updateScanAsFlagged(scanId: String) {
        mutateScan(id: scanId) { $0.isFlagged = true }
    }

    /// Removes the user's manual review flag from the local SwiftData store.
    func updateScanAsUnflagged(scanId: String) {
        mutateScan(id: scanId) { $0.isFlagged = false }
    }

    // MARK: - Collections Edge Sync

    struct SyncCollectionPayload: Encodable {
        let id: String
        let name: String
        let created_at: String
        let is_deleted: Bool
        let scan_ids: [String]
    }

    struct SyncRequestPayload: Encodable {
        let collections: [SyncCollectionPayload]
    }

    func pushCollectionsToEdge() async -> Bool {
        let collections: [ScanCollection]
        do {
            var descriptor = FetchDescriptor<ScanCollection>(
                predicate: #Predicate { $0.name != "Favorites" }
            )
            descriptor.relationshipKeyPathsForPrefetching = [\.scans]
            collections = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.debug("pushCollectionsToEdge: fetch failed: \(error, privacy: .private)")
            return false
        }

        let payloadList = collections.compactMap { col -> SyncCollectionPayload? in
            return SyncCollectionPayload(
                id: col.id,
                name: col.name,
                created_at: DateUtilities.iso8601Formatter.string(from: col.createdAt),
                is_deleted: col.isDeleted,
                scan_ids: col.scans?.compactMap(\.id) ?? []
            )
        }

        do {
            try await SupabaseManager.shared.client.functions.invoke(
                "sync-collections",
                options: .init(body: SyncRequestPayload(collections: payloadList))
            )
            
            // Cloud sync confirmed — purge soft-deleted tombstones so they cannot resurface on reinstall.
            let tombstones = collections.filter { $0.isDeleted }
            for tombstone in tombstones {
                modelContext.delete(tombstone)
            }
            if !tombstones.isEmpty {
                try? modelContext.save()
            }
            
            MerianLog.data.debug("✅ Pushed \(payloadList.count, privacy: .public) collections to Edge (\(tombstones.count, privacy: .public) tombstones purged)")
            return true
        } catch {
            MerianLog.data.debug("pushCollectionsToEdge: sync failed: \(error, privacy: .private)")
            return false
        }
    }
}
