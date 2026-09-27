import Foundation
import UIKit

struct MediaShareFileRequest: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case audio, video }
    let source: MediaExportSource?
    let kind: Kind

    static func make(audioPaths: [String], videoPaths: [String]) -> [Self] {
        requests(paths: audioPaths, kind: .audio) + requests(paths: videoPaths, kind: .video)
    }

    private static func requests(paths: [String], kind: Kind) -> [Self] {
        paths.flatMap { path in
            let sources = MediaExportSourceResolver.sources(from: path)
            // Preserve invalid inputs so preparation reports an unavailable item.
            return sources.isEmpty
                ? [Self(source: nil, kind: kind)]
                : sources.map { Self(source: $0, kind: kind) }
        }
    }
}

/// Owns only an export copy. Activity item sources retain it until sharing ends;
/// discarded or cancelled preparation releases it without deleting scan media.
final class MediaShareFile: Sendable {
    let url: URL
    private let directory: URL

    init(copying source: URL, kind: MediaShareFileRequest.Kind, index: Int, discoveryIndex: Int = 1) throws {
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        let size = values.fileSize ?? 0
        let maximum = kind == .audio
            ? ScanMediaPayloadPolicy.maxInferenceAudioBytes
            : ScanMediaPayloadPolicy.maxSavedVideoBytes
        guard values.isRegularFile == true, size > 0, size <= maximum else { throw CocoaError(.fileReadTooLarge) }
        let allowedExtensions = kind == .audio
            ? ["m4a", "wav", "mp3", "aac", "caf", "aif", "aiff"]
            : ["mp4", "mov", "m4v"]
        let fileExtension = source.pathExtension.lowercased()
        guard allowedExtensions.contains(fileExtension) else { throw CocoaError(.fileReadCorruptFile) }
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Naturebook-share-\(UUID().uuidString)", isDirectory: true)
        let label = kind == .audio ? "Recording" : "Video"
        url = directory.appendingPathComponent("Naturebook-Discovery-\(discoveryIndex)-\(label)-\(index).\(fileExtension)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: source, to: url)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

// UIActivityItemSource has nonisolated requirements; this provider only reads
// its immutable, Sendable file owner and never accesses controller state.
final class MediaShareFileItemSource: NSObject, UIActivityItemSource {
    private let file: MediaShareFile

    init(file: MediaShareFile) { self.file = file }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        file.url
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        file.url
    }
}
