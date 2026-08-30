import CoreLocation
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private struct GalleryImportBudget: Sendable {
    let availableSlots: Int
    let canPerformScan: Bool
}

extension CaptureWorkspaceViewModel {
    // MARK: - User Intents

    func handlePhotoPickerSelection(newItems: [PhotosPickerItem], modelContext _: ModelContext) {
        guard !newItems.isEmpty else { return }

        let isPro = self.diContainer.revenueCatManager.canStartProScan
        let importBudget = prepareGalleryImportBudget(isPro: isPro)
        self.selectedPhotoItems.removeAll()

        guard importBudget.availableSlots > 0 else { return }

        guard importBudget.canPerformScan else {
            AppTelemetry.trackPaywallImpression()
            self.activeSheet = .paywall
            return
        }

        let itemsToProcess = Array(newItems.prefix(importBudget.availableSlots))

        DetachedWork.fireAndForget(
            priority: .userInitiated,
            category: .imagePreparation
        ) { [weak self, isPro, itemsToProcess] in
            guard let self = self else { return }

            var preparedImports: [PreparedStagedImage] = []
            preparedImports.reserveCapacity(itemsToProcess.count)

            for newItem in itemsToProcess {
                if Task.isCancelled { return }
                guard let wrapper = try? await newItem.loadTransferable(type: ImageFileWrapper.self) else { continue }
                let validUrl = wrapper.url

                // Scope the defer explicitly into an immediate do-block to guarantee memory unlocks natively per-loop
                do {
                    defer { try? FileManager.default.removeItem(at: validUrl) }

                    let historicalContext = await self.historicalContextSnapshot(for: newItem.itemIdentifier)
                    guard let preparedImport = try? await self.prepareFileBackedStagedImage(
                        fileURL: validUrl,
                        isPro: isPro,
                        historicalContext: historicalContext
                    ) else { continue }
                    preparedImports.append(preparedImport)
                }
            }

            guard !Task.isCancelled, !preparedImports.isEmpty else { return }
            await self.commitPreparedStagedImages(preparedImports, requiresCrop: true)
        }
    }

    func importPendingExternalImageIfPossible() {
        operationState.beginExternalImageImport { [weak self] in
            guard let self else { return }

            let importStore = self.dependencies.externalImageImports
            let hasTerminalFailure = await importStore.consumeTerminalFailure()
            let hasPendingImport = !(await importStore.pendingImports()).isEmpty
            if hasTerminalFailure || hasPendingImport {
                let didDismissSheet = self.prepareForExternalImageImportPresentation()
                if hasTerminalFailure {
                    self.offlineToastMessage = .error("Naturebook couldn’t import that photo.")
                }
                if hasPendingImport {
                    if didDismissSheet {
                        self.operationState
                            .deferExternalImageImportUntilSheetDismissal()
                        return
                    }
                    _ = await self.importNextPendingExternalImage()
                }
            }
        }
    }

    func importNextPendingExternalImage() async -> ExternalImageImportAttemptResult {
        let importStore = dependencies.externalImageImports
        guard let pendingImport = await importStore.pendingImports().first else {
            return .noPendingImport
        }

        let isPro = diContainer.revenueCatManager.canStartProScan
        let importBudget = prepareGalleryImportBudget(isPro: isPro)
        guard importBudget.availableSlots > 0 else {
            presentExternalImportSlotBlock(for: pendingImport)
            return .temporarilyBlocked
        }
        guard importBudget.canPerformScan else {
            presentExternalImportQuotaBlock(for: pendingImport)
            return .temporarilyBlocked
        }
        guard await requestImageImportEntryAdmission(
            prospectiveImageCount: 1
        ) else {
            if activeSheet == .paywall,
               operationState.markExternalImportPaywallIfNeeded(
                for: pendingImport.id
               ) {
                AppTelemetry.trackExternalImageImport(outcome: "blocked_quota")
            }
            return .temporarilyBlocked
        }
        guard let fileURL = await importStore.fileURL(for: pendingImport) else {
            await failExternalImageImport(pendingImport, outcome: "failed_missing_file")
            return .terminalFailure
        }

        do {
            let metadata = try await DetachedWork.value(
                priority: .userInitiated,
                category: .imagePreparation
            ) {
                ImportedImageMetadataExtractor.extract(from: fileURL)
            }
            let historicalContext = await historicalContextSnapshot(for: metadata)
            guard let preparedImport = try await prepareFileBackedStagedImage(
                fileURL: fileURL,
                isPro: isPro,
                historicalContext: historicalContext
            ) else {
                throw MediaPreparationError.unreadableImage
            }

            let refreshedIsPro = diContainer.revenueCatManager.canStartProScan
            let refreshedBudget = prepareGalleryImportBudget(isPro: refreshedIsPro)
            guard refreshedBudget.availableSlots > 0 else {
                presentExternalImportSlotBlock(for: pendingImport)
                return .temporarilyBlocked
            }
            guard refreshedBudget.canPerformScan else {
                presentExternalImportQuotaBlock(for: pendingImport)
                return .temporarilyBlocked
            }

            let committedCount = commitPreparedStagedImages([preparedImport], requiresCrop: true)
            guard committedCount == 1 else {
                presentExternalImportSlotBlock(for: pendingImport)
                return .temporarilyBlocked
            }

            await importStore.remove(pendingImport)
            operationState.clearExternalImportPresentationHistory(
                for: pendingImport.id
            )
            AppTelemetry.trackExternalImageImport(outcome: "staged")
            return .staged
        } catch is CancellationError {
            return .temporarilyBlocked
        } catch {
            MerianLog.data.error(
                "External image import preparation failed: \(error, privacy: .private)"
            )
            await failExternalImageImport(pendingImport, outcome: "failed_preparation")
            return .terminalFailure
        }
    }

    private func prepareFileBackedStagedImage(
        fileURL: URL,
        isPro: Bool,
        historicalContext: HistoricalEnvironmentContextSnapshot?
    ) async throws -> PreparedStagedImage? {
        let request = PreparedStagedImageRequest(
            fileURL: fileURL,
            isPro: isPro,
            historicalContext: historicalContext
        )
        return try await dependencies.prepareImage(request)
    }

    private func presentExternalImportSlotBlock(for pendingImport: PendingExternalImageImport) {
        if operationState.markExternalImportSlotBlockIfNeeded(
            for: pendingImport.id
        ) {
            AppTelemetry.trackExternalImageImport(outcome: "blocked_staging_capacity")
            offlineToastMessage = .warning("Finish your current capture to import the shared photo.")
        }
    }

    private func presentExternalImportQuotaBlock(for pendingImport: PendingExternalImageImport) {
        guard operationState.markExternalImportPaywallIfNeeded(
            for: pendingImport.id
        ) else { return }
        AppTelemetry.trackExternalImageImport(outcome: "blocked_quota")
        AppTelemetry.trackPaywallImpression()
        activeSheet = .paywall
    }

    private func failExternalImageImport(
        _ pendingImport: PendingExternalImageImport,
        outcome: String
    ) async {
        await dependencies.externalImageImports.remove(pendingImport)
        operationState.clearExternalImportPresentationHistory(
            for: pendingImport.id
        )
        AppTelemetry.trackExternalImageImport(outcome: outcome)
        triggerErrorFeedback()
        offlineToastMessage = .error("Naturebook couldn’t import that photo.")
    }

    private func prepareGalleryImportBudget(isPro: Bool) -> GalleryImportBudget {
        GalleryImportBudget(
            availableSlots: availableStagedCaptureSlots,
            canPerformScan: diContainer.usageManager.canPerformScan(isProActive: isPro)
        )
    }

    private func historicalContextSnapshot(for localIdentifier: String?) async -> HistoricalEnvironmentContextSnapshot? {
        guard let localIdentifier else { return nil }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        if let location = asset.location, let creationDate = asset.creationDate {
            let historicalContext = await diContainer.environmentContextManager.fetchHistoricalContext(
                location: location,
                date: creationDate
            )
            return HistoricalEnvironmentContextSnapshot(context: historicalContext)
        }

        if let creationDate = asset.creationDate {
            return HistoricalEnvironmentContextSnapshot(captureDate: creationDate)
        }

        return nil
    }

    private func historicalContextSnapshot(
        for metadata: ImportedImageMetadata
    ) async -> HistoricalEnvironmentContextSnapshot? {
        if let latitude = metadata.latitude,
           let longitude = metadata.longitude,
           let captureDate = metadata.captureDate {
            let historicalContext = await diContainer.environmentContextManager.fetchHistoricalContext(
                location: CLLocation(latitude: latitude, longitude: longitude),
                date: captureDate
            )
            return HistoricalEnvironmentContextSnapshot(context: historicalContext)
        }

        guard metadata.captureDate != nil || metadata.hasCoordinate else { return nil }
        return HistoricalEnvironmentContextSnapshot(
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            captureDate: metadata.captureDate
        )
    }

    @discardableResult
    func commitPreparedStagedImages(
        _ preparedImports: [PreparedStagedImage],
        requiresCrop: Bool = false
    ) -> Int {
        let availableSlots = availableStagedCaptureSlots
        guard availableSlots > 0 else { return 0 }

        var committedCount = 0

        for preparedImport in preparedImports.prefix(availableSlots) {
            let rawImage = UIImage(cgImage: preparedImport.previewCGImage.image)

            let identifiable = IdentifiableImage(
                image: rawImage,
                environmentContext: preparedImport.historicalContext?.makeEnvironmentContext(),
                isFromGallery: true
            )
            if requiresCrop {
                operationState.appendRequiredGalleryCrop(
                    imageID: identifiable.id
                )
            }
            stagedCapture.images.append(StagedImage(
                compressedData: preparedImport.compressedData,
                displayData: preparedImport.displayData,
                uiImage: rawImage,
                original: identifiable,
                focusRegion: preparedImport.focusRegion
            ))
            committedCount += 1
        }

        if committedCount > 0 {
            beginAutomaticStagedSubmissionIfEligible()
        }

        if requiresCrop, committedCount > 0 {
            presentNextRequiredGalleryCrop()
        }
        return committedCount
    }

}
