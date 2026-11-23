import Foundation
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Protected reanalysis composition, independent of ordinary admission and replacement.
@Observable @MainActor
final class CaptureReanalysisEditor {
    enum Phase { case choosing, editing, submitted, closed }
    private(set) var phase: Phase = .choosing
    private(set) var selectedPhotoIDs = Set<UUID>()
    private(set) var capture = StagedCapture()
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var retainedPhotoIDs: [UUID] = []
    @ObservationIgnored private var retainedInput: ObservationReanalysisRetainedInput?
    private var retainedOptionsLoaded = false
    private var retainedOptionsResolved = false
    @ObservationIgnored private var session: CaptureReanalysisSession?
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let account: ObservationHistoryCloudClient
    @ObservationIgnored private let loader: CaptureReanalysisEvidenceLoader
    @ObservationIgnored private let producer: ObservationReanalysisProducer
    @ObservationIgnored private let isCurrentOwner: @MainActor () -> Bool
    @ObservationIgnored private let prepareImage: PreparedStagedImageLoader
    @ObservationIgnored private let requestSubmitted: @MainActor (UUID) -> Void
    @ObservationIgnored private let requestCleanup: @MainActor () -> Void
    @ObservationIgnored private var workspaceAudio: CaptureWorkspaceAudioReanalysis?
    @ObservationIgnored private var workspaceVideo: CaptureWorkspaceVideoReanalysis?
    @ObservationIgnored private var workspaceComposition: CaptureWorkspaceCompositionReanalysis?
    private var workspaceOwnedPaths = Set<String>()

    init(source: ObservationReanalysisSource, container: ModelContainer, account: ObservationHistoryCloudClient,
         loader: CaptureReanalysisEvidenceLoader, producer: ObservationReanalysisProducer,
         isCurrent: @escaping @MainActor () -> Bool, requestSubmitted: @escaping @MainActor (UUID) -> Void,
         requestCleanup: @escaping @MainActor () -> Void,
         prepareImage: @escaping PreparedStagedImageLoader = CaptureWorkspaceDependencies.livePreparedImageLoader,
         workspaceAudio: CaptureWorkspaceAudioReanalysis? = nil, workspaceVideo: CaptureWorkspaceVideoReanalysis? = nil, workspaceComposition: CaptureWorkspaceCompositionReanalysis? = nil) {
        session = CaptureReanalysisSession(source: source, generation: UUID())
        self.container = container; self.account = account; self.loader = loader; self.producer = producer
        retainedOptionsLoaded = loader.retainedOwner == nil
        retainedOptionsResolved = loader.retainedOwner == nil
        isCurrentOwner = isCurrent; self.requestSubmitted = requestSubmitted; self.requestCleanup = requestCleanup; self.prepareImage = prepareImage
        self.workspaceAudio = workspaceAudio
        self.workspaceVideo = workspaceVideo
        self.workspaceComposition = workspaceComposition
    }

    var photos: [ObservationHistoryPhotoReference] { session?.source.photos ?? [] }
    var observationID: UUID? { session?.source.observationID }
    var isFrozen: Bool { session?.plan != nil || workspaceAudio?.isFrozen == true || workspaceVideo?.isFrozen == true || workspaceComposition?.isFrozen == true }
    var canEdit: Bool { phase == .editing && !isBusy && !isFrozen && current }
    var supportsManualSelection: Bool { canEdit && workspaceComposition != nil }
    var canSubmit: Bool { phase == .editing && !isBusy && capture.physicalItemCount > 0 && current }
    var canContinue: Bool { phase == .choosing && !isBusy && retainedOptionsResolved && current }
    var canReloadOriginals: Bool { phase == .choosing && !isBusy && !retainedOptionsLoaded && current }
    private var current: Bool { phase != .closed && session != nil && isCurrentOwner() }

    /// The shared workspace starts with the displayed version's submitted content.
    /// Loading is presentation-only: it never creates a child or submits work.
    func loadForWorkspace() async {
        if session?.source.composition != nil || session?.source.initialEvidence != nil, let workspaceComposition {
            await loadWorkspaceMedia(workspaceComposition.load, discard: workspaceComposition.discardStaging)
            return
        }
        if session?.source.video != nil, let workspaceVideo {
            await loadWorkspaceMedia(workspaceVideo.load, discard: workspaceVideo.discardStaging)
            return
        }
        if session?.source.audio != nil, let workspaceAudio {
            await loadWorkspaceMedia(workspaceAudio.load, discard: workspaceAudio.discardStaging)
            return
        }
        await loadRetainedOptions()
        // Automatic preload cannot silently turn a failed retained-media read
        // into an empty composition. The separate chooser's explicit continue
        // behavior does not authorize that fallback for the shared workspace.
        guard canContinue, retainedOptionsLoaded else { return }
        let originals = Set(photos.map(\.mediaID) + retainedPhotoIDs)
        guard !originals.isEmpty else {
            errorMessage = "The original media for this identification is unavailable for reanalysis. Your saved identification is unchanged."
            return
        }
        guard originals.count <= CaptureReanalysisEvidenceSelection.maximumPhotos else {
            errorMessage = "This identification has more photos than can be reanalyzed together. Your original identification is unchanged."
            return
        }
        selectedPhotoIDs = originals
        await loadSelection()
    }

    private func loadWorkspaceMedia(_ load: () async throws -> StagedCapture, discard: (StagedCapture) async -> Void) async {
        guard phase == .choosing, !isBusy, current else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let loaded = try await load()
            guard current, !Task.isCancelled else { await discard(loaded); return }
            capture = loaded; phase = .editing
        } catch { if current { errorMessage = "The original media couldn’t be loaded. Your saved identification is unchanged." } }
    }

    func discardUnclaimedWorkspaceMedia() async {
        guard !isFrozen else { return }
        if let workspaceComposition { await workspaceComposition.discardStaging(capture) } else if let workspaceVideo { await workspaceVideo.discardStaging(capture) } else if let workspaceAudio {
            await workspaceAudio.discardStaging(capture)
        }
        invalidate()
    }

    /// Shared Capture editors supply the final timeline; the session still owns
    /// identity, provenance validation and the immutable submitted snapshot.
    @discardableResult
    func updateWorkspaceCapture(_ value: StagedCapture, ownedPaths: Set<String> = []) -> Bool {
        guard canEdit, let source = session?.source, value.nativePhotoDraft == nil,
              value.images.count <= CaptureReanalysisEvidenceSelection.maximumPhotos else { return false }
        if source.composition != nil || source.initialEvidence != nil || CaptureWorkspaceCompositionReanalysis.requiresComposition(value) {
            guard workspaceComposition != nil, CaptureWorkspaceCompositionReanalysis.accepts(value, ownedPaths: ownedPaths) else { return false }
            capture = value; workspaceOwnedPaths = ownedPaths
            return true
        }
        if !value.videos.isEmpty {
            guard workspaceVideo != nil, value.images.isEmpty, value.audios.isEmpty, value.videos.count == 1,
                  ownedPaths.contains(value.videos[0].filePath) else { return false }
            capture = value; workspaceOwnedPaths = ownedPaths
            return true
        }
        if !value.audios.isEmpty {
            guard workspaceAudio != nil, value.images.isEmpty, value.audios.count == 1,
                  ownedPaths.contains(value.audios[0].filePath) else { return false }
            capture = value; workspaceOwnedPaths = ownedPaths
            return true
        }
        // Validate the physical evidence before replacing the staged value.
        // Notes may be temporarily empty while editing; an empty media tray is
        // also valid staging, but neither bypasses final submission validation.
        if !value.images.isEmpty {
            var photos = value
            photos.observationContexts = []
            guard (try? CaptureReanalysisPreparation.plan(source: source, capture: photos)) != nil else { return false }
        }
        capture = value
        return true
    }

    func loadRetainedOptions() async {
        guard phase == .choosing, !isBusy, !retainedOptionsLoaded, current, let session else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let input = try await loader.retained(source: session.source, container: container, isCurrent: { [weak self] in self?.current == true })
            guard current, !Task.isCancelled else { return }
            retainedInput = input; retainedPhotoIDs = input?.photos.map { $0.photo.pairID } ?? []
            retainedOptionsLoaded = true; retainedOptionsResolved = true; errorMessage = nil
        } catch {
            if current {
                retainedOptionsResolved = true
                errorMessage = "Original photos couldn’t be loaded. Try again, or continue to add new photos."
            }
        }
    }

    func toggle(_ id: UUID) {
        guard canContinue, let source = session?.source else { return }
        var proposed = selectedPhotoIDs
        if proposed.contains(id) { proposed.remove(id) } else { proposed.insert(id) }
        do {
            if let retainedInput { _ = try retainedInput.selection(proposed) } else {
                _ = try CaptureReanalysisEvidenceSelection(source: source, selectedPhotoIDs: proposed)
            }
            selectedPhotoIDs = proposed; errorMessage = nil
        } catch { errorMessage = "Choose up to five JPEG or PNG photos, within 5 MB in total." }
    }

    func loadSelection() async {
        guard canContinue, let session else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            let staged: StagedCapture
            if let retainedInput {
                staged = try await loader.load(retainedInput, selected: selectedPhotoIDs, container: container, isCurrent: { [weak self] in self?.current == true })
            } else {
                let selection = try CaptureReanalysisEvidenceSelection(source: session.source, selectedPhotoIDs: selectedPhotoIDs)
                staged = try await loader.load(selection, container: container, isCurrent: { [weak self] in self?.current == true })
            }
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

    func preview(_ id: UUID) async throws -> UIImage {
        if let photo = photos.first(where: { $0.mediaID == id }) { return try await preview(photo) }
        guard current, let retainedInput else { throw ObservationHistoryError.unavailable }
        let staged = try await loader.load(retainedInput, selected: [id], container: container, isCurrent: { [weak self] in self?.current == true })
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
            uiImage: image, original: .init(image: image, isFromGallery: true), reviewBasis: .squareCropSource))
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
            if session.source.composition != nil || session.source.initialEvidence != nil || CaptureWorkspaceCompositionReanalysis.requiresComposition(capture), let workspaceComposition {
                _ = try await workspaceComposition.submit(capture, ownedPaths: workspaceOwnedPaths)
                guard current, !Task.isCancelled else { return }
                phase = .submitted
                return
            }
            if !capture.videos.isEmpty, let workspaceVideo {
                _ = try await workspaceVideo.submit(capture, ownedPaths: workspaceOwnedPaths)
                guard current, !Task.isCancelled else { return }
                phase = .submitted
                return
            }
            if !capture.audios.isEmpty, let workspaceAudio {
                _ = try await workspaceAudio.submit(capture, ownedPaths: workspaceOwnedPaths)
                guard current, !Task.isCancelled else { return }
                // The retained source owner already owns admission/execution.
                // Do not wake the photo admission drain with an audio identity.
                phase = .submitted
                return
            }
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
        } catch { if current { errorMessage = "Your reanalysis could not be confirmed. Retry the same request; your current identification is unchanged." } }
    }

    /// Returns true only after durable retirement, or when there was no saved plan.
    func discard() -> Bool {
        guard !isBusy, current, let session else { return false }
        guard workspaceAudio?.isFrozen != true, workspaceVideo?.isFrozen != true, workspaceComposition?.isFrozen != true else {
            errorMessage = "This request has already been saved. Keep it and check its progress before starting another."
            return false
        }
        do {
            let receipt = try session.discard(generation: session.generation, container: container,
                account: account, isCurrent: { [weak self] in self?.current == true })
            if receipt != nil { requestCleanup() }
            invalidate(); return true
        } catch { errorMessage = "This draft couldn’t be discarded safely. Keep it and try again."; return false }
    }

    /// Presentation teardown never claims cancellation of a saved or ambiguous child.
    func invalidate() {
        workspaceAudio?.close(); workspaceAudio = nil; workspaceOwnedPaths = []
        workspaceVideo?.close(); workspaceVideo = nil
        workspaceComposition?.close(); workspaceComposition = nil
        retainedInput = nil; retainedPhotoIDs = []
        phase = .closed; capture = StagedCapture(); selectedPhotoIDs = []; session = nil; errorMessage = nil
    }
}
