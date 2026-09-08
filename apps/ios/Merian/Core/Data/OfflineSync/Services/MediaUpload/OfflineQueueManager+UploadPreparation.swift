import Foundation

extension OfflineQueueManager {
    // MARK: - Upload Helpers

    nonisolated func currentMediaStagingUserId() async -> String? {
        await MainActor.run {
            let manager = SupabaseManager.shared
            guard let lease = try? manager.beginUnownedAccountBoundWork()
            else { return nil }
            defer { manager.finishAccountBoundWork(lease) }
            return lease.session.userID.uuidString
        }
    }

    nonisolated func prepareUploadItems(
        from scans: [PendingScanPayload],
        userId: String
    ) -> MediaStagingPreparation {
        var uploadItems: [ScanUploadItem] = []
        var uploadFiles: [StagingUploadFile] = []
        var rejectedScanIds: [String] = []

        for scan in scans {
            let scanItems = MediaStagingContract.uploadItems(for: scan, userId: userId)
            do {
                try MediaStagingContract.validateUploadBudget(scanItems)
                let scanUploadFiles = try MediaStagingContract.uploadFiles(for: scanItems)
                uploadItems.append(contentsOf: scanItems)
                uploadFiles.append(contentsOf: scanUploadFiles)
            } catch {
                MerianLog.data.error("prepareUploadItems: rejecting staged media for \(scan.id, privacy: .private): \(error, privacy: .private)")
                rejectedScanIds.append(scan.id)
            }
        }

        return MediaStagingPreparation(
            uploadItems: uploadItems,
            uploadFiles: uploadFiles,
            rejectedScanIds: rejectedScanIds
        )
    }

    nonisolated func selectUploadBatch(
        from scans: [PendingScanPayload]
    ) -> [PendingScanPayload] {
        let maxPresignedURLsPerRequest = MediaStagingContract.maxUploadItemsPerRequest
        var selected: [PendingScanPayload] = []
        selected.reserveCapacity(MerianConfig.uploadBatchSize)
        var uploadItemCount = 0

        for scan in scans {
            guard selected.count < MerianConfig.uploadBatchSize else { break }
            let scanUploadCount = scan.localUploadPaths.count
            guard scanUploadCount > 0 else { continue }
            if uploadItemCount + scanUploadCount > maxPresignedURLsPerRequest {
                // Let the normal media-contract validator quarantine one
                // oversized head row, but do not let a later non-fitting row
                // prevent still-smaller work from filling the batch.
                if selected.isEmpty {
                    selected.append(scan)
                    break
                }
                continue
            }
            selected.append(scan)
            uploadItemCount += scanUploadCount
            if uploadItemCount >= maxPresignedURLsPerRequest {
                break
            }
        }

        return selected
    }
}
