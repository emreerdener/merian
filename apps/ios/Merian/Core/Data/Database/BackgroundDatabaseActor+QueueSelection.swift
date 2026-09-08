import Foundation
import SwiftData

extension BackgroundDatabaseActor {
    private struct FundingPrioritizedPendingScan {
        let payload: PendingScanPayload
        let priority: Int
        let order: Int
    }

    // MARK: - Pending Scan Selection

    /// Returns up to `limit` runnable-media `.pending` (state 0)
    /// `OfflineQueuedScan` records sorted oldest-first, plus at most `limit`
    /// media-less candidates for state-bound quarantine.
    ///
    /// Scans in `.uploading`, `.staged`, `.inferencing`, or `.failed` states
    /// are excluded. The caller also supplies process-local live-upload
    /// deferrals and current video-network eligibility so a page full of
    /// locally blocked rows cannot hide newer work.
    func fetchPendingScans(
        limit: Int,
        excludingScanIds: Set<String> = [],
        allowsVideoUploads: Bool = true,
        forcedVideoUploadScanIds: Set<String> = []
    ) -> [PendingScanPayload] {
        guard limit > 0 else { return [] }
        let pendingRaw = ScanQueueState.pending.rawValue
        let now = Date()
        let pageSize = max(50, limit * 3)
        var fetchOffset = 0
        var inspectedCount = 0
        var emptyCandidateCount = 0
        var mediaCandidates: [FundingPrioritizedPendingScan] = []
        var emptyCandidates: [PendingScanPayload] = []
        var candidateOrder = 0

        let jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate {
                $0.kindRaw == "scanIngestion"
            }
        )
        let fundingJobs: [OfflineJobRecord]
        do {
            fundingJobs = try modelContext.fetch(jobDescriptor)
        } catch {
            MerianLog.data.error(
                "fetchPendingScans: funding fetch failed error=\(error, privacy: .private)"
            )
            return []
        }
        let fundingByScanId: [String: ScanFundingSource] =
            fundingJobs.reduce(into: [:]) { result, job in
                guard let scanId = job.subjectId?.lowercased(),
                      let funding = OfflineScanJobMetadataContract.funding(
                          in: job.metadataJSON
                      ) else {
                    return
                }
                result[scanId] = funding.source
            }

        // Retry deadlines are filtered in memory for SwiftData compatibility.
        // Page through the complete runnable-state set so an old page full of
        // delayed, locally blocked, or media-less rows cannot permanently hide
        // newer work. Media-less candidates are bounded independently so they
        // can be quarantined without consuming the runnable-media limit.
        while true {
            var descriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate {
                    $0.scanStateRaw == pendingRaw
                        && !$0.queueNeedsAttention
                },
                sortBy: [
                    SortDescriptor(\OfflineQueuedScan.timestamp),
                    SortDescriptor(\OfflineQueuedScan.id)
                ]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = fetchOffset

            let page: [OfflineQueuedScan]
            do {
                page = try modelContext.fetch(descriptor)
            } catch {
                MerianLog.data.error(
                    "fetchPendingScans: fetch failed offset=\(fetchOffset, privacy: .public) error=\(error, privacy: .private)"
                )
                return []
            }
            guard !page.isEmpty else { break }

            inspectedCount += page.count
            for scan in page {
                guard scan.queueNextRetryAt == nil
                        || (scan.queueNextRetryAt ?? now) <= now,
                      !excludingScanIds.contains(scan.id) else {
                    continue
                }
                let snapshot = scan.capturedMediaSnapshot
                guard allowsVideoUploads
                        || snapshot.videoPaths.isEmpty
                        || forcedVideoUploadScanIds.contains(scan.id) else {
                    continue
                }
                let fundingSource = fundingByScanId[scan.id.lowercased()]
                guard fundingSource != .deferredFlash else { continue }
                let payload = PendingScanPayload(
                    id: scan.id,
                    localImagePaths:
                        scan.inferenceImagePaths?.isEmpty == false
                        ? scan.inferenceImagePaths ?? []
                        : snapshot.thumbnailImagePaths,
                    localAudioPaths: snapshot.audioPaths,
                    localVideoPaths: snapshot.videoPaths
                )
                if payload.localUploadPaths.isEmpty {
                    if emptyCandidateCount < limit {
                        emptyCandidates.append(payload)
                        emptyCandidateCount += 1
                    }
                    continue
                }
                let priority: Int
                switch fundingSource {
                case .complimentaryPro?, nil: priority = 0
                case .paidPro?: priority = 1
                case .immediateFlash?: priority = 2
                case .deferredFlash?: priority = 3
                }
                mediaCandidates.append(FundingPrioritizedPendingScan(
                    payload: payload,
                    priority: priority,
                    order: candidateOrder
                ))
                candidateOrder += 1
            }
            fetchOffset += page.count
            if page.count < pageSize {
                break
            }
        }

        MerianLog.data.debug(
            "fetchPendingScans: inspected \(inspectedCount, privacy: .public) eligible pending scans runnableMedia=\(mediaCandidates.count, privacy: .public) emptyCandidates=\(emptyCandidateCount, privacy: .public)"
        )
        let selectedMedia = mediaCandidates.sorted { lhs, rhs in
            lhs.priority == rhs.priority
                ? lhs.order < rhs.order
                : lhs.priority < rhs.priority
        }.prefix(limit).map(\.payload)
        return selectedMedia + emptyCandidates
    }

    // MARK: - Empty-Media Quarantine

    /// Moves only still-pending rows with no uploadable local media to a
    /// visible needs-attention state. The state/media recheck and mutation
    /// share this actor context, so a stale payload cannot tombstone work that
    /// another path already advanced.
    func quarantineEmptyPendingScans(
        scanIds: [String]
    ) -> Set<String> {
        guard !scanIds.isEmpty else { return [] }
        let pendingRaw = ScanQueueState.pending.rawValue
        let failedRaw = ScanQueueState.failed.rawValue
        var quarantined = Set<String>()

        for index in stride(from: 0, to: scanIds.count, by: 50) {
            let end = min(index + 50, scanIds.count)
            let chunk = Array(scanIds[index..<end])
            let descriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate {
                    chunk.contains($0.id)
                        && $0.scanStateRaw == pendingRaw
                        && !$0.queueNeedsAttention
                }
            )
            let scans: [OfflineQueuedScan]
            do {
                scans = try modelContext.fetch(descriptor)
            } catch {
                modelContext.rollback()
                MerianLog.data.error(
                    "quarantineEmptyPendingScans: fetch failed error=\(error, privacy: .private)"
                )
                return []
            }

            let now = Date()
            for scan in scans {
                let snapshot = scan.capturedMediaSnapshot
                let imagePaths = scan.inferenceImagePaths?.isEmpty == false
                    ? scan.inferenceImagePaths ?? []
                    : snapshot.thumbnailImagePaths
                guard imagePaths.isEmpty,
                      snapshot.audioPaths.isEmpty,
                      snapshot.videoPaths.isEmpty else {
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
                        "quarantineEmptyPendingScans: job fetch failed error=\(error, privacy: .private)"
                    )
                    return []
                }
                scan.scanStateRaw = failedRaw
                scan.queueLastAttemptAt = now
                scan.queueNextRetryAt = nil
                scan.queueLastErrorCode = "queued_media_missing"
                scan.queueLastErrorMessage =
                    "The queued scan has no local media to upload."
                scan.queueNeedsAttention = true
                scan.queueUpdatedAt = now
                if let job {
                    job.status = .needsAttention
                    job.updatedAt = now
                    job.nextRunAt = nil
                    job.lastErrorCode = "queued_media_missing"
                    job.lastErrorMessage =
                        "The queued scan has no local media to upload."
                }
                modelContext.insert(OfflineQueueEvent(
                    jobId: jobId,
                    scanId: scan.id,
                    kind: .needsAttention,
                    message: "Queued scan has no local upload media.",
                    errorCode: "queued_media_missing"
                ))
                quarantined.insert(scan.id)
            }
        }

        guard !quarantined.isEmpty else { return [] }
        do {
            try modelContext.save()
            return quarantined
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "quarantineEmptyPendingScans: save failed error=\(error, privacy: .private)"
            )
            return []
        }
    }
}
