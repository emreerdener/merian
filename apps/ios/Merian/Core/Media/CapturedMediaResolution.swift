import Foundation

extension StoredMediaReference {
    var resolvedURL: URL? {
        switch storage {
        case .documents:
            return URL.documentsDirectory.appendingPathComponent(path)
        case .remoteURL:
            return SecureTransportPolicy.httpsURL(from: path)
        case .absolutePath:
            if path.starts(with: "file://") {
                return URL(string: path)
            }
            return URL(fileURLWithPath: path)
        }
    }

    var resolvedLocalPath: String? {
        switch storage {
        case .documents:
            let documentsPath = URL.documentsDirectory.appendingPathComponent(path).path
            if FileManager.default.fileExists(atPath: documentsPath) {
                return documentsPath
            }
            return FileManager.default.temporaryDirectory.appendingPathComponent(path).path
        case .absolutePath:
            return resolvedURL?.path
        case .remoteURL:
            return nil
        }
    }
}

extension StoredVideoMediaReference {
    var resolvedLocalPath: String? {
        video.resolvedLocalPath
    }

    var thumbnailPath: String? {
        thumbnail?.serializedPath
    }

    var resolvedThumbnailPath: String? {
        thumbnail?.resolvedLocalPath ?? thumbnail?.serializedPath
    }

    var audioPath: String? {
        audio?.serializedPath
    }

    var resolvedAudioPath: String? {
        audio?.resolvedLocalPath ?? audio?.serializedPath
    }
}

extension CapturedMediaSnapshot {
    var activeScanMedia: ActiveScanMedia {
        let resolvedItems: [MediaItem] = items.compactMap { serialized in
            switch serialized {
            case .image(let reference):
                return .image(reference.serializedPath)
            case .audio(let reference):
                return .audio(reference.resolvedLocalPath ?? reference.serializedPath)
            case .video(let reference):
                let fallbackImage = reference.resolvedThumbnailPath.map {
                    VideoFallbackImageSource.imagePath($0)
                }
                return .video(
                    reference.resolvedLocalPath ?? reference.serializedPath,
                    fallbackImage: fallbackImage
                )
            case .description(let context):
                return .description(context)
            }
        }

        return ActiveScanMedia(items: resolvedItems)
    }
}

extension MediaJSONParser {
    static func parse(jsonString: String) -> ActiveScanMedia? {
        let snapshot = CapturedMediaSnapshot(jsonString: jsonString)
        guard !snapshot.items.isEmpty else {
            return nil
        }
        return snapshot.activeScanMedia
    }
}
