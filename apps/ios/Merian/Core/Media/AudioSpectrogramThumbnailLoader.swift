import Foundation
import UIKit

actor AudioSpectrogramThumbnailLoader {
    static let shared = AudioSpectrogramThumbnailLoader()

    private var activeTasks: [String: Task<UIImage?, Never>] = [:]

    func loadImage(fromPath audioPath: String, maxDimension: Int = 1024) async -> UIImage? {
        let cacheKey = "audio_spectrogram_\(audioPath)_\(maxDimension)"

        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            return cached
        }

        if let existingTask = activeTasks[cacheKey] {
            return await existingTask.value
        }

        let fetchTask = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let resolvedAudio = await Self.resolveAudioURL(from: audioPath) else {
                return nil
            }
            defer {
                if resolvedAudio.shouldDeleteAfterRendering {
                    try? FileManager.default.removeItem(at: resolvedAudio.url)
                }
            }

            let columns = await AudioSpectrogramDecoder.decodeColumns(fromFilePath: resolvedAudio.url.path)
            guard !columns.isEmpty,
                  let image = Self.renderThumbnail(columns: columns, maxDimension: maxDimension) else {
                return nil
            }

            ImageCache.shared.set(image, forKey: cacheKey)
            return image
        }

        activeTasks[cacheKey] = fetchTask

        defer {
            if activeTasks[cacheKey] == fetchTask {
                activeTasks.removeValue(forKey: cacheKey)
            }
        }

        return await fetchTask.value
    }

    nonisolated func prefetch(audioPaths: [String], maxDimension: Int) {
        guard !audioPaths.isEmpty else { return }

        Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for audioPath in audioPaths {
                    if inFlight >= 2 {
                        await group.next()
                        inFlight -= 1
                    }

                    group.addTask(priority: .utility) {
                        _ = await self.loadImage(fromPath: audioPath, maxDimension: maxDimension)
                    }
                    inFlight += 1
                }
            }
        }
    }

    private struct ResolvedAudioURL: Sendable {
        let url: URL
        let shouldDeleteAfterRendering: Bool
    }

    private static nonisolated func resolveAudioURL(from audioPath: String) async -> ResolvedAudioURL? {
        if let remoteURL = SecureTransportPolicy.httpsURL(from: audioPath) {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 30

            do {
                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      response.expectedContentLength <= Int64(MerianConfig.audioPayloadMaxBytes) else {
                    return nil
                }

                let byteSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard byteSize <= MerianConfig.audioPayloadMaxBytes else { return nil }

                let renderURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("explore-spectrogram-\(UUID().uuidString).wav")
                try FileManager.default.moveItem(at: temporaryURL, to: renderURL)
                return ResolvedAudioURL(url: renderURL, shouldDeleteAfterRendering: true)
            } catch {
                return nil
            }
        }

        if audioPath.starts(with: "file://"), let url = URL(string: audioPath) {
            return ResolvedAudioURL(url: url, shouldDeleteAfterRendering: false)
        }

        if audioPath.starts(with: "/") {
            return ResolvedAudioURL(
                url: URL(fileURLWithPath: audioPath),
                shouldDeleteAfterRendering: false
            )
        }

        let documentsURL = URL.documentsDirectory.appendingPathComponent(audioPath)
        if FileManager.default.fileExists(atPath: documentsURL.path) {
            return ResolvedAudioURL(url: documentsURL, shouldDeleteAfterRendering: false)
        }

        return ResolvedAudioURL(
            url: FileManager.default.temporaryDirectory.appendingPathComponent(audioPath),
            shouldDeleteAfterRendering: false
        )
    }

    private static nonisolated func renderThumbnail(
        columns: [SpectrogramColumn],
        maxDimension: Int
    ) -> UIImage? {
        guard !columns.isEmpty else { return nil }

        let dimension = max(64, maxDimension)
        let size = CGSize(width: dimension, height: dimension)
        return SpectrogramRenderer.image(
            columns: columns,
            layout: .fitToData,
            targetSize: size,
            scale: 1
        )
    }
}
