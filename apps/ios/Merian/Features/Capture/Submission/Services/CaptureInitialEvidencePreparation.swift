import Foundation

/// Builds one ordered observation from retained originals. The result contains
/// only bounded derivatives; originals stay with their registered storage owner.
actor CaptureInitialEvidencePreparation {
    typealias Source = SharedMediaCaptureDraftSourceInput
    typealias Artifact = CaptureInitialEvidencePlan.Artifact

    enum Item: Equatable, Sendable {
        case photo(Source, SharedMediaNativePreparationRecipe)
        case audio(Source)
        case video(source: Source, playback: Data, frames: [Data], companion: Source?)
        case description(String)
    }

    struct Prepared: Sendable {
        let plan: CaptureInitialEvidencePlan
        let derivatives: [UUID: Data]
    }

    func prepare(identity: CaptureInitialDraftSession.Identity, items: [Item],
                 readSource: @Sendable (Source) async throws -> Data,
                 focusFactory: ImageFocusWorkFactory = .init()) async throws -> Prepared {
        guard (1...64).contains(items.count) else { throw SharedMediaStorageFailure.capacity }
        try requireBoundedComposition(items)
        var nodes: [CaptureInitialEvidencePlan.Node] = []
        var derivatives: [UUID: Data] = [:]
        var imageBytes = 0, videoBytes = 0
        var sourceIDs: Set<UUID> = []

        func source(_ input: Source, role: SharedMediaCaptureArtifactRequest.Role) throws -> Artifact {
            guard input.scanID == identity.scanID, input.submissionGeneration == identity.generation,
                  input.role == role, sourceIDs.insert(input.mediaID).inserted,
                  input.byteCount > 0, input.byteCount <= 33_554_432 else { throw SharedMediaStorageFailure.conflict }
            try input.context.validate(role: role)
            return .init(mediaID: input.mediaID, contentType: input.contentType,
                byteCount: Int(input.byteCount), sha256: input.sha256)
        }

        func derivative(_ bytes: Data, video: Bool = false) throws -> Artifact {
            guard !bytes.isEmpty else { throw SharedMediaStorageFailure.invalid }
            let contentType: String
            if video {
                guard bytes.count <= 12_582_912 - videoBytes else { throw SharedMediaStorageFailure.capacity }
                videoBytes += bytes.count
                contentType = "video/mp4"
            } else {
                guard bytes.count <= 5_242_880 - imageBytes else { throw SharedMediaStorageFailure.capacity }
                let type = try imageType(bytes, maximum: 5_242_880)
                guard type == "image/jpeg" || type == "image/png" else { throw SharedMediaStorageFailure.invalid }
                imageBytes += bytes.count
                contentType = type
            }
            let artifact = Artifact(mediaID: UUID(), contentType: contentType,
                byteCount: bytes.count, sha256: SharedMediaAcquisitionEncoding.digest(bytes))
            derivatives[artifact.mediaID] = bytes
            return artifact
        }

        for item in items {
            try Task.checkCancellation()
            switch item {
            case let .description(text): nodes.append(.description(text))
            case let .photo(input, recipe):
                let original = try source(input, role: .sourceImage)
                let bytes = try await readSource(input)
                guard bytes.count == original.byteCount,
                      SharedMediaAcquisitionEncoding.digest(bytes) == original.sha256,
                      try imageType(bytes, maximum: 33_554_432) == original.contentType else {
                    throw SharedMediaStorageFailure.conflict
                }
                let output = try await OriginalPhotoRenderer.render(.bytes(bytes), recipe: recipe)
                let focus: NormalizedImageFocusRegion?
                if let manual = output.manualFocus { focus = manual } else {
                    focus = await ImageFocusEngine.detectAndDrain(in: output.inference, factory: focusFactory).region
                }
                try Task.checkCancellation()
                nodes.append(try .image(source: original, prepared: derivative(output.inference), focus: focus,
                    preparation: ObservationInitialPhotoPreparation(recipe: recipe)))
            case let .audio(input):
                nodes.append(try .audio(.init(source: source(input, role: .sourceAudio), preparedMediaID: UUID())))
            case let .video(input, playback, frames, companion):
                guard (1...5).contains(frames.count) else { throw SharedMediaStorageFailure.capacity }
                let original = try source(input, role: .sourceVideo)
                let playbackArtifact = try derivative(playback, video: true)
                let frameArtifacts = try frames.map { try derivative($0) }
                let audio = try companion.map { CaptureInitialEvidencePlan.Audio(
                    source: try source($0, role: .sourceCompanionAudio), preparedMediaID: UUID()) }
                nodes.append(.video(.init(source: original, playback: playbackArtifact, frames: frameArtifacts, audio: audio)))
            }
        }
        try Task.checkCancellation()
        return try .init(plan: .init(ownerID: identity.ownerID, scanID: identity.scanID,
            generation: identity.generation, items: nodes), derivatives: derivatives)
    }

    private func imageType(_ bytes: Data, maximum: Int64) throws -> String {
        let identifier = try PhotoPreparationLockedFiles.validateImage(bytes, maximumBytes: maximum)
        return try SharedMediaNativePhotoContent.wireContentType(identifier)
    }

    private func requireBoundedComposition(_ items: [Item]) throws {
        var photos = 0, audios = 0, videos = 0, companions = 0
        var originalPhotoBytes: Int64 = 0
        for item in items {
            switch item {
            case let .photo(source, _):
                photos += 1
                guard source.byteCount > 0, source.byteCount <= 33_554_432,
                      source.byteCount <= 67_108_864 - originalPhotoBytes else { throw SharedMediaStorageFailure.capacity }
                originalPhotoBytes += source.byteCount
            case .audio: audios += 1
            case let .video(_, playback, frames, companion):
                videos += 1; companions += companion == nil ? 0 : 1
                guard playback.count <= 12_582_912, (1...5).contains(frames.count) else { throw SharedMediaStorageFailure.capacity }
            case .description: break
            }
        }
        let physical = photos + audios + videos
        guard physical > 0, physical <= (physical == photos ? 5 : 2), videos <= 1,
              audios + companions <= 2 else { throw SharedMediaStorageFailure.capacity }
    }
}
