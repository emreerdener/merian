import Foundation
import SwiftData

extension BackgroundDatabaseActor {
    // MARK: - Background Account Work

    /// Persists the exact Auth/generation owner before a background URLSession
    /// task is resumed. Task descriptions are transport evidence; this job-row
    /// record is the durable local mutation fence after relaunch.
    func activateBackgroundAccountWork(
        scanId: String,
        ownership: BackgroundAccountWorkOwnership
    ) async -> Bool {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        guard !Task.isCancelled else {
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: scanId
            )
            return false
        }
        let didActivate = activateBackgroundAccountWorkLocked(
            scanId: scanId,
            ownership: ownership
        )
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        return didActivate
    }

    private func activateBackgroundAccountWorkLocked(
        scanId: String,
        ownership: BackgroundAccountWorkOwnership
    ) -> Bool {
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let scan: OfflineQueuedScan
        do {
            guard let persistedScan = try modelContext
                .fetch(scanDescriptor)
                .first else {
                return false
            }
            scan = persistedScan
        } catch {
            MerianLog.data.error(
                "activateBackgroundAccountWork: scan fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }

        let expectedState = ownership.phase == .upload
            ? ScanQueueState.uploading.rawValue
            : ScanQueueState.inferencing.rawValue
        guard scan.scanStateRaw == expectedState else { return false }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let existingJob: OfflineJobRecord?
        do {
            existingJob = try modelContext.fetchOfflineJob(id: jobId)
        } catch {
            MerianLog.data.error(
                "activateBackgroundAccountWork: job fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        let job = existingJob ?? {
            let created = OfflineJobRecord(
                id: jobId,
                kind: .scanIngestion,
                subjectId: scanId,
                status: .running
            )
            modelContext.insert(created)
            return created
        }()
        if ownership.phase == .inference,
           let durableGeneration = InferenceGenerationMetadataContract
            .generation(in: job.metadataJSON),
           durableGeneration != ownership.generation {
            return false
        }

        job.metadataJSON = OfflineScanJobMetadataContract
            .settingBackgroundAccountWork(
                ownership,
                in: job.metadataJSON
            )
        job.updatedAt = Date()
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "activateBackgroundAccountWork: persistence failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
    }

    func backgroundAccountWorkIsCurrent(
        scanId: String,
        ownership: BackgroundAccountWorkOwnership
    ) -> Bool {
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let scan: OfflineQueuedScan
        let job: OfflineJobRecord
        do {
            guard let persistedScan = try modelContext
                .fetch(scanDescriptor)
                .first,
                let persistedJob = try modelContext.fetchOfflineJob(
                    id: OfflineQueueManager.scanIngestionJobId(scanId: scanId)
                ) else {
                return false
            }
            scan = persistedScan
            job = persistedJob
        } catch {
            MerianLog.data.error(
                "backgroundAccountWorkIsCurrent: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        guard OfflineScanJobMetadataContract.backgroundAccountWork(
            in: job.metadataJSON
        ) == ownership else {
            return false
        }

        switch ownership.phase {
        case .upload:
            return scan.scanStateRaw == ScanQueueState.uploading.rawValue
        case .inference:
            return scan.scanStateRaw == ScanQueueState.inferencing.rawValue
                && InferenceGenerationMetadataContract.matches(
                    ownership.generation,
                    in: job.metadataJSON
                )
        }
    }

    /// Returns every durable URLSession owner that must be retired before the
    /// supplied Auth account can be replaced. This scan is authoritative even
    /// when the transport has already delivered its terminal callback or an
    /// unresumed task disappeared across process termination.
    func backgroundAccountWorkCandidates(
        ownerUserID: UUID?
    ) -> [BackgroundAccountWorkCandidate]? {
        let descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.kindRaw == "scanIngestion" }
        )
        let jobs: [OfflineJobRecord]
        do {
            jobs = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.error(
                "backgroundAccountWorkCandidates: fetch failed for owner \(ownerUserID?.uuidString ?? "any", privacy: .private): \(error, privacy: .private)"
            )
            return nil
        }
        return jobs.compactMap { job in
            guard let scanId = job.subjectId,
                  let ownership = OfflineScanJobMetadataContract
                    .backgroundAccountWork(in: job.metadataJSON),
                  ownerUserID.map({ $0 == ownership.ownerUserID }) ?? true
            else {
                return nil
            }
            return BackgroundAccountWorkCandidate(
                scanId: scanId,
                ownership: ownership
            )
        }
    }

    /// Retires account-bound transport work before its URLSession task is
    /// cancelled. The pending state and cleared staging manifest are committed
    /// first, so a delayed cancellation callback cannot strand `.uploading` or
    /// persist source-account media after Auth changes.
    func retireBackgroundAccountWork(
        scanId: String,
        expectedOwnerUserID: UUID?,
        expectedGeneration: UUID?,
        phase: BackgroundAccountWorkPhase
    ) async -> Bool {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        let didRetire = retireBackgroundAccountWorkLocked(
            scanId: scanId,
            expectedOwnerUserID: expectedOwnerUserID,
            expectedGeneration: expectedGeneration,
            phase: phase
        )
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        return didRetire
    }

    private func retireBackgroundAccountWorkLocked(
        scanId: String,
        expectedOwnerUserID: UUID?,
        expectedGeneration: UUID?,
        phase: BackgroundAccountWorkPhase
    ) -> Bool {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let scans: [OfflineQueuedScan]
        do {
            scans = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.error(
                "retireBackgroundAccountWork: scan fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let job: OfflineJobRecord?
        do {
            job = try modelContext.fetchOfflineJob(id: jobId)
        } catch {
            MerianLog.data.error(
                "retireBackgroundAccountWork: job fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        let durableOwnership = OfflineScanJobMetadataContract
            .backgroundAccountWork(in: job?.metadataJSON)
        if let durable = durableOwnership {
            guard durable.phase == phase,
                  expectedOwnerUserID == durable.ownerUserID,
                  expectedGeneration == durable.generation
            else {
                // The task being retired is stale relative to a newer durable
                // owner. Cancelling that transport is safe, but it must not
                // mutate the newer queue operation.
                return true
            }
        }

        guard let scan = scans.first else {
            return clearBackgroundAccountWorkMetadataIfNeeded(job: job)
        }
        let ownsRunnableState: Bool
        if durableOwnership != nil {
            // A terminal callback may advance upload -> staged (or claim
            // inference) immediately before the transition quiescer acquires
            // this actor. The exact durable owner remains authoritative in
            // that race, so retire every runnable state and discard its
            // source-account staging keys. Otherwise the next Auth account
            // could replay media written under the previous account.
            switch scan.queueState {
            case .pending, .uploading, .staged, .inferencing:
                ownsRunnableState = true
            case .externalImport, .failed:
                ownsRunnableState = false
            }
        } else {
            let expectedState = phase == .upload
                ? ScanQueueState.uploading.rawValue
                : ScanQueueState.inferencing.rawValue
            ownsRunnableState = scan.scanStateRaw == expectedState
        }
        guard ownsRunnableState else {
            return clearBackgroundAccountWorkMetadataIfNeeded(job: job)
        }

        let now = Date()
        scan.scanStateRaw = ScanQueueState.pending.rawValue
        scan.stagedR2Keys = nil
        scan.queueNextRetryAt = nil
        scan.queueNeedsAttention = false
        scan.queueUpdatedAt = now
        if let job {
            job.status = .pending
            job.updatedAt = now
            job.nextRunAt = nil
            job.metadataJSON = OfflineScanJobMetadataContract
                .clearingBackgroundAccountWork(in: job.metadataJSON)
        }
        modelContext.insert(OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .retryScheduled,
            message: "Retired account-bound background work before an authentication transition."
        ))
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "retireBackgroundAccountWork: persistence failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
    }

    private func clearBackgroundAccountWorkMetadataIfNeeded(
        job: OfflineJobRecord?
    ) -> Bool {
        guard let job,
              OfflineScanJobMetadataContract.backgroundAccountWork(
                  in: job.metadataJSON
              ) != nil else {
            return true
        }
        job.metadataJSON = OfflineScanJobMetadataContract
            .clearingBackgroundAccountWork(in: job.metadataJSON)
        job.updatedAt = Date()
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "retireBackgroundAccountWork: metadata cleanup failed: \(error, privacy: .private)"
            )
            return false
        }
    }
}
