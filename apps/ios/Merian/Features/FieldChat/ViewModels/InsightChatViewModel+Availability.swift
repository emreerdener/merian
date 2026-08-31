import Foundation

extension InsightChatViewModel {
    func prepareForPresentation(scanId: String) async -> Bool {
        await prepareForPresentation(scanId: scanId) { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performPresentationPreparation(scanId: scanId)
        }
    }

    func prepareForPresentation(
        scanId: String,
        using preparation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        guard !isUnavailable(for: scanId) else {
            errorMessage = source.unavailableMessage
            return false
        }
        guard !isOffline else {
            if operations.hasLoadedCurrentSubject, isLoadedSubject(scanId) {
                return true
            }
            errorMessage = "Connect to use Field chat."
            return false
        }

        isCheckingAvailability = true
        let canPresent = await operations.prepare(
            subjectId: scanId,
            operation: preparation
        )
        isCheckingAvailability = operations.isPreparing
        return canPresent
    }

    private func performPresentationPreparation(scanId: String) async -> Bool {
        if source != .insightScan {
            let generation = activateSubject(scanId: scanId)
            await loadCurrentSubject(scanId: scanId, generation: generation)
            return isCurrentSubject(scanId: scanId, generation: generation) &&
                errorMessage == nil &&
                !isUnavailable(for: scanId)
        }

        do {
            let status = try await dependencies.checkOwnedScanStatus(scanId)
            guard operations.isCurrentPreparation(subjectId: scanId),
                  !Task.isCancelled else {
                return false
            }
            return applyOwnedScanReadinessStatus(status, scanId: scanId)
        } catch {
            guard operations.isCurrentPreparation(subjectId: scanId),
                  !Task.isCancelled else {
                return false
            }
            handle(error, scanId: scanId)
            return false
        }
    }

    func applyOwnedScanReadinessStatus(_ status: String, scanId: String) -> Bool {
        guard status == "found" else {
            errorMessage = Self.stillSyncingMessage
            return false
        }

        markAvailable(scanId: scanId)
        return true
    }

    func markUnavailable(scanId: String, message: String? = nil) {
        unavailableScanId = scanId
        errorMessage = message ?? source.unavailableMessage
    }

    func markAvailable(scanId: String) {
        if unavailableScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame {
            unavailableScanId = nil
        }
        errorMessage = nil
    }

}
