import CryptoKit
import Foundation
import SwiftData
import UIKit

/// The toolbar owns staging; this owner freezes its exact ordered submission.
/// A retry resumes the saved child and never creates another provider attempt.
@MainActor
final class CaptureWorkspaceCompositionReanalysis {
    typealias Start = (ObservationCompositionResumeSubmission.Ready, ModelContainer, ObservationReanalysisFileStore) -> Bool
    let source: ObservationReanalysisSource
    private let container: ModelContainer
    private let producer: ObservationCompositionProducer
    private let files: FileIOActor
    private let current: @MainActor @Sendable () -> Bool
    private let start: Start
    private var child: UUID?
    private var frozen: StagedCapture?
    private var payload: ObservationCompositionPayload?
    private var preparation: ObservationCompositionPreparation?
    private var ready = false
    private var submitting = false
    private var closed = false

    init(source: ObservationReanalysisSource, container: ModelContainer, producer: ObservationCompositionProducer,
         files: FileIOActor, current: @escaping @MainActor @Sendable () -> Bool, start: @escaping Start) {
        self.source = source; self.container = container; self.producer = producer
        self.files = files; self.current = current; self.start = start
    }

    var isFrozen: Bool { child != nil }

    static func requiresComposition(_ capture: StagedCapture) -> Bool {
        if capture.images.contains(where: { $0.focusRegion?.source == .userSelection }) { return true }
        let kinds = [!capture.images.isEmpty, !capture.audios.isEmpty, !capture.videos.isEmpty].filter { $0 }.count
        if kinds > 1 || capture.audios.count > 1 { return true }
        if !capture.videos.isEmpty, case .video = capture.orderedNodes.first { return false }
        return !capture.videos.isEmpty
    }

    static func accepts(_ capture: StagedCapture, ownedPaths: Set<String>) -> Bool {
        guard capture.nativePhotoDraft == nil, capture.videos.count <= 1, capture.audios.count <= 2,
              capture.physicalItemCount <= (capture.audios.isEmpty && capture.videos.isEmpty ? 5 : 2),
              capture.audios.allSatisfy({ ownedPaths.contains($0.filePath) }),
              capture.videos.allSatisfy({ ownedPaths.contains($0.filePath) }) else { return false }
        return true
    }

    func submit(_ capture: StagedCapture, ownedPaths: Set<String>) async throws -> UUID {
        guard !submitting else { throw ObservationHistoryError.unavailable }
        try validate()
        guard Self.accepts(capture, ownedPaths: ownedPaths), capture.physicalItemCount > 0 else { throw MerianError.invalidResponse }
        if frozen == nil { frozen = capture; child = UUID() }
        guard let frozen, let child else { throw ObservationHistoryError.unavailable }
        submitting = true
        defer { submitting = false }
        if !ready {
            if payload == nil {
                let prepared = try await prepare(frozen, child: child)
                try validate()
                preparation = try ObservationCompositionPreparation(request: prepared.request, source: source)
                payload = prepared
            }
            guard let preparation, let payload else { throw ObservationHistoryError.unavailable }
            _ = try await producer.prepare(preparation, source: source, payload: payload,
                container: container, isCurrent: { self.current() && !self.closed })
            ready = true
            self.payload = nil
        }
        try validate()
        guard let preparation else { throw ObservationHistoryError.unavailable }
        guard let continuation = try await ObservationCompositionResumeSubmission(producer: producer)
            .resume(preparation.identity, container: container, isCurrent: { self.current() && !self.closed }) else {
            throw ObservationHistoryError.unavailable
        }
        try validate()
        guard start(continuation, container, producer.files) else { throw ObservationHistoryError.unavailable }
        return child
    }

    func close() { closed = true }

    private func validate() throws {
        try Task.checkCancellation()
        guard !closed, current() else { throw ObservationHistoryError.accountChanged }
        try source.validate(container: container)
    }

    private func prepare(_ capture: StagedCapture, child: UUID) async throws -> ObservationCompositionPayload {
        var nodes: [[String: Any]] = [], standalone: [UUID: Data] = [:]
        let focused = source.composition?.schemaVersion == 6
            || capture.images.contains { $0.focusRegion?.source == .userSelection }
            || (source.initialEvidence != nil && capture.images.contains { $0.focusRegion != nil })
        var video: ObservationVideoCohort.Payload?
        for node in capture.orderedNodes {
            try validate()
            switch node {
            case let .description(_, value):
                nodes.append(["kind": "description", "text": value.context.freeText])
            case let .image(_, image):
                let original: ObservationHistoryPhotoReference?
                if case let .original(analysisID, reference) = image.reanalysisProvenance {
                    guard analysisID == source.analysisID else { throw MerianError.invalidResponse }
                    original = reference
                } else { original = nil }
                let bytes = image.compressedData, id = UUID()
                let photo = try await DetachedWork.value(category: .inferenceRequestPreparation) {
                    try ObservationReanalysisPhotoPreparation.prepare(bytes: bytes, mediaID: id, original: original)
                }
                try validate()
                standalone[id] = photo.bytes
                var item: [String: Any] = ["kind": "image", "artifact": Self.artifact(id, photo.reference.contentType, photo.bytes)]
                if focused, let focus = image.focusRegion {
                    guard focus.isValidEvidence else { throw MerianError.invalidResponse }
                    item["focus_region"] = focus.jsonObject
                }
                nodes.append(item)
            case let .audio(_, audio):
                guard let snapshot = await files.snapshotAudioFile(path: audio.filePath) else { throw MerianError.invalidResponse }
                let bytes: Data
                do {
                    try validate()
                    bytes = try await CaptureAudioInputPreparer(directory: FileManager.default.temporaryDirectory).prepare(snapshot.url)
                    guard await files.videoSnapshotIsCurrent(snapshot) else { throw ObservationHistoryError.resultConflict }
                } catch { await files.discardVideoSnapshot(snapshot); throw error }
                guard await files.discardVideoSnapshot(snapshot) else { throw ObservationHistoryError.resultConflict }
                try validate()
                let id = UUID(); standalone[id] = bytes
                nodes.append(["kind": "audio", "artifact": Self.artifact(id, "audio/wav", bytes)])
            case let .video(_, clip):
                guard video == nil, let snapshot = await files.snapshotVideoFile(filename: clip.filePath) else { throw MerianError.invalidResponse }
                do {
                    try validate()
                    let cohort = try await ObservationVideoCohortPreparer().prepare(source: snapshot.url,
                        directory: FileManager.default.temporaryDirectory, observationID: source.observationID,
                        analysisID: child, sourceAnalysisID: source.analysisID, descriptions: [],
                        cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
                    video = try await cohort.compositionPayload()
                    guard await files.videoSnapshotIsCurrent(snapshot) else { throw ObservationHistoryError.resultConflict }
                } catch { await files.discardVideoSnapshot(snapshot); throw error }
                guard await files.discardVideoSnapshot(snapshot) else { throw ObservationHistoryError.resultConflict }
                try validate()
                guard let video,
                      let manifest = try JSONSerialization.jsonObject(with: video.request.manifest.originalBytes) as? [String: Any],
                      let graph = manifest["provenance"] else { throw MerianError.invalidResponse }
                nodes.append(["kind": "video", "provenance": graph])
            }
        }
        let request = try ObservationCompositionReanalysisRequest(observationID: source.observationID, analysisID: child,
            sourceAnalysisID: source.analysisID,
            manifestBytes: JSONSerialization.data(withJSONObject: ["schema_version": focused ? 6 : 5, "items": nodes], options: [.sortedKeys, .withoutEscapingSlashes]))
        return try await DetachedWork.value(category: .inferenceRequestPreparation) { [standalone, video] in
            try ObservationCompositionPayload.prepare(request: request, standalone: standalone, video: video)
        }
    }

    private static func artifact(_ id: UUID, _ type: String, _ bytes: Data) -> [String: Any] {
        ["media_id": id.uuidString.lowercased(), "content_type": type, "byte_count": bytes.count,
         "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]
    }
}

extension CaptureWorkspaceCompositionReanalysis {
    func load() async throws -> StagedCapture {
        let source = try ObservationCompositionSource.capture(observationID: self.source.observationID,
            analysisID: self.source.analysisID, ownerID: self.source.ownerID, container: container)
        let loader = ObservationHistoryMediaLoader(account: producer.account)
        var capture = StagedCapture(), owned: [String] = []
        do {
            try validate()
            for (index, node) in source.nodes.enumerated() {
                let order = Date(timeIntervalSince1970: TimeInterval(index))
                switch node {
                case let .description(text): capture.observationContexts.append(.init(context: .init(freeText: text), addedAt: order))
                case let .video(manifest):
                    capture.videos.append(try await stageVideo(source: source, playback: manifest.provenance.source,
                        frames: manifest.provenance.frames.map(\.artifact), audio: manifest.provenance.audio?.artifact,
                        order: order, allowsReframing: true, owned: &owned))
                case let .initialVideo(video):
                    // Keep ordinary playback and its sampled frame/audio roles.
                    // A new child preparation, not decoding, creates a recipe.
                    capture.videos.append(try await stageVideo(source: source, playback: video.playback,
                        frames: video.frames, audio: video.audio?.prepared, order: order,
                        allowsReframing: video.source.sha256 == video.playback.sha256
                            && video.source.byteCount == video.playback.byteCount, owned: &owned))
                case let .audio(artifact):
                    let bytes = try await loader.load(source: source, artifact: artifact, container: container, isCurrent: current)
                    try validate()
                    guard let path = await files.stageHistoryAudio(bytes) else { throw ObservationHistoryError.invalidSnapshot }
                    owned.append(path)
                    capture.audios.append(.init(filePath: path, addedAt: order))
                case let .image(artifact):
                    let bytes = try await loader.load(source: source, artifact: artifact, container: container, isCurrent: current)
                    try validate()
                    let reference = ObservationHistoryPhotoReference(mediaID: artifact.mediaID, contentType: artifact.contentType,
                        byteCount: artifact.byteCount, sha256: artifact.sha256)
                    let preview = try await DetachedWork.value(category: .imagePreparation) {
                        _ = try ObservationReanalysisPhotoPreparation.prepare(bytes: bytes, mediaID: artifact.mediaID, original: reference)
                        guard let image = ImageDownsampler.downsampledSendableImage(data: bytes, maxSize: 2048) else { throw ObservationHistoryError.invalidSnapshot }
                        return image
                    }
                    try validate()
                    let image = UIImage(cgImage: preview.cgImage)
                    let focus = source.imageFocusRegions[artifact.mediaID]
                    var original = IdentifiableImage(image: image)
                    original.allowsReframing = source.permitsPhotoReframing(artifact.mediaID)
                    // This accepted artifact is the new retained source, so its
                    // final-byte focus is already in the source's upright basis.
                    if focus?.source == .userSelection { original.manualSourceSelection = focus }
                    capture.images.append(.init(compressedData: bytes, displayData: bytes, uiImage: image,
                        original: original, focusRegion: focus, addedAt: order,
                        reanalysisProvenance: .original(analysisID: source.analysisID, photo: reference),
                        reviewBasis: .preparedArtifact(sha256: artifact.sha256)))
                }
            }
            try validate()
            guard capture.physicalItemCount > 0 else { throw ObservationHistoryError.unavailable }
            return capture
        } catch {
            await files.deleteFiles(at: owned)
            throw error
        }
    }

    private func stageVideo(source: ObservationCompositionSource, playback: ObservationVideoProvenance.Artifact,
                            frames: [ObservationVideoProvenance.Artifact], audio: ObservationVideoProvenance.Artifact?,
                            order: Date, allowsReframing: Bool, owned: inout [String]) async throws -> StagedVideo {
        let clip = try await ObservationHistoryMediaLoader(account: producer.account)
            .load(source: source, artifact: playback, container: container, isCurrent: current)
        try validate()
        guard let path = await files.stageHistoryVideo(clip) else { throw ObservationHistoryError.invalidSnapshot }
        owned.append(path)
        let loader = ObservationHistoryMediaLoader(account: producer.account)
        var images: [StagedImage] = []
        for frame in frames {
            let bytes = try await loader.load(source: source, artifact: frame, container: container, isCurrent: current)
            try validate()
            guard let image = UIImage(data: bytes) else { throw ObservationHistoryError.invalidSnapshot }
            images.append(.init(compressedData: bytes, displayData: bytes, uiImage: image,
                original: .init(image: image, isFromGallery: false), addedAt: order))
        }
        var audioPath: String?
        if let audio {
            let bytes = try await loader.load(source: source, artifact: audio, container: container, isCurrent: current)
            try validate()
            guard let path = await files.stageHistoryAudio(bytes) else { throw ObservationHistoryError.invalidSnapshot }
            owned.append(path); audioPath = path
        }
        try validate()
        return .init(filePath: path, sampledImages: images, audioFilePath: audioPath, addedAt: order,
            allowsReframing: allowsReframing)
    }

    func discardStaging(_ capture: StagedCapture) async { await files.deleteFiles(at: capture.discardableLocalMediaFilePaths) }
}
