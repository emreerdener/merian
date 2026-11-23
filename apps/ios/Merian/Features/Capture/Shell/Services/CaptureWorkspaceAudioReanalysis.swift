import Foundation
import SwiftData

/// Shared-toolbar adapter to the existing retained audio source/execution owner.
/// File staging is disposable; only the existing session may freeze durable work.
@MainActor
final class CaptureWorkspaceAudioReanalysis {
    typealias HostFactory = (HistoricalReanalysisTarget, ModelContainer) throws -> CaptureAudioReanalysisHost
    let source: ObservationCompositionSource
    private let container: ModelContainer
    private let loader: ObservationHistoryMediaLoader
    private let files: FileIOActor
    private let documents: URL
    private let makeHost: HostFactory
    private let current: @MainActor () -> Bool
    private var host: CaptureAudioReanalysisHost?
    private var choices: [CaptureAudioReanalysisPlan.Choice]?

    init(source: ObservationCompositionSource, container: ModelContainer, loader: ObservationHistoryMediaLoader,
         files: FileIOActor, documents: URL, makeHost: @escaping HostFactory, current: @escaping @MainActor () -> Bool) {
        self.source = source; self.container = container; self.loader = loader; self.files = files
        self.documents = documents; self.makeHost = makeHost; self.current = current
    }

    var isFrozen: Bool { choices != nil || host?.isFrozen == true }

    func load() async throws -> StagedCapture {
        var capture = StagedCapture(), owned: [String] = []
        do {
            try validate()
            for (index, node) in source.nodes.enumerated() {
                let order = Date(timeIntervalSince1970: TimeInterval(index))
                switch node {
                case let .description(text): capture.observationContexts.append(.init(context: .init(freeText: text), addedAt: order))
                case let .audio(artifact):
                    let bytes = try await loader.load(source: source, artifact: artifact, container: container, isCurrent: current)
                    try validate()
                    guard let path = await files.stageHistoryAudio(bytes) else { throw ObservationHistoryError.invalidSnapshot }
                    owned.append(path)
                    try validate()
                    capture.audios.append(.init(filePath: path, addedAt: order))
                default: throw ObservationHistoryError.unavailable
                }
            }
            guard capture.audios.count == 1 else { throw ObservationHistoryError.unavailable }
            try validate()
            return capture
        } catch {
            await files.deleteFiles(at: owned)
            throw error
        }
    }

    func submit(_ capture: StagedCapture, ownedPaths: Set<String>) async throws -> UUID {
        try validate()
        guard capture.images.isEmpty, capture.videos.isEmpty, capture.audios.count == 1 else { throw ObservationHistoryError.unavailable }
        if choices == nil {
            let path = capture.audios[0].filePath
            guard ownedPaths.contains(path), !path.contains("\0"),
                  !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { throw ObservationHistoryError.unavailable }
            guard let snapshot = await files.snapshotAudioFile(path: path) else { throw ObservationHistoryError.unavailable }
            let bytes: Data
            do {
                try validate()
                bytes = try await CaptureAudioInputPreparer(directory: FileManager.default.temporaryDirectory).prepare(snapshot.url)
                guard await files.videoSnapshotIsCurrent(snapshot) else { throw ObservationHistoryError.resultConflict }
            } catch {
                await files.discardVideoSnapshot(snapshot)
                throw error
            }
            guard await files.discardVideoSnapshot(snapshot) else { throw ObservationHistoryError.resultConflict }
            try validate()
            let value: [CaptureAudioReanalysisPlan.Choice] = try capture.orderedNodes.map { node in
                switch node {
                case .audio: return .audio(bytes)
                case let .description(_, note): return .description(note.context.freeText)
                default: throw ObservationHistoryError.unavailable
                }
            }
            let opened = try makeHost(.init(observationID: source.observationID, analysisID: source.analysisID, ownerID: source.ownerID), container)
            guard opened.isCurrent else { throw ObservationHistoryError.accountChanged }
            host = opened
            choices = value
        }
        guard let choices, let host else { throw ObservationHistoryError.unavailable }
        let result: CaptureAudioReanalysisSession.SourceAdmission
        do { result = try await host.submitFromWorkspace(choices) } catch {
            if !host.isFrozen { self.choices = nil }
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
