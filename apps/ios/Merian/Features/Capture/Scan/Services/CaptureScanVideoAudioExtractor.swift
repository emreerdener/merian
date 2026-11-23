import AVFoundation
import Foundation

enum CaptureScanVideoAudioExtractor {
    nonisolated static func extract(
        videoURL: URL,
        outputDirectory: URL = .documentsDirectory
    ) async -> CaptureScanTemporaryFileLease? {
        await withArtifacts { artifacts in
            guard await FileIOActor.shared.retryProducerCleanup() else { throw SharedMediaStorageFailure.unavailable }
            try Task.checkCancellation()
            let asset = AVURLAsset(url: videoURL)
            guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { return nil }
            let producer = try MediaProducerOutput(fileExtension: "wav")
            do {
                // Decode the asset timeline, including empty edits. ExtAudioFile
                // alone reads contiguous packets and loses video soundtrack gaps.
                try await CaptureScanVideoAudioTimeline.write(asset: asset, output: producer)
                guard InferenceAudioPreparer.isCanonicalPreparedWAV(at: producer.outputURL) else {
                    throw InferenceAudioPreparationError.invalidAudio
                }
                let (url, receipt) = try await producer.publish(to: outputDirectory,
                    suffix: "video-audio.wav", maximumBytes: ScanMediaPayloadPolicy.maxInferenceAudioBytes)
                let lease = CaptureScanTemporaryFileLease(fileURL: url, retirement: receipt)
                await artifacts.insert(lease)
                try Task.checkCancellation()
                return lease
            } catch {
                _ = await FileIOActor.shared.settleProducerCleanup(owner: producer) { try await producer.discardAfterExit() }
                throw error
            }
        }
    }

    /// The same owner is used by the live extractor and deterministic late-output tests.
    nonisolated private static func withArtifacts(
        operation: @Sendable @escaping (AudioArtifacts) async throws -> CaptureScanTemporaryFileLease?
    ) async -> CaptureScanTemporaryFileLease? {
        let artifacts = AudioArtifacts()
        // Observe actual worker completion before applying caller cancellation.
        let worker = Task.detached(priority: .utility) { try await operation(artifacts) }
        do {
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            let accepted = Task.isCancelled ? nil : result
            await artifacts.discardAll(except: accepted)
            return accepted
        } catch {
            await artifacts.discardAll(except: nil)
            if !(error is CancellationError) {
                MerianLog.hardware.error(
                    "Video audio extraction task failed: \(error, privacy: .private)"
                )
            }
            return nil
        }
    }

    #if DEBUG
    nonisolated static func qualifyArtifactLifecycle(
        operation: @Sendable @escaping (
            @Sendable (URL) async -> CaptureScanTemporaryFileLease
        ) async throws -> CaptureScanTemporaryFileLease?
    ) async -> CaptureScanTemporaryFileLease? {
        await withArtifacts { artifacts in
            try await operation { url in
                let lease = CaptureScanTemporaryFileLease(fileURL: url)
                await artifacts.insert(lease)
                return lease
            }
        }
    }
    #endif

    private actor AudioArtifacts {
        private var leases: [CaptureScanTemporaryFileLease] = []
        func insert(_ lease: CaptureScanTemporaryFileLease) { leases.append(lease) }
        func discardAll(except accepted: CaptureScanTemporaryFileLease?) async {
            for lease in leases where lease !== accepted { await lease.discardReportingFailure() }
            leases.removeAll()
        }
    }
}
