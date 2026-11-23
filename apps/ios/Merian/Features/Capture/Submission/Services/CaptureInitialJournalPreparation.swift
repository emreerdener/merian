import Foundation

/// Maps the saved editor to one submission. UI thumbnails and playback copies
/// are never substituted for a retained original or companion.
actor CaptureInitialJournalPreparation {
    func items(journal: SharedMediaCaptureDraftJournal,
               read: @Sendable (SharedMediaCaptureDraftSourceInput) async throws -> Data) async throws
        -> [CaptureInitialEvidencePreparation.Item] {
        try journal.validate()
        guard journal.phase == .editing, journal.frozenObservation == nil,
              journal.sources.filter({ !$0.state.isTerminal }).allSatisfy({ $0.state == .ready }) else {
            throw SharedMediaStorageFailure.closed
        }
        func source(_ id: UUID) throws -> SharedMediaCaptureDraftSourceInput {
            guard let value = journal.sources.first(where: { $0.input.id == id && $0.state == .ready }) else {
                throw SharedMediaStorageFailure.conflict
            }
            return value.input
        }
        var result: [CaptureInitialEvidencePreparation.Item] = []
        for item in journal.items {
            try Task.checkCancellation()
            switch item {
            case let .photo(_, id, recipe): result.append(try .photo(source(id), recipe))
            case let .audio(_, id): result.append(try .audio(source(id)))
            case let .description(_, text): result.append(.description(text))
            case let .video(_, id, companion, recipe):
                let original = try source(id), bytes = try await read(original)
                guard bytes.count == original.byteCount,
                      SharedMediaAcquisitionEncoding.digest(bytes) == original.sha256 else {
                    throw SharedMediaStorageFailure.conflict
                }
                let prepared = try await video(bytes, recipe: recipe)
                result.append(try .video(source: original, playback: prepared.playback,
                    frames: prepared.frames, companion: companion.map(source)))
            }
        }
        try Task.checkCancellation()
        return result
    }

    private func video(_ bytes: Data, recipe: SharedMediaCaptureDraftJournal.VideoRecipe) async throws
        -> (playback: Data, frames: [Data]) {
        guard let path = await FileIOActor.shared.stageHistoryVideo(bytes) else { throw SharedMediaStorageFailure.unavailable }
        var paths: Set<String> = [path]
        var snapshot: FileIOActor.VideoSnapshot?
        do {
            let framing = recipe.displaySize.map {
                CaptureVideoFraming(scale: CGFloat(recipe.scale), offset: .init(width: recipe.offsetX, height: recipe.offsetY),
                    displaySize: CGFloat($0), quarterTurns: recipe.quarterTurns)
            }
            var dependencies = CaptureScanVideoMediaPreparer.Dependencies.live
            dependencies.audio = { _ in nil }
            let prepared = try await CaptureScanVideoMediaPreparer.prepare(.init(
                videoURL: StagedVideo.localURL(for: path), duration: recipe.duration,
                composingCenter: CGFloat(recipe.composingCenter), isProActive: recipe.isPro, framing: framing), dependencies: dependencies)
            paths.insert(prepared.playback.fileURL.path)
            if let audio = prepared.audioFilePath { paths.insert(audio) }
            guard let copy = await FileIOActor.shared.snapshotCapturePlayback(path: prepared.playback.fileURL.path) else {
                throw SharedMediaStorageFailure.unavailable
            }
            snapshot = copy
            guard let playback = await FileIOActor.shared.readVideoSnapshot(copy, maximumBytes: 12_582_912) else {
                throw SharedMediaStorageFailure.conflict
            }
            let frames = prepared.sampledFrames.map(\.inferenceData)
            guard (1...5).contains(frames.count), frames.reduce(0, { $0 + $1.count }) <= 5_242_880 else {
                throw SharedMediaStorageFailure.capacity
            }
            guard await FileIOActor.shared.discardVideoSnapshot(copy) else { throw SharedMediaStorageFailure.unavailable }
            snapshot = nil
            await FileIOActor.shared.deleteFiles(at: Array(paths))
            try Task.checkCancellation()
            return (playback, frames)
        } catch {
            if let snapshot { await FileIOActor.shared.discardVideoSnapshot(snapshot) }
            await FileIOActor.shared.deleteFiles(at: Array(paths))
            throw error
        }
    }
}
