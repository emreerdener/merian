import Foundation
import SwiftData
import CoreLocation
import Supabase
import os

// MARK: - Extracted Scan Data

/// Sendable snapshot of `OfflineQueuedScan` metadata captured on the main actor.
///
/// Passed across the actor boundary into `runInferencePipeline` so that background
/// inference can proceed without touching the main-actor-bound `ModelContext`.
struct ExtractedScanData {
    /// Environmental and capture telemetry for the scan, used as Gemini inference context.
    let telemetry: CaptureTelemetry
    /// Filenames of local images relative to the Documents directory.
    let localImagePaths: [String]
    /// The model container, used to create a new `BackgroundDatabaseActor` on the inference thread.
    let container: ModelContainer
    /// Original capture timestamp, used for historical weather backfill and record persistence.
    let originalTimestamp: Date
}

// MARK: - Background Database Actor

/// Swift 6-safe actor that performs all SwiftData reads and writes off the main thread.
///
/// Conforms to `@ModelActor`, which provides an isolated `modelContext` bound to this actor.
/// All methods are safe to call from `Task { }` or `BackgroundTaskWrapper.execute` contexts.
@ModelActor
actor BackgroundDatabaseActor {

    // MARK: - Data Transfer Objects

    /// Minimal Sendable representation of a pending scan, safe to pass across actor boundaries.
    struct PendingScanPayload: Sendable {
        let id: String
        let localImagePaths: [String]
    }

    // MARK: - Pending Scan Fetching

    /// Returns up to `limit` undeleted `OfflineQueuedScan` records sorted oldest-first.
    func fetchPendingScans(limit: Int) -> [PendingScanPayload] {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.isDeleted == false })
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

    // MARK: - Offline Scan Processing

    /// Decodes edge inference results, persists a LocalScanRecord, then removes the OfflineQueuedScan.
    func processAndCleanupOfflineScan(
        resultData: Data,
        originalImagePaths: [String],
        scanId: String,
        originalTimestamp: Date,
        telemetry: CaptureTelemetry? = nil
    ) -> (resolvedSpeciesName: String?, isNewDiscovery: Bool) {
        var inferenceFailed = true
        var resolvedSpeciesName: String? = nil
        var finalIsNewDiscovery = false

        let parsedWrapper: EdgeResponseWrapper?
        do {
            parsedWrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: resultData)
        } catch {
            MerianLog.data.debug("processAndCleanupOfflineScan: JSON decode failed: \(error, privacy: .private)")
            parsedWrapper = nil
        }

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

                let targetName = mappedData.scientificName
                var fetchDescriptor = FetchDescriptor<LocalScanRecord>(
                    predicate: #Predicate<LocalScanRecord> { $0.scientificName == targetName }
                )
                fetchDescriptor.fetchLimit = 1
                fetchDescriptor.propertiesToFetch = [\.speciesId]
                let existingRecords: [LocalScanRecord]
                do {
                    existingRecords = try modelContext.fetch(fetchDescriptor)
                } catch {
                    MerianLog.data.debug("processAndCleanupOfflineScan: species lookup failed: \(error, privacy: .private)")
                    existingRecords = []
                }

                let activeSpeciesId = existingRecords.first?.speciesId ?? UUID().uuidString

                if existingRecords.isEmpty {
                    mappedData.isNewDiscovery = true
                    finalIsNewDiscovery = true
                }

                let diagnosticDifferentiatorsJson: String? = {
                    guard let diffs = mappedData.diagnosticComparison?.keyDifferentiators else { return nil }
                    do {
                        let data = try JSONEncoder().encode(diffs)
                        return String(data: data, encoding: .utf8)
                    } catch {
                        MerianLog.data.debug("processAndCleanupOfflineScan: JSON encode failed: \(error, privacy: .private)")
                        return nil
                    }
                }()

                let record = LocalScanRecord(
                    id: mappedData.scanId ?? UUID().uuidString,
                    speciesId: activeSpeciesId,
                    scientificName: mappedData.scientificName,
                    commonName: mappedData.commonName,
                    timestamp: originalTimestamp,
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
                    diagnosticPrimaryRationale: mappedData.diagnosticComparison?.primaryMatchRationale,
                    diagnosticLookalikeName: mappedData.diagnosticComparison?.confusingLookalikeName,
                    diagnosticDifferentiatorsJson: diagnosticDifferentiatorsJson,
                    iucnRedListStatus: mappedData.iucnRedListStatus,
                    gpsLatitude: mappedData.gpsLatitude,
                    gpsLongitude: mappedData.gpsLongitude,
                    gpsElevation: mappedData.gpsElevation,
                    zoomFactor: mappedData.zoomFactor,
                    aiReasoning: mappedData.aiReasoning,
                    habitatDescription: mappedData.habitatDescription,
                    globalDistributionRegionsJson: {
                        guard let dist = mappedData.globalDistributionRegions else { return nil }
                        do {
                            let data = try JSONEncoder().encode(dist)
                            return String(data: data, encoding: .utf8)
                        } catch { return nil }
                    }()
                )
                modelContext.insert(record)
                do {
                    try modelContext.save()
                } catch {
                    MerianLog.data.error("processAndCleanupOfflineScan: save failed: \(error, privacy: .private)")
                }
            }
        }

        // Dequeue the OfflineQueuedScan and purge local image files if inference failed.
        do {
            var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            descriptor.fetchLimit = 1
            let matches = try modelContext.fetch(descriptor)
            for scan in matches { modelContext.delete(scan) }
            try modelContext.save()

            if inferenceFailed {
                Task { await FileIOActor.shared.deleteImages(at: originalImagePaths) }
            }
        } catch {
            MerianLog.data.error("processAndCleanupOfflineScan: dequeue failed — scan may be reprocessed on next sync: \(error, privacy: .private)")
        }

        return (resolvedSpeciesName, finalIsNewDiscovery)
    }

    // MARK: - Live Scan Recording

    /// Persists a real-time scan result to SwiftData on the actor thread.
    func saveLiveScanRecord(mappedData: SpeciesData, localImagePaths: [String]) -> Bool {
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

        let diagnosticDifferentiatorsJson: String? = {
            guard let diffs = mappedData.diagnosticComparison?.keyDifferentiators else { return nil }
            do {
                let data = try JSONEncoder().encode(diffs)
                return String(data: data, encoding: .utf8)
            } catch {
                MerianLog.data.debug("saveLiveScanRecord: JSON encode failed: \(error, privacy: .private)")
                return nil
            }
        }()

        let record = LocalScanRecord(
            id: mappedData.scanId ?? UUID().uuidString,
            speciesId: activeSpeciesId,
            scientificName: mappedData.scientificName,
            commonName: mappedData.commonName,
            timestamp: Date(),
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
            diagnosticPrimaryRationale: mappedData.diagnosticComparison?.primaryMatchRationale,
            diagnosticLookalikeName: mappedData.diagnosticComparison?.confusingLookalikeName,
            diagnosticDifferentiatorsJson: diagnosticDifferentiatorsJson,
            iucnRedListStatus: mappedData.iucnRedListStatus,
            gpsLatitude: mappedData.gpsLatitude,
            gpsLongitude: mappedData.gpsLongitude,
            gpsElevation: mappedData.gpsElevation,
            zoomFactor: mappedData.zoomFactor,
            aiReasoning: mappedData.aiReasoning,
            habitatDescription: mappedData.habitatDescription,
            globalDistributionRegionsJson: {
                guard let dist = mappedData.globalDistributionRegions else { return nil }
                do {
                    let data = try JSONEncoder().encode(dist)
                    return String(data: data, encoding: .utf8)
                } catch { return nil }
            }()
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("saveLiveScanRecord: save failed: \(error, privacy: .private)")
        }
        return isNewDiscovery
    }

    // MARK: - Wikipedia Enrichment

    /// Retroactively hydrates a scan record with Wikipedia data post-inference.
    func updateScanWithWikipedia(scanId: String, extract: String, url: String, imageUrl: String?) {
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

        record.wikipediaOverview = extract
        record.wikipediaUrl = url
        if let img = imageUrl, !img.isEmpty {
            record.referenceImageUrl = img
        }
        do {
            try modelContext.save()
        } catch {
            MerianLog.data.error("updateScanWithWikipedia: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }

    // MARK: - Premium Enrichment

    func updateScanWithEnrichment(
        scanId: String,
        habitatDescription: String?,
        globalDistributionRegions: [String]?,
        diagnosticPrimaryRationale: String?,
        diagnosticLookalikeName: String?,
        diagnosticKeyDifferentiators: [String]?
    ) {
        var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(descriptor).first else { return }

        if let habitat = habitatDescription { record.habitatDescription = habitat }
        if let regions = globalDistributionRegions,
           let encoded = try? JSONEncoder().encode(regions),
           let json = String(data: encoded, encoding: .utf8) {
            record.globalDistributionRegionsJson = json
        }
        if let rationale = diagnosticPrimaryRationale { record.diagnosticPrimaryRationale = rationale }
        if let lookalike = diagnosticLookalikeName { record.diagnosticLookalikeName = lookalike }
        if let diffs = diagnosticKeyDifferentiators,
           let encoded = try? JSONEncoder().encode(diffs),
           let json = String(data: encoded, encoding: .utf8) {
            record.diagnosticDifferentiatorsJson = json
        }

        try? modelContext.save()
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
            MerianLog.data.debug("✅ Pushed \(payloadList.count, privacy: .public) collections to Edge")
            return true
        } catch {
            MerianLog.data.debug("pushCollectionsToEdge: sync failed: \(error, privacy: .private)")
            return false
        }
    }
}
