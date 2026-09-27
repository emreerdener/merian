import Foundation

/// File-backed capture staging shared by visual and non-visual queue admission.
enum OfflineCaptureFileStore {
    /// Construct the live handoff from the same maps committed to the durable record.
    static func acceptedTimeline(
        _ timeline: [CaptureSubmissionMediaItem],
        audio: [String: String], video: [String: String],
        documentsDirectory: URL
    ) throws -> [CaptureSubmissionMediaItem] {
        func path(_ source: String, in map: [String: String]) throws -> String {
            guard let name = map[source] else { throw CocoaError(.fileNoSuchFile) }
            return documentsDirectory.appendingPathComponent(name).path
        }
        return try timeline.map { item in
            switch item {
            case .audio(let source): return .audio(try path(source, in: audio))
            case .video(let source, let poster, let companion):
                return .video(try path(source, in: video), posterImageIndex: poster,
                              audioFilePath: try companion.map { try path($0, in: audio) })
            case .image, .description: return item
            }
        }
    }

    static func persistFiles(
        _ filePaths: [String],
        documentsDirectory: URL
    ) throws -> [String: String] {
        guard !filePaths.isEmpty else { return [:] }

        var persistedNamesBySourcePath: [String: String] = [:]
        do {
            for filePath in Set(filePaths) {
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
        let destinationName = "queued-\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
        let destinationURL = documentsDirectory.appendingPathComponent(destinationName)

        let candidateURLs: [URL]
        if normalizedPath.hasPrefix("/") {
            candidateURLs = [sourceURL]
        } else {
            candidateURLs = [
                documentsDirectory.appendingPathComponent(normalizedPath),
                FileManager.default.temporaryDirectory.appendingPathComponent(normalizedPath)
            ]
        }

        for candidateURL in candidateURLs {
            guard FileManager.default.fileExists(atPath: candidateURL.path) else { continue }
            // The draft retains its source until durable acceptance. Failure cleanup
            // may delete only these unique queue-owned copies.
            try FileManager.default.copyItem(at: candidateURL, to: destinationURL)
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
