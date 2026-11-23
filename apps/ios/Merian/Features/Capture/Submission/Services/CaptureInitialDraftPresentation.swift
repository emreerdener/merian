import Foundation
import UIKit

/// Disposable editing pixels/files. These never identify accepted evidence;
/// the journal and its retained sources remain the only submission inputs.
@MainActor
struct CaptureInitialDraftPresentation {
    enum Mode: Equatable { case editing, frozenReadOnly }
    let capture: StagedCapture
    let resources: CaptureDraftPresentationResources
    var ownedPaths: Set<String> { resources.paths }

    @discardableResult func discard() async -> Bool { await resources.discard() }

    static func make(journal: SharedMediaCaptureDraftJournal,
                     mode: Mode = .editing,
                     resources: CaptureDraftPresentationResources? = nil,
                     prepareVideo: @escaping @Sendable (CaptureScanVideoPreparationRequest) async throws -> PreparedCaptureScanVideo = {
                         var dependencies = CaptureScanVideoMediaPreparer.Dependencies.live
                         dependencies.audio = { _ in nil }
                         return try await CaptureScanVideoMediaPreparer.prepare($0, dependencies: dependencies)
                     },
                     read: @escaping @Sendable (SharedMediaCaptureDraftSourceInput) async throws -> Data) async throws -> Self {
        let resources = resources ?? CaptureDraftPresentationResources()
        try journal.validate()
        switch mode {
        case .editing:
            guard journal.phase == .editing, journal.frozenObservation == nil else { throw SharedMediaStorageFailure.closed }
        case .frozenReadOnly:
            guard journal.phase == .preparing || journal.phase == .submitting,
                  journal.frozenObservation != nil || journal.preparation != nil else { throw SharedMediaStorageFailure.closed }
        }
        guard journal.sources.filter({ !$0.state.isTerminal }).allSatisfy({ $0.state == .ready }) else {
            throw SharedMediaStorageFailure.closed
        }
        var capture = StagedCapture()
        capture.retainedItemOrder = journal.items.map(\.id)
        func source(_ id: UUID) throws -> SharedMediaCaptureDraftSourceInput {
            guard let saved = journal.sources.first(where: { $0.input.id == id && $0.state == .ready }) else {
                throw SharedMediaStorageFailure.conflict
            }
            return saved.input
        }
        do {
            for item in journal.items {
                try Task.checkCancellation()
                switch item {
                case let .photo(id, sourceID, recipe):
                    let input = try source(sourceID)
                    let bytes = try await read(input)
                    let preview = try await CaptureInitialPhotoPresentation().make(bytes, recipe: recipe)
                    var original = IdentifiableImage(image: UIImage(cgImage: preview.original.image),
                        environmentContext: input.context.facts?.environmentContext,
                        isFromGallery: input.context.origin == .imported,
                        initialCameraVerticalCenter: recipe.cameraVerticalCenter.map { CGFloat($0) },
                        lastCropQuarterTurns: recipe.quarterTurns, lastCropScale: CGFloat(recipe.scale),
                        lastCropOffset: .init(width: recipe.offsetX, height: recipe.offsetY),
                        lastCropDisplaySize: recipe.cropDisplaySize.map { CGFloat($0) },
                        manualSourceSelection: recipe.sourceSelection, id: id)
                    // The original preview remains upright and uncropped; its
                    // normalized selection maps to the verified original later.
                    original.allowsReframing = mode == .editing
                    capture.images.append(.init(compressedData: preview.output.inference,
                        displayData: preview.output.display, uiImage: UIImage(cgImage: preview.thumbnail.image),
                        original: original, focusRegion: preview.output.manualFocus,
                        addedAt: input.context.facts?.addedAt ?? .distantPast,
                        reviewBasis: .nativeOriginal(recipe)))
                case let .audio(id, sourceID):
                    let input = try source(sourceID), bytes = try await read(input)
                    guard let path = await FileIOActor.shared.stageHistoryAudio(bytes) else { throw SharedMediaStorageFailure.unavailable }
                    try await resources.retain(path)
                    capture.audios.append(.init(filePath: path, addedAt: input.context.facts?.addedAt ?? .distantPast, id: id))
                case let .video(id, sourceID, companionID, recipe):
                    let input = try source(sourceID), bytes = try await read(input)
                    guard let path = await FileIOActor.shared.stageHistoryVideo(bytes) else { throw SharedMediaStorageFailure.unavailable }
                    try await resources.retain(path)
                    let framing = recipe.displaySize.map {
                        CaptureVideoFraming(scale: recipe.scale,
                            offset: .init(width: recipe.offsetX, height: recipe.offsetY),
                            displaySize: $0, quarterTurns: recipe.quarterTurns)
                    }
                    let prepared = try await prepareVideo(.init(
                        videoURL: StagedVideo.localURL(for: path), duration: recipe.duration,
                        composingCenter: recipe.composingCenter, isProActive: recipe.isPro, framing: framing))
                    try await resources.retainAll([prepared.playback.fileURL.path] + [prepared.audioFilePath].compactMap { $0 })
                    if let audio = prepared.audioFilePath {
                        guard await resources.discard(audio) else { throw SharedMediaStorageFailure.unavailable }
                    }
                    // A restored companion is exact retained evidence. A fresh
                    // extraction must neither replace it nor invent membership.
                    var companionPath: String?
                    if let companionID {
                        let companionBytes = try await read(source(companionID))
                        guard let audio = await FileIOActor.shared.stageHistoryAudio(companionBytes) else {
                            throw SharedMediaStorageFailure.unavailable
                        }
                        companionPath = audio; try await resources.retain(audio)
                    }
                    let restored = PreparedCaptureScanVideo(sampledFrames: prepared.sampledFrames,
                        audioFilePath: companionPath, playback: prepared.playback)
                    capture.videos.append(CaptureWorkspaceViewModel.makeStagedVideo(restored,
                        isFromGallery: input.context.origin == .imported, id: id,
                        addedAt: input.context.facts?.addedAt ?? .distantPast,
                        originalFilePath: path, composingCenter: recipe.composingCenter, framing: framing))
                case let .description(id, text):
                    capture.observationContexts.append(.init(context: ObservationContext(freeText: text), id: id))
                }
            }
            try Task.checkCancellation()
            return .init(capture: capture, resources: resources)
        } catch {
            await resources.discard()
            throw error
        }
    }
}

private actor CaptureInitialPhotoPresentation {
    struct Preview: Sendable {
        let original: SendableCGImage
        let thumbnail: SendableCGImage
        let output: OriginalPhotoRenderer.Output
    }

    func make(_ bytes: Data, recipe: SharedMediaNativePreparationRecipe) async throws -> Preview {
        _ = try PhotoPreparationLockedFiles.validateImage(bytes, maximumBytes: 33_554_432)
        guard !bytes.isEmpty, bytes.count <= 33_554_432,
              let original = ImageDownsampler.downsample(data: bytes, maxSize: 2048) else {
            throw SharedMediaStorageFailure.invalid
        }
        let output = try await OriginalPhotoRenderer.render(.bytes(bytes), recipe: recipe)
        guard let thumbnail = ImageDownsampler.downsample(data: output.display, maxSize: 512) else {
            throw SharedMediaStorageFailure.invalid
        }
        try Task.checkCancellation()
        return .init(original: .init(image: original), thumbnail: .init(image: thumbnail), output: output)
    }
}
