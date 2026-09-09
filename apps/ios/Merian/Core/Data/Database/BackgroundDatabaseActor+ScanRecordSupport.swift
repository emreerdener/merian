import Foundation
import SwiftData

/// Actor-isolated support shared only by the focused offline and live scan
/// persistence owners. Keeping these operations on `BackgroundDatabaseActor`
/// prevents a `ModelContext` or persistent model from crossing an actor boundary.
extension BackgroundDatabaseActor {
    func acquireScanFinalizationLock(
        scanId: String,
        operation: String
    ) async {
        let waited = await ScanFinalizationCoordinator.shared.acquire(
            scanId: scanId
        )
        if waited {
            MerianLog.data.debug(
                "Scan finalization waited for existing writer operation=\(operation, privacy: .public) scanId=\(scanId, privacy: .public)"
            )
        }
    }

    func scanRecordSpeciesIdentity(
        for scientificName: String
    ) throws -> (speciesId: String, isNewDiscovery: Bool) {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.scientificName == scientificName }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.speciesId]

        let existingRecords = try modelContext.fetch(descriptor)

        return (
            existingRecords.first?.speciesId ?? UUID().uuidString,
            existingRecords.isEmpty
        )
    }

    func localScanRecord(id recordId: String) throws -> LocalScanRecord? {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == recordId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func preservedScanRecordFieldNotes(scanId: String) throws -> String? {
        if let localNotes = try localScanRecord(id: scanId)?.fieldNotes?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !localNotes.isEmpty {
            return localNotes
        }

        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let queuedNotes = try modelContext.fetch(descriptor).first?.fieldNotes?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return queuedNotes?.isEmpty == false ? queuedNotes : nil
    }

    func insertOfflineScanRecordIfMissing(
        mappedData: SpeciesData,
        recordId: String,
        speciesId: String,
        discoveryTimestamp: Date,
        originalImagePaths: [String],
        observationContextsJSON: [String]?,
        audioFilePaths: [String]?,
        videoFilePaths: [String]?,
        capturedMediaJSON: String?
    ) async throws {
        guard try localScanRecord(id: recordId) == nil else { return }

        let resolvedCapturedMediaJSON: String?
        if let capturedMediaJSON {
            resolvedCapturedMediaJSON = capturedMediaJSON
        } else {
            resolvedCapturedMediaJSON = await CapturedMediaPersistenceService
                .live.makeCapturedMediaJSON(for: .init(
                    localImagePaths: originalImagePaths,
                    observationContextsJSON: observationContextsJSON ?? [],
                    audioFilePaths: audioFilePaths ?? mappedData.audioFilePaths ?? [],
                    videoFilePaths: videoFilePaths ?? mappedData.videoFilePaths ?? []
                ))
        }

        try Task.checkCancellation()
        guard try localScanRecord(id: recordId) == nil else { return }

        modelContext.insert(LocalScanRecordFactory.makeRecord(
            from: mappedData,
            recordId: recordId,
            speciesId: speciesId,
            timestamp: discoveryTimestamp,
            captureDate: discoveryTimestamp,
            capturedMediaJSON: resolvedCapturedMediaJSON,
            coverImagePath: originalImagePaths.first,
            isLiveCapture: mappedData.isLiveCapture,
            fieldNotes: try preservedScanRecordFieldNotes(scanId: recordId)
        ))
    }

    func insertReplacingLocalScanRecord(
        mappedData: SpeciesData,
        recordId: String,
        speciesId: String,
        timestamp: Date,
        captureDate: Date,
        capturedMediaJSON: String?,
        coverImagePath: String?,
        isLiveCapture: Bool,
        fieldNotes: String?
    ) throws {
        if let existing = try localScanRecord(id: recordId) {
            modelContext.delete(existing)
        }
        modelContext.insert(LocalScanRecordFactory.makeRecord(
            from: mappedData,
            recordId: recordId,
            speciesId: speciesId,
            timestamp: timestamp,
            captureDate: captureDate,
            capturedMediaJSON: capturedMediaJSON,
            coverImagePath: coverImagePath,
            isLiveCapture: isLiveCapture,
            fieldNotes: fieldNotes
        ))
    }
}
