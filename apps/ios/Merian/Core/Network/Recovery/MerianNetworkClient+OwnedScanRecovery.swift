import Foundation
import os

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct ScanPublicationSnapshot {
    let scanId: String
    let imagePaths: [String]
    let videoPaths: [String]
    let audioPaths: [String]
    let coverImagePath: String?
    let fallbackImageData: Data?
    let scientificName: String
    let timestamp: Date
    let captureDate: Date?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsElevation: Double?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    let confidenceScore: Double?
    let isBiological: Bool
    let isLiveCapture: Bool
    let isInvasive: Bool
    let invasiveStatusRegion: String?
    let invasiveRationale: String?
    let invasiveConfidence: Double?
    let ecologyType: String
    let aiReasoning: String?
    let inferenceTier: String?
    let imageQualityScore: Int?
    let userIdentificationOverride: String?
    let userConfirmedIdentification: Bool
    let userReviewStateRaw: String?

    init(scan: LocalScanRecord, fallbackImageData: Data? = nil) {
        scanId = scan.id
        let mediaSnapshot = scan.capturedMediaSnapshot
        imagePaths = mediaSnapshot.thumbnailImagePaths
        videoPaths = mediaSnapshot.videoPaths
        audioPaths = mediaSnapshot.audioPaths
        coverImagePath = scan.coverImagePath
        self.fallbackImageData = fallbackImageData
        scientificName = scan.scientificName
        timestamp = scan.timestamp
        captureDate = scan.captureDate
        gpsLatitude = scan.gpsLatitude
        gpsLongitude = scan.gpsLongitude
        gpsElevation = scan.gpsElevation
        locationName = scan.locationName
        weatherCondition = scan.weatherCondition
        weatherTemperatureF = scan.weatherTemperatureF
        confidenceScore = scan.confidenceScore
        isBiological = scan.isBiological
        isLiveCapture = scan.isLiveCapture
        isInvasive = scan.isInvasive
        invasiveStatusRegion = scan.invasiveStatusRegion
        invasiveRationale = scan.invasiveRationale
        invasiveConfidence = scan.invasiveConfidence
        ecologyType = scan.ecologyType
        aiReasoning = scan.aiReasoning
        inferenceTier = scan.inferenceTier
        imageQualityScore = scan.imageQualityScore
        userIdentificationOverride = scan.userIdentificationOverride
        userConfirmedIdentification = scan.userConfirmedIdentification
        userReviewStateRaw = scan.userReviewStateRaw
    }

    var mediaSource: ScanPublicationMediaSource {
        ScanPublicationMediaSource(
            scanId: scanId,
            imagePaths: imagePaths,
            videoPaths: videoPaths,
            audioPaths: audioPaths,
            coverImagePath: coverImagePath,
            fallbackImageData: fallbackImageData
        )
    }
}

private enum ScanPersistenceProbeResult {
    case found
    case recoverableMissing
    case deferRecovery
    case serviceUnavailable
}

private struct ExploreCloudSpeciesIdRow: Decodable {
    let id: String
}

extension MerianNetworkClient {
    func shareScanToExplore(
        scan: LocalScanRecord,
        fallbackImageData: Data? = nil,
        speciesCommonName: String? = nil,
        fieldNotes: String? = nil,
        hashtags: [String] = [],
        locationSharing: ExplorePostLocationSharing? = nil,
        mediaItems: [ExplorePostMediaSelection]? = nil
    ) async throws -> ExploreShareResponse {
        let snapshot = ScanPublicationSnapshot(
            scan: scan,
            fallbackImageData: fallbackImageData
        )
        let mediaRestorer = ScanPublicationMediaRestorer(client: self)
        let idempotencyKey = UUID().uuidString.lowercased()
        do {
            return try await shareScanToExplore(
                scanId: snapshot.scanId,
                speciesCommonName: speciesCommonName,
                fieldNotes: fieldNotes,
                hashtags: hashtags,
                locationSharing: locationSharing,
                mediaItems: mediaItems,
                idempotencyKey: idempotencyKey
            )
        } catch {
            if Self.shouldAttemptExploreCloudScanRestore(after: error) {
                MerianLog.network.debug(
                    "Explore share missing cloud scan; attempting local scan recovery for \(snapshot.scanId, privacy: .private)."
                )
                switch try await waitForScanPersistence(
                    scanId: snapshot.scanId
                ) {
                case .found:
                    MerianLog.network.debug(
                        "Explore scan persistence completed; retrying share for \(snapshot.scanId, privacy: .private)."
                    )
                    return try await shareScanToExplore(
                        scanId: snapshot.scanId,
                        speciesCommonName: speciesCommonName,
                        fieldNotes: fieldNotes,
                        hashtags: hashtags,
                        locationSharing: locationSharing,
                        mediaItems: mediaItems,
                        idempotencyKey: idempotencyKey
                    )
                case .deferRecovery:
                    throw error
                case .serviceUnavailable:
                    throw MerianError.edgeFunctionUnavailable
                case .recoverableMissing:
                    break
                }

                let preparedMedia = try mediaRestorer.prepare(
                    source: snapshot.mediaSource,
                    includeAudio: true
                )
                guard !preparedMedia.isEmpty else {
                    MerianLog.network.debug(
                        "Explore share cloud scan recovery could not find restorable local media for \(snapshot.scanId, privacy: .private); refusing owner-row reconstruction."
                    )
                    throw error
                }
                let recoveryScan = try await makeOwnedScanRecoveryPayload(
                    for: snapshot,
                    locationSharing: locationSharing
                )
                let recovered = try await recoverMissingOwnedCloudScan(
                    for: snapshot,
                    locationSharing: locationSharing,
                    recoveryScan: recoveryScan
                )
                guard recovered else {
                    throw error
                }
                let restoredObjectKeys = try await mediaRestorer.restore(
                    preparedMedia
                )

                MerianLog.network.debug(
                    "Explore share cloud scan recovery uploaded \(restoredObjectKeys.imageObjectKeys.count + restoredObjectKeys.videoObjectKeys.count + restoredObjectKeys.audioObjectKeys.count, privacy: .public) media item(s); retrying."
                )
                return try await shareScanToExplore(
                    scanId: snapshot.scanId,
                    restoredObjectKeys: restoredObjectKeys.imageObjectKeys,
                    restoredVideoObjectKeys: restoredObjectKeys.videoObjectKeys,
                    restoredAudioObjectKeys: restoredObjectKeys.audioObjectKeys,
                    speciesCommonName: speciesCommonName,
                    fieldNotes: fieldNotes,
                    hashtags: hashtags,
                    locationSharing: locationSharing,
                    mediaItems: mediaItems,
                    idempotencyKey: idempotencyKey,
                    recoveryScan: recoveryScan
                )
            }

            guard ScanPublicationMediaRestorePolicy.shouldAttemptRestore(
                after: error
            ) else {
                throw error
            }

            let preparedMedia = try mediaRestorer.prepare(
                source: snapshot.mediaSource,
                includeImages: ScanPublicationMediaRestorePolicy
                    .shouldRestoreImages(after: error),
                includeAudio: true
            )
            let restoredObjectKeys = try await mediaRestorer.restore(
                preparedMedia
            )
            guard !restoredObjectKeys.isEmpty else {
                throw error
            }

            return try await shareScanToExplore(
                scanId: snapshot.scanId,
                restoredObjectKeys: restoredObjectKeys.imageObjectKeys,
                restoredVideoObjectKeys: restoredObjectKeys.videoObjectKeys,
                restoredAudioObjectKeys: restoredObjectKeys.audioObjectKeys,
                speciesCommonName: speciesCommonName,
                fieldNotes: fieldNotes,
                hashtags: hashtags,
                locationSharing: locationSharing,
                mediaItems: mediaItems,
                idempotencyKey: idempotencyKey
            )
        }
    }

    func requestCommunityIdentification(
        scan: LocalScanRecord,
        fallbackImageData: Data? = nil,
        speciesCommonName: String? = nil,
        note: String? = nil,
        locationSharing: ExplorePostLocationSharing? = nil
    ) async throws -> CommunityIdentificationRequest {
        let snapshot = ScanPublicationSnapshot(
            scan: scan,
            fallbackImageData: fallbackImageData
        )
        let mediaRestorer = ScanPublicationMediaRestorer(client: self)
        let idempotencyKey = UUID().uuidString.lowercased()
        do {
            return try await requestCommunityIdentification(
                scanId: snapshot.scanId,
                speciesCommonName: speciesCommonName,
                note: note,
                locationSharing: locationSharing,
                idempotencyKey: idempotencyKey
            )
        } catch {
            if Self.shouldAttemptExploreCloudScanRestore(after: error) {
                MerianLog.network.debug(
                    "Community request missing cloud scan; attempting local scan recovery for \(snapshot.scanId, privacy: .private)."
                )
                switch try await waitForScanPersistence(
                    scanId: snapshot.scanId
                ) {
                case .found:
                    return try await requestCommunityIdentification(
                        scanId: snapshot.scanId,
                        speciesCommonName: speciesCommonName,
                        note: note,
                        locationSharing: locationSharing,
                        idempotencyKey: idempotencyKey
                    )
                case .deferRecovery:
                    throw error
                case .serviceUnavailable:
                    throw MerianError.edgeFunctionUnavailable
                case .recoverableMissing:
                    break
                }

                let preparedMedia = try mediaRestorer.prepare(
                    source: snapshot.mediaSource,
                    includeAudio: true
                )
                guard !preparedMedia.isEmpty else {
                    MerianLog.network.debug(
                        "Community request cloud scan recovery could not find restorable local media for \(snapshot.scanId, privacy: .private); refusing owner-row reconstruction."
                    )
                    throw error
                }
                let recovered = try await recoverMissingOwnedCloudScan(
                    for: snapshot,
                    locationSharing: locationSharing
                )
                guard recovered else {
                    throw error
                }
                let restoredObjectKeys = try await mediaRestorer.restore(
                    preparedMedia
                )

                MerianLog.network.debug(
                    "Community request cloud scan recovery uploaded \(restoredObjectKeys.imageObjectKeys.count + restoredObjectKeys.videoObjectKeys.count + restoredObjectKeys.audioObjectKeys.count, privacy: .public) media item(s); retrying."
                )
                return try await requestCommunityIdentification(
                    scanId: snapshot.scanId,
                    restoredObjectKeys: restoredObjectKeys.imageObjectKeys,
                    restoredVideoObjectKeys: restoredObjectKeys.videoObjectKeys,
                    restoredAudioObjectKeys: restoredObjectKeys.audioObjectKeys,
                    speciesCommonName: speciesCommonName,
                    note: note,
                    locationSharing: locationSharing,
                    idempotencyKey: idempotencyKey
                )
            }

            guard ScanPublicationMediaRestorePolicy.shouldAttemptRestore(
                after: error
            ) else {
                throw error
            }

            let preparedMedia = try mediaRestorer.prepare(
                source: snapshot.mediaSource,
                includeAudio: true
            )
            let restoredObjectKeys = try await mediaRestorer.restore(
                preparedMedia
            )
            guard !restoredObjectKeys.isEmpty else {
                throw error
            }

            return try await requestCommunityIdentification(
                scanId: snapshot.scanId,
                restoredObjectKeys: restoredObjectKeys.imageObjectKeys,
                restoredVideoObjectKeys: restoredObjectKeys.videoObjectKeys,
                restoredAudioObjectKeys: restoredObjectKeys.audioObjectKeys,
                speciesCommonName: speciesCommonName,
                note: note,
                locationSharing: locationSharing,
                idempotencyKey: idempotencyKey
            )
        }
    }

    static func shouldAttemptExploreCloudScanRestore(after error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, message) = error,
              statusCode == 404 else {
            return false
        }

        if let code = EdgeFunctionErrorPolicy.stableCode(from: error) {
            return code == "not_found"
        }

        return message.localizedCaseInsensitiveContains("Scan not found")
    }

    @MainActor
    func ensureCloudScanAvailableForFieldChat(
        scan: LocalScanRecord,
        expectedScanId: String
    ) async throws -> Bool {
        let snapshot = ScanPublicationSnapshot(scan: scan)
        guard snapshot.scanId.caseInsensitiveCompare(expectedScanId)
                == .orderedSame else {
            throw MerianError.invalidResponse
        }
        switch try await waitForScanPersistence(scanId: snapshot.scanId) {
        case .found:
            return true
        case .deferRecovery:
            return false
        case .serviceUnavailable:
            throw MerianError.edgeFunctionUnavailable
        case .recoverableMissing:
            return try await recoverMissingOwnedCloudScan(
                for: snapshot,
                locationSharing: nil
            )
        }
    }

    private func waitForScanPersistence(
        scanId: String
    ) async throws -> ScanPersistenceProbeResult {
        let retryDelaysNanoseconds: [UInt64] = [
            0,
            250_000_000,
            500_000_000,
            1_000_000_000,
            2_000_000_000
        ]

        for delay in retryDelaysNanoseconds {
            try Task.checkCancellation()
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }

            let status: ScanStatusResponse
            do {
                status = try await checkScanStatusDetails(scanId: scanId)
            } catch MerianError.edgeFunctionUnavailable {
                try Task.checkCancellation()
                return .serviceUnavailable
            } catch {
                try Task.checkCancellation()
                return .deferRecovery
            }
            try Task.checkCancellation()
            if status.isFound {
                return .found
            }

            switch OwnedScanRecoveryPolicy.action(
                for: status.jobStatus,
                jobStage: status.jobStage,
                jobLastError: status.lastError
            ) {
            case .retryStatus:
                continue
            case .deferRecovery:
                return .deferRecovery
            case .recover:
                MerianLog.network.debug(
                    "Scan persistence unavailable for \(scanId, privacy: .private); job status=\(status.jobStatus?.rawValue ?? "none", privacy: .public) stage=\(status.jobStage ?? "none", privacy: .public)."
                )
                return .recoverableMissing
            }
        }

        return .deferRecovery
    }

    private func recoverMissingOwnedCloudScan(
        for scan: ScanPublicationSnapshot,
        locationSharing: ExplorePostLocationSharing?,
        recoveryScan: OwnedScanRecoveryPayload? = nil
    ) async throws -> Bool {
        let payload: OwnedScanRecoveryPayload
        if let recoveryScan {
            payload = recoveryScan
        } else {
            payload = try await makeOwnedScanRecoveryPayload(
                for: scan,
                locationSharing: locationSharing
            )
        }
        let status = try await checkScanStatusDetails(
            scanId: scan.scanId,
            recoveryScan: payload
        )
        return status.isFound
    }

    private func makeOwnedScanRecoveryPayload(
        for scan: ScanPublicationSnapshot,
        locationSharing: ExplorePostLocationSharing?
    ) async throws -> OwnedScanRecoveryPayload {
        let authUserID = try await authenticatedUserIDForOwnedScanRecovery()
        let authUserId = authUserID.uuidString.lowercased()
        let defaultGeoprivacy = await MainActor.run {
            AppDIContainer.shared.profileViewModel.defaultGeoprivacy
        }
        let geoprivacy = normalizedScanGeoprivacy(
            locationSharing?.rawValue ?? defaultGeoprivacy
        )
        let serverSpeciesId = try await resolveCloudSpeciesId(
            scientificName: scan.scientificName
        )
        let publicLocationLabel = geoprivacy == "private"
            ? nil
            : ExploreLocationPrivacy.displayLabel(from: scan.locationName)
        let exposesExactPublicCoordinates = geoprivacy == "open"

        return OwnedScanRecoveryPayload(
            id: scan.scanId,
            userId: authUserId,
            speciesId: serverSpeciesId,
            confirmedSpeciesId: scan.userConfirmedIdentification
                ? serverSpeciesId
                : nil,
            imageStorageUrls: [],
            timestamp: DateUtilities.iso8601Formatter.string(
                from: scan.captureDate ?? scan.timestamp
            ),
            gpsLatExact: scan.gpsLatitude,
            gpsLongExact: scan.gpsLongitude,
            gpsLatPublic: exposesExactPublicCoordinates
                ? scan.gpsLatitude
                : nil,
            gpsLongPublic: exposesExactPublicCoordinates
                ? scan.gpsLongitude
                : nil,
            gpsElevation: scan.gpsElevation,
            geoprivacy: geoprivacy,
            weatherCondition: scan.weatherCondition?.nilIfEmpty,
            weatherTemperatureF: scan.weatherTemperatureF,
            aiConfidenceScore: normalizedConfidence(scan.confidenceScore),
            ecologyType: normalizedEcologyType(scan.ecologyType),
            isInvasive: scan.isInvasive,
            invasiveStatusRegion: scan.invasiveStatusRegion?.nilIfEmpty,
            invasiveRationale: scan.invasiveRationale?.nilIfEmpty,
            invasiveConfidence: scan.invasiveConfidence,
            isLiveCapture: scan.isLiveCapture,
            isBiologicalSubject: scan.isBiological,
            aiReasoning: scan.aiReasoning?.nilIfEmpty,
            semanticLocation: scan.locationName?.nilIfEmpty,
            publicLocationLabel: publicLocationLabel,
            inferenceTier: normalizedInferenceTier(scan.inferenceTier),
            imageQualityScore: scan.imageQualityScore,
            userIdentificationOverride:
                scan.userIdentificationOverride?.nilIfEmpty,
            userConfirmedIdentification: scan.userConfirmedIdentification,
            userReviewState: normalizedUserReviewState(
                rawValue: scan.userReviewStateRaw,
                userConfirmedIdentification:
                    scan.userConfirmedIdentification,
                userIdentificationOverride: scan.userIdentificationOverride
            )
        )
    }

    private func resolveCloudSpeciesId(
        scientificName: String
    ) async throws -> String? {
        let trimmedScientificName = scientificName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedScientificName.isEmpty else { return nil }

        let rows: [ExploreCloudSpeciesIdRow] = try await SupabaseManager.shared
            .client
            .from("species_dictionary")
            .select("id")
            .eq("scientific_name", value: trimmedScientificName)
            .limit(1)
            .execute()
            .value

        return rows.first?.id
    }

    private func normalizedScanGeoprivacy(_ value: String) -> String {
        switch value {
        case "open", "obscured", "private":
            return value
        default:
            return "private"
        }
    }

    private func normalizedEcologyType(_ value: String) -> String {
        switch value {
        case "wild", "urban", "domesticated", "unknown":
            return value
        default:
            return "unknown"
        }
    }

    private func normalizedInferenceTier(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !trimmed.isEmpty else {
            return "flash"
        }
        return trimmed
    }

    private func normalizedConfidence(_ value: Double?) -> Double {
        min(1, max(0, value ?? 0))
    }

    private func normalizedUserReviewState(
        rawValue: String?,
        userConfirmedIdentification: Bool,
        userIdentificationOverride: String?
    ) -> String {
        if let rawValue,
           ["unreviewed", "ai_confirmed", "user_overridden"].contains(
               rawValue
           ) {
            return rawValue
        }
        if userConfirmedIdentification {
            return "ai_confirmed"
        }
        if userIdentificationOverride?.nilIfEmpty != nil {
            return "user_overridden"
        }
        return "unreviewed"
    }
}
