import CryptoKit
import Foundation

/// One temporary ownership unit. No per-file or durable transfer API exists.
actor ObservationVideoCohort {
    fileprivate struct File: Sendable {
        let artifact: ObservationVideoProvenance.Artifact
        let url: URL
    }
    nonisolated let request: ObservationVideoReanalysisRequest
    private let files: [File]
    private let directory: URL
    private let clip: ObservationRetainedVideoClip
    private let frames: ObservationVideoFrameDerivation
    private let audio: ObservationVideoAudioDerivation?

    fileprivate init(request: ObservationVideoReanalysisRequest, files: [File], directory: URL,
                     clip: ObservationRetainedVideoClip, frames: ObservationVideoFrameDerivation, audio: ObservationVideoAudioDerivation?) {
        self.request = request; self.files = files; self.directory = directory
        self.clip = clip; self.frames = frames; self.audio = audio
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

enum ObservationVideoCohortPhase: Sendable, Equatable {
    case retained, frames, audio, beforeHandoff
}

enum ObservationVideoCohortError: Error {
    case busy, invalidScope, changedArtifact
}

/// Uninstalled composition boundary; one joined worker owns all preparation and cleanup.
actor ObservationVideoCohortPreparer {
    private var occupied = false
    private let validate: @Sendable (ObservationVideoCohortPhase) async throws -> Void

    init(validate: @escaping @Sendable (ObservationVideoCohortPhase) async throws -> Void = { _ in }) {
        self.validate = validate
    }

    func prepare(source: URL, directory: URL, observationID: UUID, analysisID: UUID, sourceAnalysisID: UUID,
                 descriptions: [String], cropCenterBasisPoints: Int, inferenceLongEdge: Int) async throws -> ObservationVideoCohort {
        guard !occupied else { throw ObservationVideoCohortError.busy }
        guard Set([observationID, analysisID, sourceAnalysisID]).count == 3 else { throw ObservationVideoCohortError.invalidScope }
        try ObservationVideoFrameDeriver.validateParameters(directory: directory, cropCenterBasisPoints: cropCenterBasisPoints, inferenceLongEdge: inferenceLongEdge)
        try ObservationVideoManifest.validateDescriptions(descriptions)
        try Task.checkCancellation()
        occupied = true
        defer { occupied = false }
        let validate = validate
        let worker = Task.detached(priority: .utility) {
            try await Self.compose(source: source, directory: directory, observationID: observationID, analysisID: analysisID,
                                   sourceAnalysisID: sourceAnalysisID, descriptions: descriptions, cropCenterBasisPoints: cropCenterBasisPoints,
                                   inferenceLongEdge: inferenceLongEdge, validate: validate)
        }
        return try await withTaskCancellationHandler {
            let cohort = try await worker.value
            try Task.checkCancellation()
            return cohort
        } onCancel: { worker.cancel() }
    }

    private nonisolated static func compose(
        source: URL, directory: URL, observationID: UUID, analysisID: UUID, sourceAnalysisID: UUID,
        descriptions: [String], cropCenterBasisPoints: Int, inferenceLongEdge: Int,
        validate: @Sendable (ObservationVideoCohortPhase) async throws -> Void
    ) async throws -> ObservationVideoCohort {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let owned = directory.appendingPathComponent("video-cohort-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: owned) } }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: source, directory: owned)
        let use = try await clip.beginDerivation()
        let reserved = Set([observationID, analysisID, sourceAnalysisID])
        var sourceID = UUID()
        while reserved.contains(sourceID) { sourceID = UUID() }
        let retained = try use.artifact(mediaID: sourceID)
        try await validate(.retained)
        try Task.checkCancellation()
        try verify(.init(artifact: retained, url: use.url))
        let frames = try await ObservationVideoFrameDeriver.prepare(source: use, sourceMediaID: sourceID, directory: owned,
                                                                   cropCenterBasisPoints: cropCenterBasisPoints, inferenceLongEdge: inferenceLongEdge,
                                                                   validate: { _ in try Task.checkCancellation() })
        guard frames.source == retained else { throw ObservationVideoCohortError.changedArtifact }
        try await validate(.frames)
        try Task.checkCancellation()
        try verify(.init(artifact: frames.source, url: use.url))
        let audio = try await ObservationVideoAudioDeriver.prepare(use: use, sourceMediaID: sourceID, directory: owned,
                                                                  validate: { _ in try Task.checkCancellation() }, afterWrite: {})
        try await validate(.audio)
        try Task.checkCancellation()
        guard audio == nil || audio?.source == frames.source else { throw ObservationVideoCohortError.changedArtifact }
        let manifest = try ObservationVideoManifest.prepared(source: frames.source, parameters: frames.parameters, frames: frames.frames,
                                                            audio: audio?.audio, descriptions: descriptions, observationID: observationID, analysisID: analysisID)
        let request = try ObservationVideoReanalysisRequest(observationID: observationID, analysisID: analysisID,
                                                           sourceAnalysisID: sourceAnalysisID, manifestBytes: manifest.originalBytes)
        guard try ObservationVideoReanalysisRequest(savedBody: request.body) == request else { throw ObservationVideoCohortError.invalidScope }
        var files: [ObservationVideoCohort.File] = [.init(artifact: frames.source, url: use.url)]
        files += zip(frames.frames, frames.files).map { .init(artifact: $0.0.artifact, url: $0.1) }
        if let audio { files.append(.init(artifact: audio.audio.artifact, url: audio.file)) }
        guard files.count == (audio == nil ? 6 : 7) else { throw ObservationVideoCohortError.invalidScope }
        try await validate(.beforeHandoff)
        try Task.checkCancellation()
        for file in files { try verify(file) }
        try Task.checkCancellation()
        let result = ObservationVideoCohort(request: request, files: files, directory: owned, clip: clip, frames: frames, audio: audio)
        complete = true
        return result
    }

    private nonisolated static func verify(_ file: ObservationVideoCohort.File) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue == file.artifact.byteCount else { throw ObservationVideoCohortError.changedArtifact }
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: file.artifact.byteCount + 1) ?? Data()
        guard bytes.count == file.artifact.byteCount,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == file.artifact.sha256 else {
            throw ObservationVideoCohortError.changedArtifact
        }
    }
}
