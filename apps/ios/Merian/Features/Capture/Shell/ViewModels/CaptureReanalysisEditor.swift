import Foundation
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Private modal composition, independent of ordinary Capture capacity, admission and replacement.
@Observable @MainActor
final class CaptureReanalysisEditor {
    enum Phase { case choosing, editing, submitted, closed }
    private(set) var phase: Phase = .choosing
    private(set) var selectedPhotoIDs = Set<UUID>()
    private(set) var capture = StagedCapture()
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var session: CaptureReanalysisSession?
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let account: ObservationHistoryCloudClient
    @ObservationIgnored private let loader: CaptureReanalysisEvidenceLoader
    @ObservationIgnored private let producer: ObservationReanalysisProducer
    @ObservationIgnored private let isCurrentOwner: @MainActor () -> Bool
    @ObservationIgnored private let prepareImage: PreparedStagedImageLoader
    @ObservationIgnored private let requestSubmitted: @MainActor (UUID) -> Void
    @ObservationIgnored private let requestCleanup: @MainActor () -> Void

    init(source: ObservationReanalysisSource, container: ModelContainer, account: ObservationHistoryCloudClient,
         loader: CaptureReanalysisEvidenceLoader, producer: ObservationReanalysisProducer,
         isCurrent: @escaping @MainActor () -> Bool, requestSubmitted: @escaping @MainActor (UUID) -> Void,
         requestCleanup: @escaping @MainActor () -> Void,
         prepareImage: @escaping PreparedStagedImageLoader = CaptureWorkspaceDependencies.livePreparedImageLoader) {
        session = CaptureReanalysisSession(source: source, generation: UUID())
        self.container = container; self.account = account; self.loader = loader; self.producer = producer
        isCurrentOwner = isCurrent; self.requestSubmitted = requestSubmitted; self.requestCleanup = requestCleanup; self.prepareImage = prepareImage
    }

    var photos: [ObservationHistoryPhotoReference] { session?.source.photos ?? [] }
    var isFrozen: Bool { session?.plan != nil }
    var canEdit: Bool { phase == .editing && !isBusy && !isFrozen && current }
    var canSubmit: Bool { phase == .editing && !isBusy && !capture.images.isEmpty && current }
    private var current: Bool { phase != .closed && session != nil && isCurrentOwner() }

    func toggle(_ id: UUID) {
        guard phase == .choosing, !isBusy, current, let source = session?.source else { return }
        var proposed = selectedPhotoIDs
        if proposed.contains(id) { proposed.remove(id) } else { proposed.insert(id) }
        do {
            _ = try CaptureReanalysisEvidenceSelection(source: source, selectedPhotoIDs: proposed)
            selectedPhotoIDs = proposed; errorMessage = nil
        } catch { errorMessage = "Choose up to five JPEG or PNG photos, within 5 MB in total." }
    }

    func loadSelection() async {
        guard phase == .choosing, !isBusy, current, let session else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            let selection = try CaptureReanalysisEvidenceSelection(source: session.source, selectedPhotoIDs: selectedPhotoIDs)
            let staged = try await loader.load(selection, container: container, isCurrent: { [weak self] in self?.current == true })
            guard current, !Task.isCancelled else { return }
            capture = staged; phase = .editing
        } catch { if current { errorMessage = "These photos couldn’t be loaded. Your selection is unchanged. Try again or choose different photos." } }
    }

    func preview(_ photo: ObservationHistoryPhotoReference) async throws -> UIImage {
        guard current, let session else { throw ObservationHistoryError.accountChanged }
        let selection = try CaptureReanalysisEvidenceSelection(source: session.source, selectedPhotoIDs: [photo.mediaID])
        let staged = try await loader.load(selection, container: container, isCurrent: { [weak self] in self?.current == true })
        guard current, !Task.isCancelled, let image = staged.images.first?.uiImage else { throw ObservationHistoryError.accountChanged }
        return image
    }

    func importPhoto(_ item: PhotosPickerItem) async {
        guard canEdit, capture.images.count < CaptureReanalysisEvidenceSelection.maximumPhotos else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            guard let file = try await item.loadTransferable(type: ImageFileWrapper.self) else { throw MerianError.invalidResponse }
            defer { try? FileManager.default.removeItem(at: file.url) }
            guard current, !Task.isCancelled else { return }
            let prepared = try await prepareImage(.init(fileURL: file.url, isPro: true, historicalContext: nil))
            guard current, !Task.isCancelled, let prepared else { throw MerianError.invalidResponse }
            // Commit after the asynchronous import, while still holding the editor's operation lock.
            appendPhoto(prepared)
        } catch { if current { errorMessage = "This photo couldn’t be added. Try another photo." } }
    }

    /// An imported photo has no inherited history lineage or mutable parent context.
    func addPhoto(_ prepared: PreparedStagedImage) {
        guard canEdit, capture.images.count < CaptureReanalysisEvidenceSelection.maximumPhotos else { return }
        appendPhoto(prepared)
    }

    private func appendPhoto(_ prepared: PreparedStagedImage) {
        let image = UIImage(cgImage: prepared.previewCGImage.image)
        capture.images.append(StagedImage(compressedData: prepared.compressedData, displayData: prepared.displayData,
            uiImage: image, original: .init(image: image, isFromGallery: true)))
    }

    func removePhoto(_ id: UUID) {
        guard canEdit else { return }
        capture.images.removeAll { $0.original.id == id }
    }
    func setNote(_ text: String, at index: Int) {
        guard canEdit, capture.observationContexts.indices.contains(index), text.utf16.count <= 16384 else { return }
        capture.observationContexts[index].context.freeText = text
    }
    func removeNote(at index: Int) {
        guard canEdit, capture.observationContexts.indices.contains(index) else { return }
        capture.observationContexts.remove(at: index)
    }
    func addNote() {
        guard canEdit, capture.observationContexts.count < 64 else { return }
        capture.observationContexts.append(.init(context: .init(freeText: "")))
    }

    func submit() async {
        guard canSubmit, let session else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            let result = try await session.stage(capture: capture, generation: session.generation, container: container,
                producer: producer, action: .submit, isCurrent: { [weak self] in self?.current == true })
            guard current, !Task.isCancelled else { return }
            switch result {
            case let .submitted(intent): requestSubmitted(intent.draft.identity.analysisID)
            case .bound: break // Existing execution owns an exact admitted replay.
            case .draft: throw ObservationHistoryError.resultConflict
            }
            guard current, !Task.isCancelled else { return }
            phase = .submitted
        } catch { if current { errorMessage = "Your reanalysis could not be confirmed. Retry with the same photos; your current identification is unchanged." } }
    }

    /// Returns true only after durable retirement, or when there was no saved plan.
    func discard() -> Bool {
        guard !isBusy, current, let session else { return false }
        do {
            let receipt = try session.discard(generation: session.generation, container: container,
                account: account, isCurrent: { [weak self] in self?.current == true })
            if receipt != nil { requestCleanup() }
            invalidate(); return true
        } catch { errorMessage = "This draft couldn’t be discarded safely. Keep it and try again."; return false }
    }

    /// Presentation teardown never claims cancellation of a saved or ambiguous child.
    func invalidate() {
        phase = .closed; capture = StagedCapture(); selectedPhotoIDs = []; session = nil; errorMessage = nil
    }
}
