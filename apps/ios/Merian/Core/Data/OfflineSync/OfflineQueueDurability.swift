import Foundation
import SwiftData

@MainActor
extension OfflineQueueManager {
    nonisolated static var serverRetryableFailureCode: String {
        "server_retryable_failure"
    }

    nonisolated static func isServerRetryableFailureCode(
        _ code: String?
    ) -> Bool {
        code == serverRetryableFailureCode
    }

    nonisolated static var completedServerResultRecoveryCode: String {
        "server_result_local_recovery_pending"
    }

    nonisolated static var completedServerResultRecoveryMessage: String {
        "The completed cloud analysis could not be restored locally yet."
    }

    nonisolated static var completedServerResultContractMismatchCode: String {
        "server_result_local_recovery_contract_mismatch"
    }

    nonisolated static var completedServerResultContractMismatchMessage: String {
        [
            "Naturebook found this completed analysis in the cloud, but its saved result",
            "uses an unsupported format. Update the app and retry this scan manually."
        ].joined(separator: " ")
    }

    nonisolated static func isCompletedServerResultRecoveryCode(
        _ code: String?
    ) -> Bool {
        code?.hasPrefix("server_result_local_recovery") == true
    }

    func hasDurableCompletedServerResult(scanId: String) throws -> Bool {
        let authority = try durableQueueAuthority(scanId: scanId)
        return authority.containsErrorCode(
            matching: Self.isCompletedServerResultRecoveryCode
        )
    }

    @discardableResult
    func markCompletedServerResultContractMismatch(scanId: String) -> Bool {
        markQueuedScanNeedsAttention(
            scanId: scanId,
            code: Self.completedServerResultContractMismatchCode,
            message: Self.completedServerResultContractMismatchMessage
        )
    }

    func hasDurableScheduledServerFailureRetry(
        scanId: String
    ) throws -> Bool {
        let authority = try durableQueueAuthority(scanId: scanId)
        return authority.containsErrorCode(
            matching: Self.isServerRetryableFailureCode
        )
    }

    nonisolated static func scanIngestionJobId(scanId: String) -> String {
        "scan-ingestion:\(scanId)"
    }

    nonisolated static var collectionSyncJobId: String {
        "collection-sync"
    }

    func bootstrapOfflineJobBridgeIfNeeded() {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync) else { return }
        markCollectionSyncPending()
    }

    @discardableResult
    func ensureScanIngestionJob(
        scanId: String,
        approximateBytes: Int64 = 0,
        requiresUnconstrainedNetwork: Bool = false,
        allowsCellular: Bool = true
    ) -> OfflineJobRecord? {
        guard let context = modelContext else { return nil }
        do {
            let job = try context.ensureOfflineJobRecord(
                id: Self.scanIngestionJobId(scanId: scanId),
                kind: .scanIngestion,
                subjectId: scanId,
                priority: 100,
                approximateBytes: approximateBytes,
                requiresUnconstrainedNetwork: requiresUnconstrainedNetwork,
                allowsCellular: allowsCellular
            )
            try context.save()
            return job
        } catch {
            context.rollback()
            MerianLog.data.error("ensureScanIngestionJob: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return nil
        }
    }

    @discardableResult
    func updateQueuedScanForRetry(
        scanId: String,
        code: String,
        message: String?,
        httpStatus: Int? = nil,
        serverStatus: String? = nil,
        serverStage: String? = nil,
        serverRetryAfter: Date? = nil,
        delay: TimeInterval,
        resetTo state: ScanQueueState?
    ) -> Int? {
        guard let context = modelContext else { return nil }
        let authority: OfflineQueueDurableAuthority
        do {
            authority = try durableQueueAuthority(scanId: scanId)
        } catch {
            MerianLog.data.error(
                "updateQueuedScanForRetry: authority fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return nil
        }
        let durableAttempt = authority.maximumAttemptCount
        let preservesServerFailureRetry = state == .pending &&
            authority.containsErrorCode(
                matching: Self.isServerRetryableFailureCode
            )
        let persistedCode = preservesServerFailureRetry
            ? Self.serverRetryableFailureCode
            : code
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        let scan: OfflineQueuedScan?
        do {
            scan = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.error(
                "updateQueuedScanForRetry: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return nil
        }
        guard let scan else { return nil }
        let attempt = max(scan.queueAttemptCount, durableAttempt) + 1
        let now = Date()
        scan.queueAttemptCount = attempt
        scan.queueLastAttemptAt = now
        scan.queueNextRetryAt = now.addingTimeInterval(max(1, delay))
        // A required media re-stage is one phase of the already-authorized
        // server retry. Keep its machine latch through transient signer/PUT
        // failures; the event below still records the precise upload error.
        scan.queueLastErrorCode = persistedCode
        scan.queueLastErrorMessage = message
        scan.queueLastHTTPStatus = httpStatus
        scan.queueLastServerStatus = serverStatus
        scan.queueLastServerStage = serverStage
        scan.queueLastServerRetryAfter = serverRetryAfter
        scan.queueUpdatedAt = now
        scan.queueNeedsAttention = false
        if let state {
            scan.queueState = state
        }
        do {
            try updateJobForRetry(
                scanId: scanId,
                attempt: attempt,
                nextRunAt: scan.queueNextRetryAt,
                code: persistedCode,
                message: message,
                httpStatus: httpStatus,
                serverStatus: serverStatus,
                serverStage: serverStage,
                serverRetryAfter: serverRetryAfter,
                in: context
            )
            try context.save()
        } catch {
            context.rollback()
            MerianLog.data.error("updateQueuedScanForRetry: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return nil
        }
        recordQueueEvent(
            scanId: scanId,
            jobId: Self.scanIngestionJobId(scanId: scanId),
            kind: .retryScheduled,
            message: message,
            errorCode: code,
            httpStatus: httpStatus
        )
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        return attempt
    }

    func queueAttemptCount(for scanId: String) throws -> Int {
        try durableQueueAuthority(scanId: scanId).maximumAttemptCount
    }

    /// Resumes at most one policy-blocked scan after the user explicitly
    /// reapproves the current disclosure. Durable funding metadata is the
    /// ownership proof: legacy, released, deferred, or cross-account work must
    /// remain paused for an explicit review in Scans.
    @discardableResult
    func resumeMostRecentConsentBlockedScan(accountId: UUID) -> String? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.queueNeedsAttention
                    && $0.queueLastErrorCode == "ai_consent_required"
            },
            sortBy: [
                SortDescriptor(\.queueUpdatedAt, order: .reverse),
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id)
            ]
        )
        descriptor.includePendingChanges = true

        let candidates: [OfflineQueuedScan]
        do {
            candidates = try context.fetch(descriptor)
        } catch {
            MerianLog.data.error(
                "resumeMostRecentConsentBlockedScan: fetch failed: \(error, privacy: .private)"
            )
            return nil
        }
        for scan in candidates where scan.queueState == .failed {
            let job: OfflineJobRecord?
            do {
                job = try fetchScanJob(scanId: scan.id, in: context)
            } catch {
                MerianLog.data.error(
                    "resumeMostRecentConsentBlockedScan: job fetch failed for \(scan.id, privacy: .private): \(error, privacy: .private)"
                )
                return nil
            }
            guard let job,
                  job.kind == .scanIngestion,
                  job.status == .needsAttention,
                  job.subjectId?.lowercased() == scan.id.lowercased(),
                  job.lastErrorCode == "ai_consent_required",
                  let funding = OfflineScanJobMetadataContract.funding(
                      in: job.metadataJSON
                  ),
                  !OfflineScanJobMetadataContract.fundingWasReleased(
                      in: job.metadataJSON
                  ),
                  funding.allowsDispatch,
                  funding.accountId == accountId,
                  funding.scanId == scan.id.lowercased() else {
                continue
            }
            return retryQueuedScanNow(scanId: scan.id) ? scan.id : nil
        }
        return nil
    }

    @discardableResult
    func retryQueuedScanNow(scanId: String) -> Bool {
        guard let context = modelContext else { return false }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let scan: OfflineQueuedScan?
        let shouldRecoverCompletedServerResult: Bool
        let job: OfflineJobRecord?
        do {
            scan = try context.fetch(descriptor).first
            shouldRecoverCompletedServerResult = try
                hasDurableCompletedServerResult(scanId: scanId)
            job = try fetchScanJob(scanId: scanId, in: context)
        } catch {
            MerianLog.data.error(
                "retryQueuedScanNow: authority fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        guard let scan else { return false }
        guard scan.queueState != .externalImport else { return false }

        let snapshot = scan.capturedMediaSnapshot
        var newlyClaimedFunding: ScanFundingReservation?
        if !shouldRecoverCompletedServerResult,
           let job,
           OfflineScanJobMetadataContract.fundingWasReleased(
               in: job.metadataJSON
           ) {
            guard let funding = EntitlementManager.shared.claimFunding(
                scanId: scanId,
                flashFallbackEligible: flashFallbackEligibleForRetry(snapshot)
            ) else {
                UsageManager.shared.showPaywall = true
                return false
            }
            if funding.source == .immediateFlash ||
                funding.source == .deferredFlash {
                guard UsageManager.shared.canPerformScan(isProActive: false) else {
                    EntitlementManager.shared.releaseFundingAfterProvenLocalFailure(
                        scanId: funding.scanId
                    )
                    UsageManager.shared.showPaywall = true
                    return false
                }
                UsageManager.shared.consumeScan(scanId: funding.scanId)
            }
            job.metadataJSON = OfflineScanJobMetadataContract.settingFunding(
                funding,
                in: job.metadataJSON
            )
            newlyClaimedFunding = funding
        }
        if !shouldRecoverCompletedServerResult {
            // The bounded counter governs automatic work. An explicit user
            // retry starts a new automatic budget under the same scan UUID;
            // otherwise a text-only staged scan paused at the limit would be
            // sent straight back to needs-attention before one retry could run.
            scan.queueAttemptCount = 0
        }
        let hasUploadableMedia = !(scan.inferenceImagePaths ?? snapshot.thumbnailImagePaths).isEmpty
            || !snapshot.audioPaths.isEmpty
            || !snapshot.videoPaths.isEmpty
        scan.queueNextRetryAt = nil
        scan.queueNeedsAttention = false
        scan.queueLastErrorCode = shouldRecoverCompletedServerResult
            ? Self.completedServerResultRecoveryCode
            : nil
        scan.queueLastErrorMessage = shouldRecoverCompletedServerResult
            ? Self.completedServerResultRecoveryMessage
            : nil
        scan.queueUpdatedAt = Date()
        if scan.queueState == .failed {
            scan.queueState = shouldRecoverCompletedServerResult
                ? .inferencing
                : (hasUploadableMedia ? .pending : .staged)
        }
        if !snapshot.videoPaths.isEmpty {
            userRequestedLargeUploadScanIds.insert(scanId)
        }
        if let job {
            job.status = .pending
            job.updatedAt = Date()
            job.nextRunAt = nil
            if shouldRecoverCompletedServerResult {
                job.lastErrorCode =
                    Self.completedServerResultRecoveryCode
                job.lastErrorMessage =
                    Self.completedServerResultRecoveryMessage
            } else {
                job.attemptCount = 0
                job.lastErrorCode = nil
                job.lastErrorMessage = nil
            }
        }
        context.insert(OfflineQueueEvent(
            jobId: Self.scanIngestionJobId(scanId: scanId),
            scanId: scanId,
            kind: .retryScheduled,
            message: "User requested an immediate retry."
        ))
        do {
            try context.save()
            updateUnsyncedItemCount()
            AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
            if scan.queueState == .pending {
                syncPendingScans()
            } else {
                replayInferenceForUploadedScans()
            }
            return true
        } catch {
            context.rollback()
            if let funding = newlyClaimedFunding {
                if funding.source == .immediateFlash ||
                    funding.source == .deferredFlash {
                    UsageManager.shared.refundScan(scanId: funding.scanId)
                }
                EntitlementManager.shared.releaseFundingAfterProvenLocalFailure(
                    scanId: funding.scanId
                )
            }
            MerianLog.data.error("retryQueuedScanNow: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
    }

    private func flashFallbackEligibleForRetry(
        _ snapshot: CapturedMediaSnapshot
    ) -> Bool {
        guard snapshot.items.count == 1 else { return false }
        switch snapshot.items[0] {
        case .image, .audio, .description:
            return true
        case .video:
            return false
        }
    }

    @discardableResult
    func markQueuedScanNeedsAttention(
        scanId: String,
        code: String,
        message: String?,
        httpStatus: Int? = nil
    ) -> Bool {
        guard let context = modelContext else { return false }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let scan: OfflineQueuedScan?
        let job: OfflineJobRecord?
        do {
            scan = try context.fetch(descriptor).first
            job = try fetchScanJob(scanId: scanId, in: context)
        } catch {
            MerianLog.data.error(
                "markQueuedScanNeedsAttention: authority fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        guard let scan else {
            return false
        }
        let now = Date()
        scan.queueLastAttemptAt = now
        scan.queueNextRetryAt = nil
        scan.queueLastErrorCode = code
        scan.queueLastErrorMessage = message
        scan.queueLastHTTPStatus = httpStatus
        scan.queueNeedsAttention = true
        scan.queueUpdatedAt = now
        scan.queueState = .failed
        if let job {
            job.status = .needsAttention
            job.updatedAt = now
            job.lastAttemptAt = now
            job.nextRunAt = nil
            job.lastErrorCode = code
            job.lastErrorMessage = message
            job.lastHTTPStatus = httpStatus
        }
        context.insert(OfflineQueueEvent(
            jobId: Self.scanIngestionJobId(scanId: scanId),
            scanId: scanId,
            kind: .needsAttention,
            message: message,
            errorCode: code,
            httpStatus: httpStatus
        ))
        do {
            try context.save()
            updateUnsyncedItemCount()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
            return true
        } catch {
            context.rollback()
            MerianLog.data.error("markQueuedScanNeedsAttention: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
    }

    func persistServerStatus(scanId: String, response: ScanStatusResponse) {
        guard let context = modelContext else { return }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let scan: OfflineQueuedScan?
        let job: OfflineJobRecord?
        do {
            scan = try context.fetch(descriptor).first
            job = try fetchScanJob(scanId: scanId, in: context)
        } catch {
            MerianLog.data.error(
                "persistServerStatus: authority fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return
        }
        guard let scan else { return }
        let retryAfterDate = response.retryAfter.flatMap(
            BackgroundInferencePolicy.parseRetryAfterDate
        )
        scan.queueLastServerStatus = response.jobStatus?.rawValue
        scan.queueLastServerStage = response.jobStage
        scan.queueLastServerRetryAfter = retryAfterDate
        scan.queueUpdatedAt = Date()
        if response.isFound {
            // Persist the owner-row observation before local hydration. If the
            // app terminates or the next status probe is unavailable, this
            // marker makes any later orphan claim enter bounded completed-result
            // recovery instead of permitting another provider dispatch.
            scan.queueLastErrorCode =
                Self.completedServerResultRecoveryCode
            scan.queueLastErrorMessage =
                Self.completedServerResultRecoveryMessage
        }
        if let retryAfterDate {
            scan.queueNextRetryAt = retryAfterDate
        }
        if let job {
            job.serverStatus = response.jobStatus?.rawValue
            job.serverStage = response.jobStage
            job.serverRetryAfter = retryAfterDate
            job.updatedAt = Date()
            if response.isFound {
                job.lastErrorCode =
                    Self.completedServerResultRecoveryCode
                job.lastErrorMessage =
                    Self.completedServerResultRecoveryMessage
            }
            if let retryAfterDate {
                job.nextRunAt = retryAfterDate
                job.status = .waiting
            }
        }
        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.debug("persistServerStatus: save failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func updateJobForRetry(
        scanId: String,
        attempt: Int,
        nextRunAt: Date?,
        code: String,
        message: String?,
        httpStatus: Int?,
        serverStatus: String?,
        serverStage: String?,
        serverRetryAfter: Date?,
        in context: ModelContext
    ) throws {
        let job: OfflineJobRecord
        if let existing = try fetchScanJob(scanId: scanId, in: context) {
            job = existing
        } else {
            job = OfflineJobRecord(
                id: Self.scanIngestionJobId(scanId: scanId),
                kind: .scanIngestion,
                subjectId: scanId,
                priority: 100
            )
            context.insert(job)
        }
        job.status = .waiting
        job.updatedAt = Date()
        job.lastAttemptAt = Date()
        job.nextRunAt = nextRunAt
        job.attemptCount = attempt
        job.lastErrorCode = code
        job.lastErrorMessage = message
        job.lastHTTPStatus = httpStatus
        job.serverStatus = serverStatus
        job.serverStage = serverStage
        job.serverRetryAfter = serverRetryAfter
    }

    private func fetchScanJob(
        scanId: String,
        in context: ModelContext
    ) throws -> OfflineJobRecord? {
        let jobId = Self.scanIngestionJobId(scanId: scanId)
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
