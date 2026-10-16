import CoreLocation
import Foundation
import PhotosUI
import SwiftUI

/// Explicit local qualification composition. This is never provided by `.live`.
@MainActor
final class CapturePhotoOriginalPreparationAccess {
    let owner: PhotoOriginalPreparationOwner
    private(set) var packageID = UUID()
    private(set) var generation = UUID()
    private(set) var revision: Int64 = 0
    private(set) var hasUnsavedChanges = false
    private(set) var receipt: PhotoPreparationReceipt?
    private var nextOrdinal: Int64 = 0
    private(set) var needsRecovery = false

    init(owner: PhotoOriginalPreparationOwner) { self.owner = owner }

    func markUnsaved() { hasUnsavedChanges = true }

    func acquire(source: String, sourceByteLiability: Int64 = 0, sourceIdentity: String? = nil,
                 releaseSource: (@Sendable () async throws -> Void)? = nil,
                 load: @escaping @Sendable () async throws -> Data,
                 prepare: @escaping @Sendable (URL) async throws -> PreparedStagedImage?) async throws -> StagedImage {
        guard receipt == nil, !needsRecovery, nextOrdinal < 2 else { throw PhotoPreparationFailure.sizeLimit }
        hasUnsavedChanges = true
        let reference = try await owner.acquire(packageID: packageID, draftGeneration: generation,
            ordinal: nextOrdinal, sourceKind: source, sourceByteLiability: sourceByteLiability, sourceIdentity: sourceIdentity, load: load)
        nextOrdinal += 1
        if let sourceIdentity, let releaseSource {
            try await owner.releaseSource(reference, identity: sourceIdentity, releaseAndConfirm: releaseSource)
        }
        guard let prepared = try await owner.prepare(reference, using: prepare) else {
            throw PhotoPreparationFailure.invalidMedia
        }
        try await owner.updateDerivatives(for: reference, ai: prepared.compressedData, display: prepared.displayData)
        try await refreshRevision()
        let image = UIImage(cgImage: prepared.previewCGImage.image)
        return StagedImage(compressedData: prepared.compressedData, displayData: prepared.displayData,
            uiImage: image, original: IdentifiableImage(image: image,
                environmentContext: prepared.historicalContext?.makeEnvironmentContext(), isFromGallery: source != "camera"),
            focusRegion: prepared.focusRegion, photoOriginalReference: reference)
    }

    func persist(images: [StagedImage], contexts: [ObservationContext]) async throws {
        hasUnsavedChanges = true
        guard receipt == nil, !needsRecovery else { throw PhotoPreparationFailure.immutablePackage }
        for image in images {
            guard let reference = image.photoOriginalReference, reference.packageID == packageID else {
                throw PhotoPreparationFailure.missingMedia
            }
            try await owner.updateDerivatives(for: reference, ai: image.compressedData, display: image.displayData)
        }
        try await refreshRevision()
        let presentation = try images.map { image -> PhotoPreparationImagePresentation in
            guard let reference = image.photoOriginalReference else { throw PhotoPreparationFailure.missingMedia }
            let environment = image.original.environmentContext
            return PhotoPreparationImagePresentation(referenceID: reference.referenceID, addedAt: image.addedAt,
                isFromGallery: image.original.isFromGallery, cropQuarterTurns: image.original.lastCropQuarterTurns,
                cropScale: image.original.lastCropScale, cropOffsetX: image.original.lastCropOffset.width,
                cropOffsetY: image.original.lastCropOffset.height, focus: image.focusRegion,
                latitude: environment?.location?.coordinate.latitude, longitude: environment?.location?.coordinate.longitude,
                locationName: environment?.locationName, weatherCondition: environment?.weatherCondition,
                weatherTemperature: environment?.weatherTemperature, captureDate: environment?.captureDate)
        }
        revision = try await owner.saveContexts(packageID: packageID, revision: revision, contexts: contexts, presentation: presentation)
        hasUnsavedChanges = false
    }

    func freeze(images: [StagedImage], contexts: [ObservationContext]) async throws -> PhotoPreparationReceipt {
        guard !hasUnsavedChanges, receipt == nil, !images.isEmpty,
              images.allSatisfy({ $0.photoOriginalReference != nil }) else { throw PhotoPreparationFailure.missingMedia }
        let snapshot = PhotoPreparationSnapshot(originals: images.compactMap(\.photoOriginalReference),
            expectedPackageRevision: revision, supportingContexts: contexts)
        let saved = try await owner.freeze(snapshot)
        receipt = saved
        return saved
    }

    func remove(_ image: StagedImage) async throws {
        guard let reference = image.photoOriginalReference else { throw PhotoPreparationFailure.missingMedia }
        hasUnsavedChanges = true
        try await owner.remove(reference)
        nextOrdinal = max(0, nextOrdinal - 1)
        try await refreshRevision()
    }

    func discard(returningSourcesTo inbox: ExternalImageImportStore? = nil) async throws {
        let drafts = try await owner.recover()
        if let draft = drafts.first(where: { $0.packageID == packageID }) {
            for identity in draft.retainedSourceIdentities {
                guard let inbox else { throw PhotoPreparationFailure.cleanupPending }
                try await owner.returnSource(packageID: packageID, identity: identity) {
                    guard let item = await inbox.pendingImports().first(where: { $0.id.uuidString == identity }),
                          let url = await inbox.fileURL(for: item) else { throw PhotoPreparationFailure.cleanupPending }
                    try PhotoOriginalPickerTransfer.confirmRetained(url)
                    guard await inbox.pendingImports().contains(item) else { throw PhotoPreparationFailure.cleanupPending }
                }
            }
            try await owner.discard(packageID: packageID, revision: draft.revision)
        }
        packageID = UUID(); generation = UUID(); revision = 0; nextOrdinal = 0
        hasUnsavedChanges = false; receipt = nil; needsRecovery = false
    }

    /// Reopens committed bytes without regenerating or substituting AI inputs.
    /// A partial acquisition stays visible through needsRecovery and blocks edits.
    func restore(packageID: UUID, prepareOriginal: @escaping @Sendable (URL) async throws -> PreparedStagedImage?) async throws
        -> (images: [StagedImage], contexts: [ObservationContext]) {
        guard let draft = try await owner.recover().first(where: { $0.packageID == packageID }) else {
            throw PhotoPreparationFailure.missingMedia
        }
        self.packageID = draft.packageID; generation = draft.draftGeneration; revision = draft.revision
        nextOrdinal = Int64(draft.originals.count)
        needsRecovery = draft.needsAttention
        receipt = draft.phase == "preparedHeld" ? PhotoPreparationReceipt(packageID: packageID, revision: revision) : nil
        var images: [StagedImage] = []
        for handle in draft.originals {
            do {
                guard let metadata = draft.presentation.first(where: { $0.referenceID == handle.referenceID }),
                      let prepared = try await owner.prepare(handle, using: prepareOriginal) else {
                    needsRecovery = true
                    continue
                }
                let (ai, display) = try await owner.derivativeData(handle)
                guard let thumbnail = ImageDownsampler.downsample(data: display, maxSize: 512) else {
                    throw PhotoPreparationFailure.invalidMedia
                }
                let location: CLLocation?
                if let latitude = metadata.latitude, let longitude = metadata.longitude {
                    location = CLLocation(latitude: latitude, longitude: longitude)
                } else { location = nil }
                var original = IdentifiableImage(image: UIImage(cgImage: prepared.previewCGImage.image),
                    environmentContext: EnvironmentContext(location: location, locationName: metadata.locationName,
                        weatherCondition: metadata.weatherCondition, weatherTemperature: metadata.weatherTemperature,
                        captureDate: metadata.captureDate), isFromGallery: metadata.isFromGallery)
                original.lastCropScale = metadata.cropScale
                original.lastCropOffset = CGSize(width: metadata.cropOffsetX, height: metadata.cropOffsetY)
                original.lastCropQuarterTurns = metadata.cropQuarterTurns
                images.append(StagedImage(compressedData: ai, displayData: display, uiImage: UIImage(cgImage: thumbnail),
                    original: original, focusRegion: metadata.focus, addedAt: metadata.addedAt, photoOriginalReference: handle))
            } catch { needsRecovery = true }
        }
        hasUnsavedChanges = needsRecovery
        return (images, draft.contexts)
    }

    private func refreshRevision() async throws {
        guard let draft = try await owner.recover().first(where: { $0.packageID == packageID }), !draft.needsAttention else {
            throw PhotoPreparationFailure.cleanupPending
        }
        revision = draft.revision
    }
}

extension CaptureWorkspaceViewModel {
    func restorePhotoPreparationDraft(packageID: UUID) async {
        guard let access = dependencies.photoOriginalPreparation, stagedCapture.images.isEmpty,
              !isDraftMutationLocked, let operation = beginDraftOperation() else { return }
        isCheckingScanAdmission = true
        var succeeded = false
        defer { isCheckingScanAdmission = false; completeDraftOperation(operation, succeeded: succeeded, preservingRestoredContext: true) }
        let prepare = dependencies.prepareImage
        let isPro = dependencies.scan.canStartProScan()
        do {
            let restored = try await access.restore(packageID: packageID) { url in
                try await prepare(PreparedStagedImageRequest(fileURL: url, isPro: isPro, historicalContext: nil))
            }
            guard draftSession.contains(operation), isDraftAccountCurrent else { return }
            stagedCapture.images = restored.images
            succeeded = true
            stagedCapture.observationContexts = restored.contexts.map { StagedObservationContext(context: $0) }
            descriptionDraft = restored.contexts.first ?? ObservationContext()
            if access.needsRecovery {
                offlineToastMessage = .error("The last saved draft needs attention. Original ownership is retained; submission is blocked.")
            }
        } catch { offlineToastMessage = .error("The saved draft could not be reopened. Its files remain protected.") }
    }

    func schedulePhotoPreparationPersistence() {
        guard let access = dependencies.photoOriginalPreparation else { return }
        access.markUnsaved()
        guard !stagedCapture.images.isEmpty else { return }
        let operation = draftSession.beginRelatedWork()
        Task { @MainActor in
            let success = await persistPhotoPreparationDraft()
            completeDraftOperation(operation, succeeded: success)
        }
    }

    func importPhotoPreparationInbox(_ item: PendingExternalImageImport, access: CapturePhotoOriginalPreparationAccess) async -> ExternalImageImportAttemptResult {
        guard !isDraftMutationLocked, !dependencies.submission.admission.isLibraryAccessBlocked(),
              let operation = beginDraftOperation() else { return .temporarilyBlocked }
        var succeeded = false
        defer { completeDraftOperation(operation, succeeded: succeeded) }
        let imports = dependencies.externalImageImports
        guard let url = await imports.fileURL(for: item) else { return .temporarilyBlocked }
        do {
            let prepare = dependencies.prepareImage
            let isPro = dependencies.scan.canStartProScan()
            // Charge the existing app-owned inbox file conservatively at its cap
            // until the transfer returns ownership to the inbox or commits.
            let sourceBytes = try PhotoOriginalPickerTransfer.validateInboxSize(url)
            let image = try await access.acquire(source: "inbox", sourceByteLiability: sourceBytes,
                sourceIdentity: item.id.uuidString,
                releaseSource: {
                    await imports.remove(item)
                    try PhotoOriginalPickerTransfer.confirmReleased(url)
                }, load: { try PhotoOriginalPickerTransfer.readInbox(url) }, prepare: { original in
                    let metadata = try await DetachedWork.value(priority: .userInitiated, category: .imagePreparation) {
                        ImportedImageMetadataExtractor.extract(from: original)
                    }
                    let context = await self.historicalContextSnapshot(for: metadata)
                    return try await prepare(PreparedStagedImageRequest(fileURL: original, isPro: isPro, historicalContext: context))
                })
            guard draftSession.contains(operation), isDraftAccountCurrent else { return .temporarilyBlocked }
            stagedCapture.images.append(image)
            succeeded = await persistPhotoPreparationDraft()
            guard succeeded else { return .temporarilyBlocked }
            operationState.appendRequiredGalleryCrop(imageID: image.original.id)
            presentNextRequiredGalleryCrop()
            return .staged
        } catch {
            offlineToastMessage = .error("Import is pending. Any committed original remains in local recovery.")
            return .temporarilyBlocked
        }
    }

    func persistPhotoPreparationDraft() async -> Bool {
        guard let access = dependencies.photoOriginalPreparation else { return true }
        do {
            try await access.persist(images: stagedCapture.images,
                contexts: stagedCapture.observationContexts.map(\.context))
            return true
        } catch {
            offlineToastMessage = .error("Changes are not saved. Your original photos are retained; resolve storage or recovery before submitting.")
            return false
        }
    }

    func submitPhotoPreparationDraft(_ access: CapturePhotoOriginalPreparationAccess) async {
        guard !isCheckingScanAdmission, !isQueueingStagedCapture,
              !draftSession.hasUnresolvedWork, !hasPendingRequiredGalleryCrop, imageToCrop == nil, isDraftAccountCurrent,
              !dependencies.submission.admission.isLibraryAccessBlocked(),
              stagedCapture.audios.isEmpty, stagedCapture.videos.isEmpty,
              baseRefinementContext == nil else {
            offlineToastMessage = .error("This local preparation accepts original photos only. Your draft is retained.")
            return
        }
        isCheckingScanAdmission = true
        defer { isCheckingScanAdmission = false }
        guard await persistPhotoPreparationDraft() else { return }
        do {
            _ = try await access.freeze(images: stagedCapture.images, contexts: stagedCapture.observationContexts.map(\.context))
            offlineToastMessage = .information("Saved locally. Identification has not been requested.")
        } catch {
            offlineToastMessage = .error("The local draft could not be frozen. Your photos and details are retained.")
        }
    }

    func importPhotoPreparationItems(_ items: [PhotosPickerItem], access: CapturePhotoOriginalPreparationAccess) {
        guard !isDraftMutationLocked, !dependencies.submission.admission.isLibraryAccessBlocked(),
              let operation = beginDraftOperation() else { return }
        Task { @MainActor in
            var succeeded = false
            defer { completeDraftOperation(operation, succeeded: succeeded) }
            let prepare = dependencies.prepareImage
            let isPro = dependencies.scan.canStartProScan()
            do {
                for item in items {
                    let context = await historicalContextSnapshot(for: item.itemIdentifier)
                    let image = try await access.acquire(source: "picker", load: {
                        guard let transferred = try await item.loadTransferable(type: PhotoOriginalPickerTransfer.self) else {
                            throw PhotoPreparationFailure.missingMedia
                        }
                        return transferred.bytes
                    }, prepare: { url in
                        try await prepare(PreparedStagedImageRequest(fileURL: url, isPro: isPro, historicalContext: context))
                    })
                    guard draftSession.contains(operation), isDraftAccountCurrent else { return }
                    stagedCapture.images.append(image)
                    operationState.appendRequiredGalleryCrop(imageID: image.original.id)
                }
                succeeded = await persistPhotoPreparationDraft()
                if succeeded { selectedPhotoItems.removeAll(); presentNextRequiredGalleryCrop() }
            } catch {
                offlineToastMessage = .error("Photo preparation stopped. Your selection and retained originals are preserved.")
            }
        }
    }

    func capturePhotoPreparation(_ access: CapturePhotoOriginalPreparationAccess) {
        guard !isCapturing, !isDraftMutationLocked, !dependencies.submission.admission.isLibraryAccessBlocked(),
              let operation = beginDraftOperation() else { return }
        isCapturing = true
        Task { @MainActor in
            var succeeded = false
            defer { isCapturing = false; completeDraftOperation(operation, succeeded: succeeded) }
            let camera = dependencies.scan.camera.captureImage
            let prepare = dependencies.scan.media.prepareStill
            let center = composingZoneVerticalCenter
            let isPro = dependencies.scan.canStartProScan()
            do {
                let image = try await access.acquire(source: "camera", load: { try await camera() }, prepare: { url in
                    let data = try PhotoOriginalPickerTransfer.readInbox(url)
                    guard let prepared = try await prepare(CaptureScanStillPreparationRequest(
                        captureData: data, composingCenter: center, isProActive: isPro)) else { return nil }
                    return PreparedStagedImage(compressedData: prepared.inferenceData, displayData: prepared.displayData,
                        historicalContext: nil, previewCGImage: prepared.previewCGImage, focusRegion: prepared.focusRegion)
                })
                guard draftSession.contains(operation), isDraftAccountCurrent else { return }
                stagedCapture.images.append(image)
                succeeded = await persistPhotoPreparationDraft()
            } catch {
                offlineToastMessage = .error("Photo preparation stopped. Any retained original remains available for recovery.")
            }
        }
    }

    func removePhotoPreparationImage(_ index: Int) {
        guard let access = dependencies.photoOriginalPreparation,
              stagedCapture.images.indices.contains(index), !isDraftMutationLocked else { return }
        let image = stagedCapture.images[index]
        isCheckingScanAdmission = true
        Task { @MainActor in
            defer { isCheckingScanAdmission = false }
            do {
                try await access.remove(image)
                stagedCapture.images.removeAll { $0.original.id == image.original.id }
                operationState.removeRequiredGalleryCrop(imageID: image.original.id)
                imageToCrop = nil; editingCropIndex = nil
                _ = await persistPhotoPreparationDraft()
            } catch { offlineToastMessage = .error("Removal is pending. The original remains protected.") }
        }
    }

    func discardPhotoPreparationDraft(_ access: CapturePhotoOriginalPreparationAccess) {
        guard !isCheckingScanAdmission else { return }
        isCheckingScanAdmission = true
        Task { @MainActor in
            defer { isCheckingScanAdmission = false }
            do {
                try await access.discard(returningSourcesTo: dependencies.externalImageImports)
                stagedCapture.clearAll(); descriptionDraft = ObservationContext(); draftSession.reset()
                imageToCrop = nil; editingCropIndex = nil; isReviewActive = false
            } catch { offlineToastMessage = .error("Discard is pending. Your local files remain protected.") }
        }
    }
}
