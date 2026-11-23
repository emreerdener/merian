import Foundation
import SwiftData

/// Exact displayed result for the shared toolbar. This explicit capability does
/// not widen the old photo/audio/video submission codecs or their recovery paths.
struct ObservationCompositionSource: Equatable, Sendable {
    typealias Artifact = ObservationVideoProvenance.Artifact
    enum Node: Equatable, Sendable {
        case image(Artifact), audio(Artifact), video(ObservationVideoManifest), description(String)
        case initialVideo(ObservationInitialEvidence.Video)
    }
    let ownerID: UUID
    let observationID: UUID
    let analysisID: UUID
    let snapshot: Data
    let nodes: [Node]
    let imageFocusRegions: [UUID: NormalizedImageFocusRegion]
    let initialEvidence: ObservationInitialEvidence?

    var resolutionProtocol: Int {
        guard let initialEvidence else { return 1 }
        return initialEvidence.manifestVersion >= 8 ? 3 : 2
    }

    func isRetainedOriginalImage(_ artifact: Artifact) -> Bool {
        guard let initialEvidence, initialEvidence.manifestVersion >= 8 else { return false }
        return initialEvidence.items.contains { item in
            if case let .image(source, _, _) = item { return source == artifact }
            return false
        }
    }

    /// Without a recorded source-to-prepared transform, reframing a prepared
    /// photo would compound a previous crop. Selection still uses its exact
    /// prepared-image basis, and a replacement can supply a new editing source.
    func permitsPhotoReframing(_ id: UUID) -> Bool {
        guard let initialEvidence else { return true }
        for item in initialEvidence.items {
            if case let .image(source, prepared, _) = item, prepared.mediaID == id {
                return source.sha256 == prepared.sha256 && source.byteCount == prepared.byteCount
                    && source.contentType == prepared.contentType
            }
        }
        return false
    }

    var artifacts: [Artifact] {
        if let initialEvidence { return initialEvidence.artifacts }
        return nodes.flatMap { node in
            switch node {
            case let .image(value), let .audio(value): return [value]
            case let .video(value):
                let graph = value.provenance
                return [graph.source] + graph.frames.map(\.artifact) + (graph.audio.map { [$0.artifact] } ?? [])
            case .description: return []
            case let .initialVideo(video):
                return [video.source, video.playback] + video.frames
                    + (video.audio.map { [$0.source, $0.prepared] } ?? [])
            }
        }
    }

    /// Pure decoding for tests and captured, already owner-bound local results.
    /// No network or persistence authority is conferred by this value.
    init(ownerID: UUID, observationID: UUID, result: ObservationHistoryPage.Result) throws {
        guard (1...8).contains(result.version) else { throw ObservationHistoryError.unavailable }
        self.ownerID = ownerID; self.observationID = observationID; analysisID = result.analysisID; snapshot = result.bytes
        initialEvidence = result.initialEvidence
        if result.version == 8 {
            guard let initialEvidence, initialEvidence.ownerID == ownerID else { throw ObservationHistoryError.invalidSnapshot }
            var focuses: [UUID: NormalizedImageFocusRegion] = [:]
            nodes = initialEvidence.items.map { item in
                switch item {
                case let .image(_, prepared, focus):
                    focuses[prepared.mediaID] = focus
                    return .image(prepared)
                case let .audio(audio): return .audio(audio.prepared)
                case let .video(video): return .initialVideo(video)
                case let .description(text): return .description(text)
                }
            }
            imageFocusRegions = focuses
            return
        }
        guard initialEvidence == nil else { throw ObservationHistoryError.invalidSnapshot }
        imageFocusRegions = result.composition?.imageFocusRegions ?? [:]
        let row = try JSONSerialization.jsonObject(with: result.bytes) as? [String: Any]
        switch result.version {
        case 2:
            nodes = try ObservationHistoryPhotoReference.decodeEvidence(row?["evidence_manifest"],
                observationID: observationID, analysisID: result.analysisID).map {
                switch $0 {
                case let .description(text): return .description(text)
                case let .photo(photo): return .image(.init(mediaID: photo.mediaID, contentType: photo.contentType,
                    byteCount: photo.byteCount, sha256: photo.sha256))
                }
            }
        case 4:
            // Validate the entire manifest before preserving its original order.
            let audio = try ObservationHistoryAudioReference.decodeManifest(row?["evidence_manifest"],
                observationID: observationID, analysisID: result.analysisID)
            guard let manifest = row?["evidence_manifest"] as? [String: Any],
                  let items = manifest["items"] as? [[String: Any]] else { throw ObservationHistoryError.invalidSnapshot }
            nodes = try items.map { item in
                if item["kind"] as? String == "description" {
                    guard let text = item["text"] as? String else { throw ObservationHistoryError.invalidSnapshot }
                    return .description(text)
                }
                return .audio(.init(mediaID: audio.mediaID, contentType: audio.contentType,
                    byteCount: audio.byteCount, sha256: audio.sha256))
            }
        case 6, 7:
            guard let composition = result.composition else { throw ObservationHistoryError.invalidSnapshot }
            nodes = try composition.items.map { item in
                switch item {
                case let .image(artifact): return .image(artifact)
                case let .audio(artifact): return .audio(artifact)
                case let .description(text): return .description(text)
                case let .video(graph):
                    // Derived frames/audio stay attached to their original clip.
                    return .video(try ObservationVideoManifest.prepared(source: graph.source, parameters: graph.parameters,
                        frames: graph.frames, audio: graph.audio, descriptions: [],
                        observationID: observationID, analysisID: result.analysisID))
                }
            }
        case 5:
            guard let video = result.video else { throw ObservationHistoryError.invalidSnapshot }
            // This stored generation defines one clip followed by descriptions.
            // Its frames/companion audio never become separate toolbar items.
            nodes = [.video(video)] + video.descriptions.map(Node.description)
        default:
            // V1/V3 have no immutable original-artifact membership. Never borrow
            // the mutable observation's cover, files or Field notes.
            nodes = []
        }
    }

    @MainActor
    static func capture(observationID: UUID, analysisID: UUID, ownerID: UUID, container: ModelContainer) throws -> Self {
        try ConfirmedSpeciesReviewPersistence.transaction {
            try read(observationID: observationID, analysisID: analysisID, ownerID: ownerID, context: ModelContext(container))
        }
    }

    @MainActor
    private static func read(observationID: UUID, analysisID: UUID, ownerID: UUID, context: ModelContext) throws -> Self {
        let scan = try ObservationHistorySyncService.enrolledScan(observationID.uuidString, context: context)
        guard scan.analysisOwnerAccountID == ownerID.uuidString.lowercased(),
              !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else { throw ObservationHistoryError.unavailable }
        let id = analysisID.uuidString.lowercased()
        var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 1
        guard let record = try context.fetch(query).first, record.observationID == scan.id,
              record.ownerAccountID == scan.analysisOwnerAccountID,
              record.resultSnapshotData.count <= LocalAnalysisRecord.maximumSnapshotBytes else { throw ObservationHistoryError.unavailable }
        let row = try JSONSerialization.jsonObject(with: record.resultSnapshotData) as? [String: Any]
        let result = try ObservationHistoryPage.snapshot(record.resultSnapshotData,
            observationID: observationID.uuidString.lowercased(), ordinal: ObservationHistoryPage.integer(row?["ordinal"]))
        guard result.analysisID == analysisID, result.version == record.snapshotVersion, result.completedAt == record.completedAt else {
            throw ObservationHistoryError.resultConflict
        }
        return try Self(ownerID: ownerID, observationID: observationID, result: result)
    }

    /// Caller owns the shared persistence transaction. Later current selection
    /// does not change this source; deletion or snapshot replacement does.
    @MainActor func validate(context: ModelContext) throws {
        guard try Self.read(observationID: observationID, analysisID: analysisID, ownerID: ownerID, context: context) == self else {
            throw ObservationHistoryError.resultConflict
        }
    }
    @MainActor func validate(container: ModelContainer) throws {
        try ConfirmedSpeciesReviewPersistence.transaction { try validate(context: ModelContext(container)) }
    }
}
