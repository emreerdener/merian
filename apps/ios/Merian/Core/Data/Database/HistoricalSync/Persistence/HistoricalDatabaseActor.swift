import Foundation
import os
import SwiftData

// MARK: - SwiftData Asynchronous Actors

/// Executes bulk historical reconciliation in an actor-isolated SwiftData context
/// without giving the main actor persistence ownership.
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
    func reconcileScanPage(
        responses: [HistoricalScanResponse]
    ) throws -> Int {
        do {
            try Task.checkCancellation()
            let recoveryCount = LocalScanMediaRecoveryResolver
                .registerRecoveryMappings(for: responses)
            if recoveryCount > 0 {
                MerianLog.data.info(
                    "Historical media recovery registered \(recoveryCount, privacy: .public) scan image mapping(s)."
                )
            }
            let responseIds = responses.map { $0.id }
            var existingIds = Set<String>()

            let chunkSize = 500
            for chunkStart in stride(
                from: 0,
                to: responseIds.count,
                by: chunkSize
            ) {
                try Task.checkCancellation()
                let chunk = Array(
                    responseIds[
                        chunkStart..<min(
                            chunkStart + chunkSize,
                            responseIds.count
                        )
                    ]
                )
                // propertiesToFetch: [\.id] loads only the id column — no full record fault.
                // fetchIdentifiers + model(for:) previously faulted complete LocalScanRecord objects
                // just to extract the id string, loading all columns for every existing record.
                var descriptor = FetchDescriptor<LocalScanRecord>(
                    predicate: #Predicate { chunk.contains($0.id) }
                )
                descriptor.propertiesToFetch = [\.id]
                for record in try modelContext.fetch(descriptor) {
                    existingIds.insert(record.id)
                }
            }

            try updateExistingScans(
                responses: responses,
                existingIds: existingIds
            )

            let missingScans = responses.filter {
                !existingIds.contains($0.id)
            }
            guard !missingScans.isEmpty else { return 0 }

            return try ingestScans(missingScans: missingScans)
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "reconcileScanPage: local reconciliation failed: \(error, privacy: .private)"
            )
            throw error
        }
    }

    /// Reconciles the full remote collection list against local state
    func syncCollectionsDown(
        remoteCollections: [CloudCollectionResponse]
    ) throws {
        do {
            try syncCollections(remoteCollections: remoteCollections)
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "syncCollectionsDown: local reconciliation failed: \(error, privacy: .private)"
            )
            throw error
        }
    }

    // MARK: - Private Helpers

    private func updateExistingScans(
        responses: [HistoricalScanResponse],
        existingIds: Set<String>
    ) throws {
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
            try Task.checkCancellation()
            let chunkIds = Array(responseIds[chunkStart..<min(chunkStart + chunkSize, responseIds.count)])

            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { chunkIds.contains($0.id) })
            let chunkRecords = try modelContext.fetch(descriptor)
            let chunkLookup = Dictionary(uniqueKeysWithValues: chunkRecords.map { ($0.id, $0) })

            var chunkDidUpdate = false
            for id in chunkIds {
                guard let existing = chunkLookup[id], let res = responseLookup[id] else { continue }

                let dictRefImage = ExternalReferenceImagePolicy.sanitizedURLList(
                    res.species_dictionary?.reference_image_url
                )

                let existingMediaSnapshot = existing.capturedMediaSnapshot
                let hydratedItems = CapturedMediaSnapshot.cloudHydratedItems(
                    capturedMediaItems: res.capturedMediaItems,
                    imageStorageURLs: res.image_storage_urls,
                    videoStorageURLs: res.video_storage_urls,
                    audioStorageURLs: res.audio_storage_urls,
                    observationContext:
                        res.user_observation_context?.observationContext
                )
                let newItems = CapturedMediaSnapshot.preservingExistingNonVisualItems(
                    in: hydratedItems,
                    from: existingMediaSnapshot
                )
                if CloudMediaReplacementPolicy.shouldReplace(
                    existing: existingMediaSnapshot,
                    hydratedItems: newItems,
                    imageStorageURLs: res.image_storage_urls,
                    videoStorageURLs: res.video_storage_urls
                ) {
                    existing.replaceCapturedMedia(with: newItems)
                    chunkDidUpdate = true
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
                if let isBiological = res.is_biological_subject,
                   existing.isBiological != isBiological {
                    existing.isBiological = isBiological
                    chunkDidUpdate = true
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
                if existing.petIdentificationData == nil, let petIdentification = res.pet_identification {
                    existing.petIdentificationData = try? encoder.encode(petIdentification)
                    chunkDidUpdate = true
                }
                if let petLabel = res.pet_identification?.label.trimmingCharacters(in: .whitespacesAndNewlines),
                   !petLabel.isEmpty,
                   !existing.semanticTags.contains(where: { $0.localizedCaseInsensitiveCompare(petLabel) == .orderedSame }) {
                    existing.semanticTags.append(petLabel)
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
                try Task.checkCancellation()
                try saveHistoricalContext("updateExistingScans chunk")
            }
        }
    }

    private func ingestScans(
        missingScans: [HistoricalScanResponse]
    ) throws -> Int {
        let checkpointInterval = MerianConfig.ingestCheckpointInterval
        // Hoist encoder outside the loop — JSONEncoder allocation is non-trivial (Obj-C init,
        // key strategy setup, etc.) and creating one per scan across thousands of records adds
        // measurable GC pressure on the @ModelActor thread.
        let encoder = JSONEncoder()
        var insertedCount = 0
        for (index, scan) in missingScans.enumerated() {
            try Task.checkCancellation()
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

            let semanticPetTags = [scan.pet_identification?.label].compactMap {
                $0?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            let semanticTags: [String] = [cName, sciName] + semanticPetTags + (scan.colors ?? []) + (dict?.group_tags ?? [])
            let candidatesData: Data? = scan.candidates.flatMap { entries in
                try? encoder.encode(entries.map {
                    IdentificationCandidate(scientificName: $0.scientific_name, commonName: $0.common_name, confidenceScore: $0.confidence_score, distinguishingFeature: $0.distinguishing_feature)
                })
            }
            let petIdentificationData: Data? = scan.pet_identification.flatMap {
                try? encoder.encode($0)
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
                isBiological: scan.is_biological_subject ?? true,
                isLiveCapture: scan.is_live_capture ?? true,
                isInvasive: scan.is_invasive ?? false,
                invasiveStatusRegion: scan.invasive_status_region,
                invasiveRationale: scan.invasive_rationale,
                invasiveConfidence: scan.invasive_confidence,
                ecologyType: scan.ecology_type ?? "unknown",
                wikipediaUrl: dict?.wikipedia_url,
                wikipediaOverview: wikiExtract,
                referenceImageUrl: ExternalReferenceImagePolicy.sanitizedURLList(
                    dict?.reference_image_url
                ),
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
                imageQualityScore: scan.image_quality_score,
                petIdentificationData: petIdentificationData
            )
            
            let newItems = CapturedMediaSnapshot.cloudHydratedItems(
                capturedMediaItems: scan.capturedMediaItems,
                imageStorageURLs: scan.image_storage_urls,
                videoStorageURLs: scan.video_storage_urls,
                audioStorageURLs: scan.audio_storage_urls,
                observationContext:
                    scan.user_observation_context?.observationContext
            )
            record.replaceCapturedMedia(with: newItems)

            modelContext.insert(record)
            insertedCount += 1

            if (index + 1).isMultiple(of: checkpointInterval) {
                try Task.checkCancellation()
                try saveHistoricalContext(
                    "ingestScans checkpoint at index \(index)"
                )
            }
        }

        try Task.checkCancellation()
        try saveHistoricalContext("ingestScans final")
        return insertedCount
    }

    private func syncCollections(
        remoteCollections: [CloudCollectionResponse]
    ) throws {
        try Task.checkCancellation()
        // fetchLimit: 500 is a defensive ceiling — an unbounded full-table scan can fault orphaned
        // or schema-migrated collection records into memory before sync begins.
        var collectionsDescriptor = FetchDescriptor<ScanCollection>()
        collectionsDescriptor.fetchLimit = 500
        let existingCollections = try modelContext.fetch(
            collectionsDescriptor
        )
        var existingLookup = Dictionary(existingCollections.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        
        // Fetch only the local scan records referenced by the incoming collections.
        let referencedScanIds = remoteCollections.compactMap { $0.collection_scans }.flatMap { $0 }.map { $0.scan_id }
        let allScansDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { referencedScanIds.contains($0.id) })
        let localScans: [LocalScanRecord] = referencedScanIds.isEmpty
            ? []
            : try modelContext.fetch(allScansDescriptor)
        let localScansLookup = Dictionary(localScans.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // Read membership from the `LocalScanRecord.collections` side in bounded batches to
        // avoid faulting every `ScanCollection.scans` array or the entire scan library at once.
        let relevantCollectionIDs = Set(remoteCollections.map { $0.id.lowercased() })
        var collectionMembersByID = try fetchCollectionMembersByID(
            relevantCollectionIDs: relevantCollectionIDs,
            modelContext: modelContext
        )

        for remote in remoteCollections {
            try Task.checkCancellation()
            let col: ScanCollection
            let remoteIdLower = remote.id.lowercased()
            if let existing = existingLookup[remoteIdLower] {
                col = existing
                existingLookup.removeValue(forKey: remoteIdLower)
                
                // --- INBOUND SHIELD ---
                // If a collection is marked as deleted locally, aggressively ignore any remote
                // representations of it. This prevents an obsolete or delayed remote state
                // from "resurrecting" the collection locally or wiping its tombstone status.
                if existing.isPendingDeletion {
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

        try Task.checkCancellation()
        for (_, obsolete) in existingLookup where obsolete.name != "Favorites" {
            try Task.checkCancellation()
            modelContext.delete(obsolete)
        }

        try Task.checkCancellation()
        try saveHistoricalContext("syncCollections inbound reconciliation")
    }

    private func saveHistoricalContext(_ logContext: String) throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error("\(logContext, privacy: .public): save failed; rolled back context: \(error, privacy: .private)")
            throw error
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
    ) throws -> [String: [LocalScanRecord]] {
        guard !relevantCollectionIDs.isEmpty else { return [:] }

        let batchSize = 200
        var offset = 0
        var collectionMembersByID: [String: [LocalScanRecord]] = [:]

        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<LocalScanRecord>(
                sortBy: [SortDescriptor(\.timestamp)]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            descriptor.relationshipKeyPathsForPrefetching = [\.collections]

            let batch = try modelContext.fetch(descriptor)
            guard !batch.isEmpty else { break }

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
