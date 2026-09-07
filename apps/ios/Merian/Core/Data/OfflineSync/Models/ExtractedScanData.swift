import Foundation
import SwiftData

// MARK: - Extracted Scan Data

/// Sendable snapshot of `OfflineQueuedScan` metadata captured on the main actor.
///
/// Passed across the actor boundary into `dispatchInferenceDownloadTask` so that
/// background inference can proceed without touching the main-actor-bound `ModelContext`.
struct ExtractedScanData: Sendable {
    /// Environmental and capture telemetry for the scan, used as Gemini inference context.
    let telemetry: CaptureTelemetry
    /// Confirmed R2 object keys stored at upload time.
    /// Non-empty on the offline queue path; empty on the live inference path.
    let r2Keys: [String]
    /// The model container, used to create a new `BackgroundDatabaseActor` on the inference thread.
    let container: ModelContainer
    let originalTimestamp: Date
    /// Canonical persisted media timeline from the queued scan, preserving mixed-media order.
    let capturedMediaItems: [SerializedMediaItem]
    /// Documents-relative images used for inference replay. New video rows keep sampled frames here
    /// while `capturedMediaItems` keeps only the display/share timeline.
    let inferenceImagePaths: [String]?
    /// Encoded `[IdentifyVisualMediaItem]` aligned to `inferenceImagePaths`.
    let visualMediaItemsJSON: String?
    /// Durable live-Capture preference carried through foreground and background completion.
    let preferredGoal: FieldTripPreferredGoal?

    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: capturedMediaItems)
    }

    var submissionMediaProjection: CaptureSubmissionMediaProjection {
        capturedMediaSnapshot.submissionMediaProjection
    }

    /// Filenames of local inference images relative to the Documents directory.
    var localImagePaths: [String] {
        if let inferenceImagePaths, !inferenceImagePaths.isEmpty {
            return inferenceImagePaths
        }
        return capturedMediaSnapshot.thumbnailImagePaths
    }

    var localUploadPaths: [String] {
        localImagePaths + (audioFilePaths ?? []) + (videoFilePaths ?? [])
    }

    /// Pre-serialized `ObservationContext` text for combined image+description scans.
    var description: String? {
        capturedMediaSnapshot.descriptionText
    }

    /// Raw `ObservationContext` JSON string forwarded to the edge function as `observation_context`
    /// and persisted in the `scans` table. Separate from `description` (plain-text for Gemini).
    /// `nil` for image-only scans.
    var observationContextsJSON: [String]? {
        capturedMediaSnapshot.observationContextsJSON
    }

    /// Audio inference paths in the exact same order as `audioMediaItems`.
    ///
    /// This order must come from one shared projection. Grouping standalone audio
    /// ahead of video-extracted audio can make the Edge Function promote and delete
    /// the opposite clips when the mixed-media timeline is interleaved.
    var audioFilePaths: [String]? {
        let paths = submissionMediaProjection.audioFilePaths
        return paths.isEmpty ? nil : paths
    }

    var videoFilePaths: [String]? {
        let paths = capturedMediaSnapshot.videoPaths
        return paths.isEmpty ? nil : paths
    }

    var visualMediaItems: [IdentifyVisualMediaItem]? {
        guard let visualMediaItemsJSON,
              let data = visualMediaItemsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([IdentifyVisualMediaItem].self, from: data),
              !decoded.isEmpty else {
            return nil
        }
        return decoded
    }

    var audioMediaItems: [IdentifyAudioMediaItem]? {
        let items = submissionMediaProjection.audioMediaItems
        return items.isEmpty ? nil : items
    }

    var ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]? {
        let projection = submissionMediaProjection
        let timeline = projection.ownerMediaTimeline
        guard !timeline.isEmpty else { return nil }

        // Persisted standalone-audio identities can be sparse after a partial legacy
        // repair. Preserve those descriptors, but do not claim a new authoritative
        // timeline unless the durable source identities are complete zero-based ordinals.
        let standaloneAudioSourceIndexes = projection.audioMediaItems.compactMap { item in
            item.kind == .audio ? item.sourceIndex : nil
        }
        guard standaloneAudioSourceIndexes.sorted()
                == Array(0..<standaloneAudioSourceIndexes.count) else {
            return nil
        }

        let ownerImageIndexes = timeline.compactMap { item in
            item.kind == .image ? item.sourceIndex : nil
        }
        let ownerVideoIndexes = timeline.compactMap { item in
            item.kind == .video ? item.clipIndex : nil
        }
        guard !ownerImageIndexes.isEmpty || !ownerVideoIndexes.isEmpty else {
            return timeline
        }

        // Older queued visual records predate persisted visual descriptors. Sending a
        // reconstructed timeline for them would turn a safe legacy replay into a strict
        // validation failure, so only opt into the new contract when every visual input
        // and owner-visible source can be proven locally.
        guard let visualMediaItems,
              visualMediaItems.count == localImagePaths.count,
              ownerImageIndexes.sorted() == Array(0..<ownerImageIndexes.count),
              ownerVideoIndexes.sorted() == Array(0..<ownerVideoIndexes.count),
              ownerVideoIndexes.count == (videoFilePaths?.count ?? 0) else {
            return nil
        }
        let visualImageIndexes = visualMediaItems.compactMap { item in
            item.kind == .image ? item.sourceIndex : nil
        }
        let videoFrameClipIndexes = visualMediaItems.compactMap { item in
            item.kind == .videoFrame ? item.clipIndex : nil
        }
        let ownerVideoIndexSet = Set(ownerVideoIndexes)
        guard visualImageIndexes.sorted() == ownerImageIndexes.sorted(),
              videoFrameClipIndexes.allSatisfy(ownerVideoIndexSet.contains),
              ownerVideoIndexSet.isSubset(of: Set(videoFrameClipIndexes)) else {
            return nil
        }
        return timeline
    }

    var capturedMediaJSON: String? {
        capturedMediaSnapshot.jsonString
    }
}

// MARK: - Offline Scan Processing Result

/// Result returned by `BackgroundDatabaseActor.processAndCleanupOfflineScan`.
struct OfflineScanProcessingResult {
    let resolvedSpeciesName: String?
    let isNewDiscovery: Bool
    let finalScanId: String?
    /// The fully-parsed result, present when inference succeeded (confidenceScore > 0).
    /// Passed back to the main actor so the live InferenceEngine can be hydrated directly
    /// when the background path races ahead of the suspended live inference task.
    let speciesData: SpeciesData?
    /// True when the background context's save committed (inserting the `LocalScanRecord` on
    /// success, or a no-op save on a confidence==0 failure). When true, the caller must delete
    /// the `OfflineQueuedScan` through the main actor's queue path.
    ///
    /// The background context intentionally does NOT delete the `OfflineQueuedScan`. Delegating
    /// the deletion to the main actor guarantees the main `ModelContext` always has a real
    /// pending change when it saves — the only reliable way to trigger `@Query` re-evaluation
    /// in a presented sheet (SwiftData platform limitation: background context saves do not
    /// reliably propagate to `@Query` in open sheets via remote change notifications).
    let wasCleaned: Bool
}
