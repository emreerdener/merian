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
        for data: SpeciesData
    ) throws -> (speciesId: String, isNewDiscovery: Bool) {
        if data.primaryIdentification != nil && !data.hasSpeciesLevelIdentification {
            return ("", false)
        }
        return try scanRecordSpeciesIdentity(for: data.scientificName)
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
        if let existing = try localScanRecord(id: recordId) {
            try validatePrimaryCompletion(mappedData, existing: existing)
            return
        }

        try validatePrimaryCompletion(mappedData, existing: nil)
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
        if let existing = try localScanRecord(id: recordId) {
            try validatePrimaryCompletion(mappedData, existing: existing)
            return
        }

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
        try validatePrimaryCompletion(mappedData, existing: nil)
        if let existing = try localScanRecord(id: recordId) {
            try validatePrimaryCompletion(mappedData, existing: existing)
            if existing.primaryIdentification != nil { return }
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

    func validatePrimaryCompletion(_ data: SpeciesData, existing: LocalScanRecord?) throws {
        if existing?.primaryIdentification != nil && data.primaryIdentification == nil {
            throw PrimaryIdentification.IntegrityError.missingRequiredSnapshot
        }
        try PrimaryIdentificationPersistence.validateMerge(
            storedPrimary: existing?.primaryIdentificationData,
            storedProvenance: existing?.identificationProvenanceData,
            incomingPrimary: data.primaryIdentification,
            incomingProvenance: data.identificationProvenance
        )
    }

}
