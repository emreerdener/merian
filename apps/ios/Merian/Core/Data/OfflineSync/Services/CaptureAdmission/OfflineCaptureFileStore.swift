import Foundation

/// File-backed capture staging shared by visual and non-visual queue admission.
enum OfflineCaptureFileStore {
    static func approximateBytes(for urls: [URL]) -> Int64 {
        urls.reduce(Int64(0)) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    static func estimatedBytes(_ paths: [String]) -> Int64 {
        paths.reduce(Int64(0)) { total, path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return total }
            let candidates: [URL]
            if trimmed.hasPrefix("/") {
                candidates = [URL(fileURLWithPath: trimmed)]
            } else {
                candidates = [
                    URL.documentsDirectory.appendingPathComponent(trimmed),
                    FileManager.default.temporaryDirectory.appendingPathComponent(trimmed)
                ]
            }
            let size = candidates.lazy.compactMap {
                (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? NSNumber)?.int64Value
            }.first ?? 0
            return total + size
        }
    }

    static func persistFiles(
        _ filePaths: [String],
        documentsDirectory: URL
    ) throws -> [String: String] {
        guard !filePaths.isEmpty else { return [:] }

        var persistedNamesBySourcePath: [String: String] = [:]
        do {
            for filePath in filePaths {
                persistedNamesBySourcePath[filePath] = try persistFile(
                    filePath,
                    documentsDirectory: documentsDirectory
                )
            }
        } catch {
            for persistedName in persistedNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(persistedName))
            }
            throw error
        }
        return persistedNamesBySourcePath
    }

    private static func persistFile(
        _ filePath: String,
        documentsDirectory: URL
    ) throws -> String {
        let normalizedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        let sourceURL = URL(fileURLWithPath: normalizedPath)
        let destinationName = sourceURL.lastPathComponent
        let destinationURL = documentsDirectory.appendingPathComponent(destinationName)

        let candidateURLs: [URL]
        if normalizedPath.hasPrefix("/") {
            candidateURLs = [sourceURL]
        } else {
            candidateURLs = [
                destinationURL,
                FileManager.default.temporaryDirectory.appendingPathComponent(normalizedPath)
            ]
        }

        for candidateURL in candidateURLs {
            guard FileManager.default.fileExists(atPath: candidateURL.path) else { continue }
            if candidateURL.path == destinationURL.path {
                return destinationName
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: candidateURL, to: destinationURL)
            return destinationName
        }

        throw CocoaError(.fileNoSuchFile)
    }

    static func makeCapturedMediaJSON(
        mediaTimeline: [CaptureSubmissionMediaItem],
        imageFileNames: [String],
        persistedAudioNamesBySourcePath: [String: String],
        persistedVideoNamesBySourcePath: [String: String] = [:]
    ) -> String? {
        var serializedItems: [SerializedMediaItem] = []
        var standaloneAudioSourceIndex = 0

        for item in mediaTimeline {
            switch item {
            case .image(let index):
                guard imageFileNames.indices.contains(index) else { continue }
                serializedItems.append(.image(.documents(imageFileNames[index])))
            case .audio(let sourcePath):
                defer { standaloneAudioSourceIndex += 1 }
                let persistedName = persistedAudioNamesBySourcePath[sourcePath]
                    ?? URL(fileURLWithPath: sourcePath).lastPathComponent
                guard !persistedName.isEmpty else { continue }
                serializedItems.append(.audio(.documents(
                    persistedName,
                    sourceIndex: standaloneAudioSourceIndex
                )))
            case .video(let sourcePath, let posterImageIndex, let audioFilePath):
                let persistedName = persistedVideoNamesBySourcePath[sourcePath]
                    ?? URL(fileURLWithPath: sourcePath).lastPathComponent
                guard !persistedName.isEmpty else { continue }
                let thumbnail = posterImageIndex.flatMap { index -> StoredMediaReference? in
                    guard imageFileNames.indices.contains(index) else { return nil }
                    return .documents(imageFileNames[index])
                }
                let audio = audioFilePath.flatMap { sourcePath -> StoredMediaReference? in
                    let persistedAudioName = persistedAudioNamesBySourcePath[sourcePath]
                        ?? URL(fileURLWithPath: sourcePath).lastPathComponent
                    guard !persistedAudioName.isEmpty else { return nil }
                    return .documents(persistedAudioName)
                }
                serializedItems.append(.video(StoredVideoMediaReference(
                    video: .documents(persistedName),
                    thumbnail: thumbnail,
                    audio: audio
                )))
            case .description(let context):
                guard !context.isEmpty else { continue }
                serializedItems.append(.description(context))
            }
        }

        guard !serializedItems.isEmpty else { return nil }
        return try? String(data: JSONEncoder().encode(serializedItems), encoding: .utf8)
    }
}
