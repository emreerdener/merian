import Foundation
import Observation
import UIKit

/// Current-process original-photo state before immutable native submission.
/// Ordinary composition supplies no session. Originals always belong to the
/// registered native owner; previews are transient and never evidence inputs.
@Observable @MainActor
final class CaptureNativePhotoDraftSession {
    struct Item {
        let id: UUID
        let ordinal: Int64
        var request: SharedMediaAcquisitionIntent?
        var reference: PhotoOriginalReference?
        var preview: UIImage?
        var recipe: SharedMediaNativePreparationRecipe?
        var removal: SharedMediaNativeAppOriginalRequest?
        var removed = false
    }
    struct Prepared {
        let capture: StagedCapture
        let submission: CaptureNativePhotoSubmissionSession
    }
    let identity: StagedCapture.NativePhotoDraft
    private(set) var items: [Item] = []
    private(set) var isBusy = false
    private(set) var isFrozen = false
    private(set) var needsAttention = false
    private(set) var isDiscarded = false
    private(set) var metadataRequest: SharedMediaNativeAppMetadataRequest?
    private(set) var prepared: Prepared?
    private var frozenSnapshot: CaptureNativePhotoSubmissionSnapshot?
    private var previewsInvalidated = false
    private var uncertainDisposition = false
    private var acquisitionEntered = false
    private var owner: SharedMediaNativeOriginalOwner?
    private let preflight: CaptureNativePhotoSubmissionSession.Preflight?
    private let resolveOwner: () async throws -> SharedMediaNativeOriginalOwner

    var canEdit: Bool { !isBusy && !isFrozen && !needsAttention && !isDiscarded && !previewsInvalidated }
    var canDiscard: Bool {
        !isBusy && !isFrozen && !isDiscarded && !previewsInvalidated && !uncertainDisposition
            && items.allSatisfy { $0.removed || $0.reference != nil }
    }
    var hasNoNativeAcquisition: Bool { !acquisitionEntered && items.isEmpty }
    var references: [PhotoOriginalReference] { items.filter { !$0.removed }.compactMap(\.reference) }

    init(identity: StagedCapture.NativePhotoDraft,
         preflight: CaptureNativePhotoSubmissionSession.Preflight? = nil,
         resolveOwner: @escaping () async throws -> SharedMediaNativeOriginalOwner) {
        self.identity = identity; self.preflight = preflight; self.resolveOwner = resolveOwner
    }

    static func app(ownerID: UUID, diContainer: AppDIContainer) -> CaptureNativePhotoDraftSession {
        .init(identity: .init(ownerID: ownerID, packageID: UUID(), draftGeneration: UUID()),
              preflight: CaptureNativePhotoSubmissionSession.appPreflight,
              resolveOwner: { try await diContainer.nativeMediaOwnerForFeature() })
    }

    /// The caller retains the whole ordered picker selection; no prefix or
    /// failed-item substitution is permitted. Request identity precedes loading.
    func acquire(itemID: UUID, kind: SharedMediaAcquisitionIntent.Kind = .picker, load: @escaping @Sendable () async throws -> Data) async throws -> (PhotoOriginalReference, UIImage) {
        guard canEdit, !items.contains(where: { $0.id == itemID }), items.count < 2 else {
            throw SharedMediaStorageFailure.closed
        }
        let index = items.count
        items.append(.init(id: itemID, ordinal: Int64(index)))
        isBusy = true
        var enteredAcquisition = false
        defer { isBusy = false }
        do {
            let admitted = try await admittedOwner()
            try Task.checkCancellation()
            guard !previewsInvalidated else { throw SharedMediaStorageFailure.closed }
            let request = try await admitted.prepareAppOriginal(packageID: identity.packageID,
                draftGeneration: identity.draftGeneration, ordinal: Int64(index), kind: kind)
            guard request.ownerID == identity.ownerID else { throw SharedMediaStorageFailure.stale }
            items[index].request = request
            guard !previewsInvalidated else { throw SharedMediaStorageFailure.closed }
            enteredAcquisition = true; acquisitionEntered = true
            let result = try await admitted.acquireAppOriginal(request) {
                let bytes = try await load()
                guard !bytes.isEmpty, bytes.count <= PhotoPreparationPolicy.original else {
                    throw PhotoPreparationFailure.sizeLimit
                }
                let image = try await DetachedWork.value(priority: .userInitiated, category: .imagePreparation) {
                    guard let value = ImageDownsampler.downsample(data: bytes,
                        maxSize: CGFloat(ImagePreparationPolicy.displayMaxDimension)) else {
                        throw MediaPreparationError.unreadableImage
                    }
                    return SendableCGImage(image: value)
                }
                await self.retainPreview(image, index: index)
                return bytes
            }
            try result.validate(request: request)
            let reference = PhotoOriginalReference(ownerID: identity.ownerID, packageID: identity.packageID,
                referenceID: result.referenceID, assetID: result.assetID, assetGeneration: result.assetGeneration,
                draftGeneration: identity.draftGeneration, referenceRevision: result.referenceRevision)
            items[index].reference = reference
            try Task.checkCancellation()
            guard !previewsInvalidated, let preview = items[index].preview else { throw SharedMediaStorageFailure.closed }
            return (reference, preview)
        } catch {
            // Even a lost acknowledgement retains the exact association. This
            // slice never reloads a picker item to guess whether copying happened.
            if enteredAcquisition { needsAttention = true }
            else { items.removeLast() } // request() is read-only; no reservation was entered
            throw error
        }
    }

    func setRecipe(_ recipe: SharedMediaNativePreparationRecipe, for reference: PhotoOriginalReference) throws {
        guard canEdit, let index = items.firstIndex(where: { !$0.removed && $0.reference == reference }) else {
            throw SharedMediaStorageFailure.closed
        }
        try recipe.validate()
        guard recipe.cropDisplaySize != nil || recipe.format == .cameraStill else { throw SharedMediaStorageFailure.invalid }
        items[index].recipe = recipe
    }

    /// Freeze ALL input before the first save/preparation. A failed preparation
    /// remains held: its hidden saved pair ID must not be guessed or regenerated.
    func prepare(_ capture: StagedCapture) async throws -> Prepared {
        let snapshot = try CaptureNativePhotoSubmissionSnapshot(capture)
        if let prepared {
            guard !isBusy, !previewsInvalidated, snapshot == frozenSnapshot else { throw SharedMediaStorageFailure.stale }
            return prepared
        }
        guard canEdit, snapshot.identity == identity, snapshot.references == references,
              (1...2).contains(references.count), references.count == items.filter({ !$0.removed }).count,
              capture.images.allSatisfy({ $0.compressedData.isEmpty && $0.displayData.isEmpty && $0.focusRegion == nil }) else {
            throw SharedMediaStorageFailure.stale
        }
        let selected = items.filter { !$0.removed }
        let recipes = try selected.map { item -> SharedMediaNativePreparationRecipe in
            guard let recipe = item.recipe else { throw SharedMediaStorageFailure.invalid }
            return recipe
        }
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(
            snapshot.supportingBytes, maximum: Int(PhotoPreparationPolicy.metadata))
        guard supporting.presentation.count == recipes.count else { throw SharedMediaStorageFailure.stale }
        for (index, entry) in zip(supporting.presentation, recipes).enumerated() {
            let (presentation, recipe) = entry
            guard presentation.referenceID == snapshot.references[index].referenceID, presentation.cropQuarterTurns == recipe.quarterTurns, presentation.cropScale == recipe.scale,
                  presentation.cropOffsetX == recipe.offsetX, presentation.cropOffsetY == recipe.offsetY else {
                throw SharedMediaStorageFailure.stale
            }
        }
        frozenSnapshot = snapshot; isFrozen = true; isBusy = true
        defer { isBusy = false }
        do {
            let admitted = try await admittedOwner()
            guard !previewsInvalidated else { throw SharedMediaStorageFailure.closed }
            try Task.checkCancellation()
            let request = try await admitted.prepareAppMetadata(packageID: identity.packageID,
                draftGeneration: identity.draftGeneration, contexts: supporting.contexts, presentation: supporting.presentation)
            metadataRequest = request
            guard !previewsInvalidated else { throw SharedMediaStorageFailure.closed }
            _ = try await admitted.saveAppMetadata(request)
            var pairs: [SharedMediaNativePairFileState] = []
            for (reference, recipe) in zip(snapshot.references, recipes) {
                try Task.checkCancellation()
                guard !previewsInvalidated else { throw SharedMediaStorageFailure.closed }
                pairs.append(try await admitted.prepareAndDeliverAppPhoto(original: reference, recipe: recipe))
            }
            let metadata = try await admitted.currentAppMetadata(packageID: identity.packageID, draftGeneration: identity.draftGeneration)
            let selection = try CaptureNativePhotoSubmissionSelection(metadata: metadata, pairs: pairs)
            let readback = try await admitted.readPreparedAppPhotos(expectedMetadata: metadata, pairIDs: selection.pairIDs)
            guard readback.photos.map(\.original) == snapshot.references else { throw SharedMediaStorageFailure.stale }
            var projected = capture
            projected.images = try zip(capture.images, readback.photos).map { image, photo in
                guard let thumbnail = ImageDownsampler.downsample(data: photo.display, maxSize: 512) else {
                    throw MediaPreparationError.unreadableImage
                }
                return image.replacing(compressedData: photo.ai, displayData: photo.display,
                    uiImage: UIImage(cgImage: thumbnail)).replacingFocusRegion(try photo.pair.intent().focus)
            }
            _ = try CaptureNativePhotoSubmissionSnapshot(projected, selection: selection)
            let value = Prepared(capture: projected, submission: .init(selection: selection, preflight: preflight, resolveOwner: { admitted }))
            guard !previewsInvalidated else { throw SharedMediaStorageFailure.closed }
            prepared = value
            try Task.checkCancellation()
            return value
        } catch {
            needsAttention = true
            throw error
        }
    }

    /// One acknowledgement at a time; later removals are prepared from fresh
    /// revisions. A partial discard keeps both the marker and unfinished items.
    func remove(_ reference: PhotoOriginalReference) async throws {
        guard canEdit, let index = items.firstIndex(where: { !$0.removed && $0.reference == reference }) else {
            throw SharedMediaStorageFailure.closed
        }
        isBusy = true
        defer { isBusy = false }
        do { try await removeAcknowledgedItem(at: index) }
        catch { needsAttention = true; uncertainDisposition = true; throw error }
    }

    func discard() async throws {
        guard canDiscard else { throw SharedMediaStorageFailure.closed }
        // Hold a single admission across the whole batch, including retirement.
        isBusy = true
        defer { isBusy = false }
        do {
            for index in items.indices where !items[index].removed {
                try await removeAcknowledgedItem(at: index)
            }
            guard !previewsInvalidated, items.allSatisfy(\.removed) else { throw SharedMediaStorageFailure.closed }
            isDiscarded = true
        } catch { needsAttention = true; uncertainDisposition = true; throw error }
    }

    private func removeAcknowledgedItem(at index: Int) async throws {
        guard !previewsInvalidated, let reference = items[index].reference else { throw SharedMediaStorageFailure.closed }
        let admitted = try await admittedOwner()
        guard !previewsInvalidated else { throw SharedMediaStorageFailure.closed }
        let request = try await admitted.prepareAppOriginalRemoval(reference)
        items[index].removal = request
        guard !previewsInvalidated else { throw SharedMediaStorageFailure.closed }
        try await admitted.removeAppOriginal(request)
        items[index].removed = true; items[index].preview = nil
        try await admitted.recoverAppOriginalRetirements()
    }

    func holdForAttention() { needsAttention = true }

    /// Account loss hides private UI without pretending native work was cancelled.
    func clearPrivatePreviews() {
        previewsInvalidated = true
        for index in items.indices { items[index].preview = nil }
        prepared = nil
    }

    private func retainPreview(_ image: SendableCGImage, index: Int) {
        guard !previewsInvalidated else { return }
        items[index].preview = UIImage(cgImage: image.image)
    }

    private func admittedOwner() async throws -> SharedMediaNativeOriginalOwner {
        if let owner { return owner }
        let admitted = try await resolveOwner(); owner = admitted
        return admitted
    }
}
