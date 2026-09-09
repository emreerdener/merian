import Foundation
import SwiftData

/// Durable outcome of promoting a completed upload manifest into
/// inference-ready state.
///
/// The URLSession callback must not infer success from an in-memory HTTP
/// completion set: inference is eligible only after the queue transition
/// commits, or when another serialized owner already advanced the same durable
/// row.
enum ScanStagingTransitionOutcome: Sendable, Equatable {
    /// This call committed `.uploading → .staged` with the exact R2 keys.
    case staged
    /// A serialized owner saved the same staged manifest or already began
    /// inference.
    case alreadyAdvanced
    /// The row remains retryable, but this call could not commit the
    /// transition.
    case retryRequired
    /// The row is missing or non-runnable and must not be resurrected.
    case discarded
}

extension BackgroundDatabaseActor {
    // MARK: - Upload Claim

    /// Transitions runnable `.pending` scans to `.uploading` and persists,
    /// preventing `syncPendingScans` from re-dispatching upload tasks for these
    /// scans after an app restart. Attention and future-retry rows cannot be
    /// claimed from a stale candidate snapshot.
    func markScansAsUploading(scanIds: [String]) -> Set<String> {
        guard !scanIds.isEmpty else { return [] }
        let pendingRaw = ScanQueueState.pending.rawValue
        let uploadingRaw = ScanQueueState.uploading.rawValue
        var claimedScanIds = Set<String>()

        // Process in chunks to prevent unbounded memory loads and SQL IN-clause
        // overflow.
        let chunkSize = 50
        for index in stride(from: 0, to: scanIds.count, by: chunkSize) {
            let chunkEnd = min(index + chunkSize, scanIds.count)
            let chunk = Array(scanIds[index..<chunkEnd])

            // SwiftData safely supports array.contains in #Predicate for
            // bounded chunks.
            let descriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate {
                    chunk.contains($0.id)
                        && $0.scanStateRaw == pendingRaw
                        && !$0.queueNeedsAttention
                }
            )

            do {
                let scans = try modelContext.fetch(descriptor)
                let now = Date()
                for scan in scans {
                    guard scan.queueNextRetryAt.map({ $0 <= now }) ?? true else {
                        continue
                    }
                    let jobId = OfflineQueueManager.scanIngestionJobId(
                        scanId: scan.id
                    )
                    let job: OfflineJobRecord?
                    do {
                        job = try modelContext.fetchOfflineJob(id: jobId)
                    } catch {
                        modelContext.rollback()
                        MerianLog.data.error(
                            "markScansAsUploading: job fetch failed for \(scan.id, privacy: .private): \(error, privacy: .private)"
                        )
                        return []
                    }
                    scan.scanStateRaw = uploadingRaw
                    scan.queueLastAttemptAt = now
                    scan.queueNextRetryAt = nil
                    scan.queueUpdatedAt = now
                    if let job {
                        reconcileMirroredInferenceState(
                            scan: scan,
                            job: job
                        )
                        job.status = .running
                        job.updatedAt = now
                        job.lastAttemptAt = now
                        job.nextRunAt = nil
                        job.attemptCount = scan.queueAttemptCount
                    }
                    modelContext.insert(OfflineQueueEvent(
                        jobId: jobId,
                        scanId: scan.id,
                        kind: .claimed,
                        message: "Queued scan claimed for media upload."
                    ))
                    claimedScanIds.insert(scan.id)
                }
            } catch {
                modelContext.rollback()
                MerianLog.data.error(
                    "markScansAsUploading: fetch failed: \(error, privacy: .private)"
                )
                return []
            }
        }

        guard !claimedScanIds.isEmpty else {
            MerianLog.data.debug(
                "markScansAsUploading: no pending scans claimed from candidates=\(scanIds.joined(separator: ","), privacy: .public)"
            )
            return []
        }

        do {
            try modelContext.save()
            MerianLog.data.debug(
                "markScansAsUploading: claimed ids=\(claimedScanIds.sorted().joined(separator: ","), privacy: .public)"
            )
            return claimedScanIds
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "markScansAsUploading: save failed: \(error, privacy: .private)"
            )
            return []
        }
    }

    // MARK: - Upload Completion

    /// Persists confirmed R2 keys, normally resets upload retry metadata, and
    /// transitions to `.staged`.
    ///
    /// Called once the last image upload for a scan is confirmed (HTTP 200).
    /// Storing keys here eliminates auth-dependent key reconstruction at
    /// inference time. An exact scheduled server-failure reclaim preserves its
    /// retry latch and accounting through a required fresh upload.
    ///
    /// Guards: only transitions from `.uploading`. If the scan was tombstoned
    /// (`.failed`) while a subset of its images were still in transit, this
    /// prevents completed uploads from resurrecting the scan into the inference
    /// pipeline with partial image data.
    @discardableResult
    func markScanAsStaged(
        scanId: String,
        r2Keys: [String]
    ) -> ScanStagingTransitionOutcome {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let scan: OfflineQueuedScan?
        do {
            scan = try modelContext.fetch(descriptor).first
        } catch {
            MerianLog.data.error(
                "markScanAsStaged: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return .retryRequired
        }
        guard let scan else {
            MerianLog.data.debug(
                "markScanAsStaged: scan missing scanId=\(scanId, privacy: .public)"
            )
            return .discarded
        }
        // Only advance from .uploading — do not resurrect tombstoned
        // (.failed) scans.
        guard scan.scanStateRaw == ScanQueueState.uploading.rawValue else {
            MerianLog.data.debug(
                "markScanAsStaged: state mismatch scanId=\(scanId, privacy: .public) state=\(scan.scanStateRaw, privacy: .public)"
            )
            switch scan.queueState {
            case .staged:
                guard scan.stagedR2Keys == r2Keys else {
                    MerianLog.data.error(
                        "markScanAsStaged: durable staged manifest mismatch scanId=\(scanId, privacy: .private)"
                    )
                    return .retryRequired
                }
                return .alreadyAdvanced
            case .inferencing:
                return .alreadyAdvanced
            case .pending:
                return .retryRequired
            case .externalImport, .failed:
                return .discarded
            case .uploading:
                // The raw-value guard above makes this branch unreachable.
                return .retryRequired
            }
        }
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let job: OfflineJobRecord?
        do {
            job = try modelContext.fetchOfflineJob(id: jobId)
        } catch {
            MerianLog.data.error(
                "markScanAsStaged: job fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return .retryRequired
        }

        let now = Date()
        if let job {
            reconcileMirroredInferenceState(scan: scan, job: job)
        }
        let preservesInferenceRecovery =
            OfflineQueueManager.isServerRetryableFailureCode(
                scan.queueLastErrorCode
            ) ||
            OfflineQueueManager.isServerRetryableFailureCode(
                job?.lastErrorCode
            ) ||
            OfflineQueueManager.isCompletedServerResultRecoveryCode(
                scan.queueLastErrorCode
            ) ||
            OfflineQueueManager.isCompletedServerResultRecoveryCode(
                job?.lastErrorCode
            )
        scan.stagedR2Keys = r2Keys
        scan.scanStateRaw = ScanQueueState.staged.rawValue
        if !preservesInferenceRecovery {
            scan.queueAttemptCount = 0
            scan.queueLastAttemptAt = nil
            scan.queueLastErrorCode = nil
            scan.queueLastErrorMessage = nil
        }
        scan.queueNextRetryAt = nil
        scan.queueLastHTTPStatus = nil
        scan.queueLastServerStatus = nil
        scan.queueLastServerStage = nil
        scan.queueLastServerRetryAfter = nil
        scan.queueNeedsAttention = false
        scan.queueUpdatedAt = now
        if let job {
            job.status = .running
            job.updatedAt = now
            job.nextRunAt = nil
            if !preservesInferenceRecovery {
                job.lastAttemptAt = nil
                job.attemptCount = 0
                job.lastErrorCode = nil
                job.lastErrorMessage = nil
            }
            job.lastHTTPStatus = nil
            job.serverStatus = nil
            job.serverStage = nil
            job.serverRetryAfter = nil
        }
        modelContext.insert(OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .staged,
            message: "Queued scan media staged for inference."
        ))
        do {
            try modelContext.save()
            MerianLog.data.debug(
                "markScanAsStaged: staged scanId=\(scanId, privacy: .public) keys=\(r2Keys.count, privacy: .public)"
            )
            return .staged
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "markScanAsStaged: save failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return .retryRequired
        }
    }

    // MARK: - Upload Reconciliation

    /// Marks scans in `.uploading` state that have no active URLSession task as
    /// `.pending`, so `syncPendingScans` re-dispatches them on the next cycle.
    ///
    /// `observedThrough` fences the URLSession snapshot: a scan claimed after
    /// that instant belongs to newer work and must not be reset by this pass.
    ///
    /// Callers capture `observedThrough` before enumerating URLSession tasks.
    /// The cutoff makes both cold-start and later safety-net passes safe if new
    /// work is claimed while the actor call is waiting to run.
    @discardableResult
    func reconcileOrphanedUploadingScans(
        activeScanIds: Set<String>,
        candidateScanIds: Set<String>? = nil,
        observedThrough: Date = Date()
    ) -> Bool {
        let uploadingRaw = ScanQueueState.uploading.rawValue
        let pendingRaw = ScanQueueState.pending.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.scanStateRaw == uploadingRaw && !$0.queueNeedsAttention
            }
        )
        let scans: [OfflineQueuedScan]
        do {
            scans = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.debug(
                "reconcileOrphanedUploadingScans: fetch failed: \(error, privacy: .private)"
            )
            return false
        }
        var changed = false
        var resetIds: [String] = []
        let now = Date()
        for scan in scans
        where scan.queueUpdatedAt <= observedThrough
            && !activeScanIds.contains(scan.id)
            && (candidateScanIds?.contains(scan.id) ?? true) {
            let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scan.id)
            let job: OfflineJobRecord?
            do {
                job = try modelContext.fetchOfflineJob(id: jobId)
            } catch {
                modelContext.rollback()
                MerianLog.data.error(
                    "reconcileOrphanedUploadingScans: job fetch failed for \(scan.id, privacy: .private): \(error, privacy: .private)"
                )
                return false
            }
            scan.scanStateRaw = pendingRaw
            scan.queueUpdatedAt = now
            if let job {
                job.status = scan.queueNextRetryAt.map {
                    $0 > now ? .waiting : .pending
                } ?? .pending
                job.updatedAt = now
                job.nextRunAt = scan.queueNextRetryAt
            }
            modelContext.insert(OfflineQueueEvent(
                jobId: jobId,
                scanId: scan.id,
                kind: .retryScheduled,
                message: "Recovered an upload claim without an active task."
            ))
            changed = true
            resetIds.append(scan.id)
        }
        if changed {
            do {
                try modelContext.save()
                MerianLog.data.debug(
                    "reconcileOrphanedUploadingScans: reset ids=\(resetIds.joined(separator: ","), privacy: .public)"
                )
            } catch {
                modelContext.rollback()
                MerianLog.data.error(
                    "reconcileOrphanedUploadingScans: save failed: \(error, privacy: .private)"
                )
                return false
            }
        }
        return changed
    }
}
