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
        let jobs: [OfflineJobRecord]
        do {
            jobs = try context.fetch(descriptor)
        } catch {
            MerianLog.data.error(
                "restoreFundingReservationsForCurrentAccount: fetch failed: \(error, privacy: .private)"
            )
            return
        }
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
            guard SharedMediaLegacyQueueAccess.permitsFresh(context.container, scanID: scanId) else {
                EntitlementManager.shared.restoreLegacyPotentialBlocker(scanId: scanId,
                    createdAt: job.createdAt, unresolvedOwnership: true)
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
    func reconcileDeferredFundingReservations(
        accountWorkLease providedLease: AccountBoundWorkLease? = nil
    ) async {
        let accountWorkLease: AccountBoundWorkLease
        let ownsAccountWorkLease: Bool
        if let providedLease {
            accountWorkLease = providedLease
            ownsAccountWorkLease = false
        } else {
            guard let accountId = EntitlementManager.shared.activeAccountID,
                  let lease = try? SupabaseManager.shared
                  .beginUnownedAccountBoundWork(expectedUserID: accountId)
            else {
                return
            }
            accountWorkLease = lease
            ownsAccountWorkLease = true
        }
        defer {
            if ownsAccountWorkLease {
                SupabaseManager.shared.finishAccountBoundWork(
                    accountWorkLease
                )
            }
        }
        await reconcileLegacyFunding(
            isCurrent: { self.fundingAccountWorkIsCurrent(accountWorkLease) },
            lookup: { try await MerianNetworkClient.shared.checkScanStatuses($0) },
            refresh: { await EntitlementManager.shared.refreshCurrentSession() }
        )
    }

    /// Owning-layer dependency seam; the production wrapper retains and checks the Auth lease.
    func reconcileLegacyFunding(
        isCurrent: () -> Bool,
        lookup: ([String: Int]) async throws -> [String: ScanStatusResponse],
        refresh: () async -> Bool
    ) async {
        guard isCurrent(), let account = EntitlementManager.shared.activeAccountID else { return }
        func current() -> Bool {
            !Task.isCancelled && isCurrent() && EntitlementManager.shared.activeAccountID == account
        }
        restoreFundingReservationsForCurrentAccount()
        let beforeLookup = legacyFundingIdentities()
        let blockers = Array(EntitlementManager.shared.fundingBlockerScanIds.filter {
            beforeLookup[$0] != nil
        }.prefix(50))
        if !blockers.isEmpty {
            let requirements = Dictionary(
                uniqueKeysWithValues: blockers.map { ($0, 0) }
            )
            let responses: [String: ScanStatusResponse]
            do {
                responses = try await lookup(requirements)
            } catch {
                MerianLog.data.debug(
                    "Deferred funding-state lookup failed: \(error.localizedDescription, privacy: .private)"
                )
                return
            }
            guard current() else {
                return
            }
            for blocker in blockers {
                guard let original = beforeLookup[blocker],
                      legacyFundingIdentities()[blocker] == original,
                      let response = responses[blocker] else { continue }
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

        if EntitlementManager.shared.needsLegacyFundingRefresh(
            eligibleLegacyScanIDs: Set(legacyFundingIdentities().keys)
        ) {
            let beforeRefresh = legacyFundingIdentities()
            let refreshed = await refresh()
            guard current() else {
                return
            }
            if refreshed {
                EntitlementManager.shared
                    .confirmTerminalSettlementsAfterEntitlementRefresh(eligibleLegacyScanIDs: Set(
                        legacyFundingIdentities().compactMap { id, proof in beforeRefresh[id] == proof ? id : nil }
                    ))
            }
        }

        let previous = EntitlementManager.shared.deferredFundingReservations
        let eligible = Set(legacyFundingIdentities().keys)
        let changes = EntitlementManager.shared.resolveDeferredFunding(eligibleLegacyScanIDs: eligible)
        guard current() else { return }
        guard !changes.isEmpty, let context = modelContext else { return }
        do {
            for reservation in changes {
                guard SharedMediaLegacyQueueAccess.permitsFresh(context.container, scanID: reservation.scanId),
                      let original = previous.first(where: { $0.scanId == reservation.scanId }),
                      let job = try context.fetchOfflineJob(
                    id: Self.scanIngestionJobId(scanId: reservation.scanId)
                ), OfflineScanJobMetadataContract.funding(in: job.metadataJSON) == original else {
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

    /// Compare the exact logical job/funding generation across every suspension.
    /// A missing job cannot settle a reservation; accepted result settlement has its own fence.
    private func legacyFundingIdentities() -> [String: SharedMediaLegacyQueueAccess.FundingIdentity] {
        guard let container = modelContext?.container else { return [:] }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var result: [String: SharedMediaLegacyQueueAccess.FundingIdentity] = [:]
        for id in EntitlementManager.shared.fundingCandidateScanIDs {
            result[id] = try? SharedMediaLegacyQueueAccess.fundingIdentity(context, scanID: id,
                reservation: EntitlementManager.shared.fundingReservation(scanId: id))
        }
        return result
    }

    private func fundingAccountWorkIsCurrent(
        _ lease: AccountBoundWorkLease
    ) -> Bool {
        !Task.isCancelled &&
            !SupabaseManager.shared.isAuthTransitionInProgress &&
            SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(lease) &&
            EntitlementManager.shared.activeAccountID == lease.session.userID
    }

    private func localFundingBlockerIsTerminal(scanId: String) -> Bool {
        guard let context = modelContext,
              SharedMediaLegacyQueueAccess.permitsFresh(context.container, scanID: scanId) else { return false }
        let jobId = Self.scanIngestionJobId(scanId: scanId)
        let job: OfflineJobRecord?
        do {
            job = try context.fetchOfflineJob(id: jobId)
        } catch {
            MerianLog.data.error(
                "Could not validate local funding terminal state for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        guard let job else {
            return true
        }
        return job.status == .complete || job.status == .cancelled
    }

    @discardableResult
    func releaseFundingForProvenPredispatchFailure(scanId: String) -> Bool {
        guard let context = modelContext,
              SharedMediaLegacyQueueAccess.permitsFresh(context.container, scanID: scanId) else { return false }
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
