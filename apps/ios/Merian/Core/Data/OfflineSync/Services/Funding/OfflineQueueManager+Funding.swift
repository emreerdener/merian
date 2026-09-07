import Foundation
import SwiftData

// MARK: - Queue Funding

extension OfflineQueueManager {

    /// Restores durable admission decisions after relaunch. Active jobs from a
    /// pre-protocol-3 build have no funding property and are conservatively
    /// treated as potential complimentary blockers until server state resolves.
    func restoreFundingReservationsForCurrentAccount() {
        guard EntitlementManager.shared.activeAccountID != nil,
              let context = modelContext else {
            return
        }
        let descriptor = FetchDescriptor<OfflineJobRecord>()
        guard let jobs = try? context.fetch(descriptor) else { return }
        let nonterminal: Set<String> = [
            OfflineJobStatus.pending.rawValue,
            OfflineJobStatus.running.rawValue,
            OfflineJobStatus.waiting.rawValue,
            OfflineJobStatus.needsAttention.rawValue
        ]
        for job in jobs where
            job.kindRaw == OfflineJobKind.scanIngestion.rawValue &&
            nonterminal.contains(job.statusRaw) {
            guard let scanId = job.subjectId?.lowercased(), !scanId.isEmpty else {
                continue
            }
            if let funding = OfflineScanJobMetadataContract.funding(
                in: job.metadataJSON
            ), funding.scanId.caseInsensitiveCompare(scanId) == .orderedSame {
                EntitlementManager.shared.restoreFundingReservation(funding)
            } else if !OfflineScanJobMetadataContract.fundingWasReleased(
                in: job.metadataJSON
            ) {
                EntitlementManager.shared.restoreLegacyPotentialBlocker(
                    scanId: scanId,
                    createdAt: job.createdAt
                )
            }
        }
    }

    /// Performs one bulk status lookup for all deferred blockers in a scheduler
    /// pass, then persists any safe reclassification before dispatch begins.
    func reconcileDeferredFundingReservations() async {
        restoreFundingReservationsForCurrentAccount()
        let blockers = Array(
            EntitlementManager.shared.fundingBlockerScanIds.prefix(50)
        )
        if !blockers.isEmpty {
            let requirements = Dictionary(
                uniqueKeysWithValues: blockers.map { ($0, 0) }
            )
            let responses: [String: ScanStatusResponse]
            do {
                responses = try await MerianNetworkClient.shared.checkScanStatuses(
                    requirements
                )
            } catch {
                MerianLog.data.debug(
                    "Deferred funding-state lookup failed: \(error.localizedDescription, privacy: .private)"
                )
                return
            }
            for blocker in blockers {
                guard let response = responses[blocker] else { continue }
                EntitlementManager.shared.applyComplimentaryState(
                    response.complimentaryState,
                    scanId: blocker,
                    terminalized: response.isFound ||
                        localFundingBlockerIsTerminal(scanId: blocker) ||
                        response.jobStatus == .failed ||
                        response.jobStatus == .complete
                )
            }
        }

        if EntitlementManager.shared.hasReleasedDeferredBlocker ||
            EntitlementManager.shared.needsTerminalSettlementEntitlementRefresh {
            let refreshed = await EntitlementManager.shared.refreshCurrentSession()
            if refreshed {
                EntitlementManager.shared
                    .confirmTerminalSettlementsAfterEntitlementRefresh()
            }
        }

        let previous = EntitlementManager.shared.deferredFundingReservations
        let changes = EntitlementManager.shared.resolveDeferredFunding()
        guard !changes.isEmpty, let context = modelContext else { return }
        do {
            for reservation in changes {
                guard let job = try context.fetchOfflineJob(
                    id: Self.scanIngestionJobId(scanId: reservation.scanId)
                ) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                job.metadataJSON = OfflineScanJobMetadataContract.settingFunding(
                    reservation,
                    in: job.metadataJSON
                )
                job.updatedAt = Date()
            }
            try context.save()
            // Deferred Flash admissions reserve the advisory local Flash
            // meter. Once a blocker is authoritatively reclassified and
            // durably persisted as paid or complimentary Pro, return that
            // meter; final server-plan reconciliation will consume it again if
            // a cross-device race ultimately selects Flash.
            for reservation in changes
            where reservation.source == .complimentaryPro ||
                reservation.source == .paidPro {
                UsageManager.shared.refundScan(scanId: reservation.scanId)
            }
        } catch {
            context.rollback()
            for reservation in previous {
                EntitlementManager.shared.restoreFundingReservation(reservation)
            }
            MerianLog.data.error(
                "Deferred funding reclassification could not be persisted: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func localFundingBlockerIsTerminal(scanId: String) -> Bool {
        guard let context = modelContext else { return false }
        let jobId = Self.scanIngestionJobId(scanId: scanId)
        guard let job = try? context.fetchOfflineJob(id: jobId) else {
            return true
        }
        return job.status == .complete || job.status == .cancelled
    }

    @discardableResult
    func releaseFundingForProvenPredispatchFailure(scanId: String) -> Bool {
        guard let context = modelContext else { return false }
        let job: OfflineJobRecord?
        do {
            job = try context.fetchOfflineJob(
                id: Self.scanIngestionJobId(scanId: scanId)
            )
        } catch {
            MerianLog.data.error(
                "Could not persist local funding release for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }

        if let job {
            guard let releasedMetadata = OfflineScanJobMetadataContract
                .markingFundingReleased(in: job.metadataJSON) else {
                return false
            }
            job.metadataJSON = releasedMetadata
            job.updatedAt = Date()
            do {
                try context.save()
            } catch {
                context.rollback()
                MerianLog.data.error(
                    "Could not save local funding release for \(scanId, privacy: .private): \(error, privacy: .private)"
                )
                return false
            }
        }

        if let funding = EntitlementManager.shared.fundingReservation(
            scanId: scanId
        ), funding.source == .immediateFlash ||
            funding.source == .deferredFlash {
            UsageManager.shared.refundScan(scanId: funding.scanId)
        }
        EntitlementManager.shared.releaseFundingAfterProvenLocalFailure(
            scanId: scanId
        )
        return true
    }
}
