#if DEBUG && targetEnvironment(simulator)
import AVFoundation
import Foundation

/// Interactive simulator input only. No launch argument, provider call, or queue write.
enum CaptureDebugReplayKind: CaseIterable, Sendable {
    case audio, video

    var filename: String { self == .audio ? "audio.wav" : "video.mp4" }

    var maximumBytes: Int {
        self == .audio
            ? ScanMediaPayloadPolicy.maxInferenceAudioBytes
            : ScanMediaPayloadPolicy.maxSavedVideoBytes
    }

    @MainActor var maximumDuration: TimeInterval {
        self == .audio ? AudioCaptureManager.maxDuration : CaptureWorkspaceViewModel.videoMaxDuration
    }
}

enum CaptureDebugReplayError: LocalizedError {
    case invalidSource, invalidDuration, incompleteVideo, comparisonMismatch

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            "Place a regular audio.wav or video.mp4 file within the media size limit in Documents/IdentificationReplay."
        case .invalidDuration:
            "Replay requires audio up to 15 seconds or video up to 5 seconds."
        case .incompleteVideo:
            "Replay couldn't prepare all five frames and the source audio."
        case .comparisonMismatch:
            "This audio sample doesn't match the selected comparison slot."
        }
    }
}

enum PreparedCaptureDebugReplay: Sendable {
    case audio(URL)
    case video(PreparedCaptureScanVideo)

    func ownedFileURLs(documentsDirectory: URL) -> [URL] {
        switch self {
        case .audio(let url):
            [url]
        case .video(let video):
            [video.playback.fileURL] + (video.audioFilePath.map {
                [documentsDirectory.appendingPathComponent($0)]
            } ?? [])
        }
    }

    func discard(documentsDirectory: URL = .documentsDirectory) async {
        await FileIOActor.shared.deleteFiles(
            at: ownedFileURLs(documentsDirectory: documentsDirectory).map(\.path)
        )
    }
}

enum CaptureDebugReplayPreparer {
    struct Metadata: Sendable {
        let duration: TimeInterval
        let hasAudio: Bool
        let hasVideo: Bool
    }

    struct Dependencies: Sendable {
        var metadata: @Sendable (URL) async throws -> Metadata
        var video: @Sendable (CaptureScanVideoPreparationRequest) async throws -> PreparedCaptureScanVideo

        static var live: Self {
            Self(
                metadata: { url in
                    let asset = AVURLAsset(url: url)
                    let duration = try await asset.load(.duration).seconds
                    let audio = try await asset.loadTracks(withMediaType: .audio)
                    let video = try await asset.loadTracks(withMediaType: .video)
                    return Metadata(duration: duration, hasAudio: !audio.isEmpty, hasVideo: !video.isEmpty)
                },
                video: { try await CaptureScanVideoMediaPreparer.prepare($0) }
            )
        }
    }

    static func prepare(
        _ kind: CaptureDebugReplayKind,
        composingCenter: CGFloat,
        isProActive: Bool,
        documentsDirectory: URL = .documentsDirectory,
        dependencies: Dependencies = .live
    ) async throws -> PreparedCaptureDebugReplay {
        let source = documentsDirectory.appendingPathComponent("IdentificationReplay")
            .appendingPathComponent(kind.filename)
        let copy = documentsDirectory
            .appendingPathComponent("identification-replay-\(UUID().uuidString)")
            .appendingPathExtension(source.pathExtension)
        var prepared: PreparedCaptureDebugReplay?
        do {
            try await DetachedWork.value(category: .imagePreparation) {
                try Task.checkCancellation()
                // Preserve the fixed inbox file; only owned copies can enter staging.
                let expected = documentsDirectory.resolvingSymlinksInPath()
                    .appendingPathComponent("IdentificationReplay")
                    .appendingPathComponent(kind.filename)
                guard source.resolvingSymlinksInPath().standardizedFileURL == expected.standardizedFileURL else {
                    throw CaptureDebugReplayError.invalidSource
                }
                try validateFile(source, maximumBytes: kind.maximumBytes)
                try FileManager.default.copyItem(at: source, to: copy)
                try validateFile(copy, maximumBytes: kind.maximumBytes)
            }
            let metadata = try await dependencies.metadata(copy)
            let maximumDuration = await kind.maximumDuration
            guard metadata.duration.isFinite, metadata.duration > 0,
                  metadata.duration <= maximumDuration else {
                throw CaptureDebugReplayError.invalidDuration
            }
            try Task.checkCancellation()
            switch kind {
            case .audio:
                guard metadata.hasAudio, !metadata.hasVideo else {
                    throw CaptureDebugReplayError.invalidSource
                }
                prepared = .audio(try await InferenceAudioPreparer.prepareLocalFile(
                    at: copy, outputDirectory: documentsDirectory
                ))
            case .video:
                guard metadata.hasVideo else { throw CaptureDebugReplayError.invalidSource }
                let video = try await dependencies.video(.init(
                    videoURL: copy, duration: metadata.duration,
                    composingCenter: composingCenter, isProActive: isProActive
                ))
                prepared = .video(video)
                guard video.sampledFrames.count == 5,
                      !metadata.hasAudio || video.audioFilePath != nil else {
                    throw CaptureDebugReplayError.incompleteVideo
                }
            }
            try Task.checkCancellation()
            guard let prepared else { throw CaptureDebugReplayError.invalidSource }
            if !prepared.ownedFileURLs(documentsDirectory: documentsDirectory).contains(copy) {
                await FileIOActor.shared.deleteFiles(at: [copy.path])
            }
            return prepared
        } catch {
            await prepared?.discard(documentsDirectory: documentsDirectory)
            await FileIOActor.shared.deleteFiles(at: [copy.path])
            throw error
        }
    }

    private static func validateFile(_ url: URL, maximumBytes: Int) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes > 0, bytes <= maximumBytes else {
            throw CaptureDebugReplayError.invalidSource
        }
    }
}
#endif
