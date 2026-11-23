import Foundation
import SwiftData
import UIKit

/// One staged clip uses the existing durable video owner. Derived frames and
/// companion sound remain part of that clip, never extra toolbar submissions.
@MainActor
final class CaptureWorkspaceVideoReanalysis {
    typealias HostFactory = (HistoricalReanalysisTarget, ModelContainer) throws -> CaptureVideoReanalysisHost
    let source: ObservationCompositionSource
    private let container: ModelContainer
    private let loader: ObservationHistoryMediaLoader
    private let files: FileIOActor
    private let makeHost: HostFactory
    private let current: @MainActor () -> Bool
    private var host: CaptureVideoReanalysisHost?
    private var submitted: StagedCapture?

    init(source: ObservationCompositionSource, container: ModelContainer, loader: ObservationHistoryMediaLoader,
         files: FileIOActor, makeHost: @escaping HostFactory, current: @escaping @MainActor () -> Bool) {
        self.source = source; self.container = container; self.loader = loader; self.files = files
        self.makeHost = makeHost; self.current = current
    }

    var isFrozen: Bool { host?.isFrozen == true }

    func load() async throws -> StagedCapture {
        var capture = StagedCapture(), owned: [String] = []
        do {
            try validate()
            for (index, node) in source.nodes.enumerated() {
                let order = Date(timeIntervalSince1970: TimeInterval(index))
                switch node {
                case let .description(text): capture.observationContexts.append(.init(context: .init(freeText: text), addedAt: order))
                case let .video(manifest):
                    let clip = try await loader.load(source: source, artifact: manifest.provenance.source, container: container, isCurrent: current)
                    try validate()
                    guard let path = await files.stageHistoryVideo(clip) else { throw ObservationHistoryError.invalidSnapshot }
                    owned.append(path)
                    var images: [StagedImage] = []
                    for frame in manifest.provenance.frames {
                        let bytes = try await loader.load(source: source, artifact: frame.artifact, container: container, isCurrent: current)
                        try validate()
                        guard let image = UIImage(data: bytes) else { throw ObservationHistoryError.invalidSnapshot }
                        images.append(.init(compressedData: bytes, displayData: bytes, uiImage: image,
                            original: .init(image: image, isFromGallery: false), addedAt: order))
                    }
                    var audioPath: String?
                    if let audio = manifest.provenance.audio {
                        let bytes = try await loader.load(source: source, artifact: audio.artifact, container: container, isCurrent: current)
                        try validate()
                        guard let path = await files.stageHistoryAudio(bytes) else { throw ObservationHistoryError.invalidSnapshot }
                        owned.append(path); audioPath = path
                    }
                    capture.videos.append(.init(filePath: path, sampledImages: images, audioFilePath: audioPath, addedAt: order))
                default: throw ObservationHistoryError.unavailable
                }
            }
            try validate()
            guard capture.videos.count == 1 else { throw ObservationHistoryError.unavailable }
            return capture
        } catch {
            await files.deleteFiles(at: owned)
            throw error
        }
    }

    func submit(_ capture: StagedCapture, ownedPaths: Set<String>) async throws -> UUID {
        try validate()
        let value = submitted ?? capture
        guard value.images.isEmpty, value.audios.isEmpty, value.videos.count == 1 else { throw ObservationHistoryError.unavailable }
        // The existing video generation stores the clip followed by descriptions.
        // A timeline with earlier notes belongs to the ordered composition owner.
        guard case .video = value.orderedNodes.first else { throw ObservationHistoryError.unavailable }
        if host == nil {
            host = try makeHost(.init(observationID: source.observationID, analysisID: source.analysisID, ownerID: source.ownerID), container)
        }
        guard let host else { throw ObservationHistoryError.unavailable }
        submitted = value
        let result: CaptureVideoResumeAccess.Admission
        do {
            result = try await host.submitFromWorkspace(path: value.videos[0].filePath, ownedPaths: ownedPaths,
                descriptions: value.observationContexts.sorted { $0.addedAt < $1.addedAt }.map(\.context.freeText))
        } catch {
            if !host.isFrozen { submitted = nil }
            throw error
        }
        try validate()
        guard result != .unavailable, let id = host.analysisID else { throw ObservationHistoryError.unavailable }
        return id
    }

    func close() { host?.close() }
    func discardStaging(_ capture: StagedCapture) async { await files.deleteFiles(at: capture.discardableLocalMediaFilePaths) }

    private func validate() throws {
        try Task.checkCancellation()
        guard current() else { throw ObservationHistoryError.accountChanged }
        try source.validate(container: container)
    }
}
