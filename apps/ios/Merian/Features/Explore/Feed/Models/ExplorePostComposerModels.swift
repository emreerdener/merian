import Foundation

enum ExplorePostComposerMode {
    case create
    case edit

    var title: String {
        switch self {
        case .create:
            return "Share with community"
        case .edit:
            return "Edit post"
        }
    }

    var actionTitle: String {
        switch self {
        case .create:
            return "Share discovery"
        case .edit:
            return "Save"
        }
    }

    var savingTitle: String {
        switch self {
        case .create:
            return "Checking and sharing…"
        case .edit:
            return "Saving…"
        }
    }
}

enum ExplorePostLocationSharing: String, CaseIterable, Identifiable, Decodable, Equatable {
    case open
    case obscured
    case privateLocation = "private"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        switch rawValue {
        case "open":
            self = .open
        case "obscured":
            self = .obscured
        case "private", "hidden":
            self = .privateLocation
        default:
            self = .obscured
        }
    }

    var title: String {
        switch self {
        case .open:
            return "Open"
        case .obscured:
            return "Obscured"
        case .privateLocation:
            return "Private"
        }
    }

    var systemImage: String {
        switch self {
        case .open:
            return "mappin.and.ellipse"
        case .obscured:
            return "location.viewfinder"
        case .privateLocation:
            return "location.slash"
        }
    }

    var detail: String {
        switch self {
        case .open:
            return "Show broad label and add to Explore Map."
        case .obscured:
            return "Show broad label and keep off Explore Map."
        case .privateLocation:
            return "Share this post without public location."
        }
    }
}

enum ExplorePostComposerMediaKind: String, Equatable {
    case image
    case video
    case audio
}

struct ExplorePostMediaSelection: Equatable {
    let kind: ExplorePostComposerMediaKind
    let sourceMediaId: String?
    let sourceIndex: Int?
    let thumbnailSourceIndex: Int?
    let url: String?
    let thumbnailUrl: String?
    let orderIndex: Int

    var jsonObject: [String: Any] {
        var payload: [String: Any] = [
            "kind": kind.rawValue,
            "order_index": orderIndex
        ]

        if let sourceMediaId {
            payload["source_media_id"] = sourceMediaId
        }
        if let sourceIndex {
            payload["source_index"] = sourceIndex
        }
        if let thumbnailSourceIndex {
            payload["thumbnail_source_index"] = thumbnailSourceIndex
        }
        if let url {
            payload["url"] = url
        }
        if let thumbnailUrl {
            payload["thumbnail_url"] = thumbnailUrl
        }

        return payload
    }
}

struct ExplorePostComposerMediaDraft: Identifiable, Equatable {
    let id: String
    let kind: ExplorePostComposerMediaKind
    let previewPath: String
    let sourceMediaId: String?
    let sourceIndex: Int?
    let thumbnailSourceIndex: Int?
    let url: String?
    let thumbnailUrl: String?
    var isIncluded: Bool

    var isVideo: Bool {
        kind == .video
    }

    var isAudio: Bool {
        kind == .audio
    }

    func selection(orderIndex: Int) -> ExplorePostMediaSelection {
        ExplorePostMediaSelection(
            kind: kind,
            sourceMediaId: sourceMediaId,
            sourceIndex: sourceIndex,
            thumbnailSourceIndex: thumbnailSourceIndex,
            url: url,
            thumbnailUrl: thumbnailUrl,
            orderIndex: orderIndex
        )
    }

    static func eligibleItems(from snapshot: CapturedMediaSnapshot, scanId: String? = nil) -> [ExplorePostComposerMediaDraft] {
        var drafts: [ExplorePostComposerMediaDraft] = []
        var imageIndex = 0
        var videoIndex = 0
        var audioIndex = 0
        let items = snapshot.items

        for index in items.indices {
            switch items[index] {
            case .image(let reference):
                let isVideoPoster: Bool
                if items.indices.contains(index + 1),
                   case .video = items[index + 1] {
                    isVideoPoster = true
                } else {
                    isVideoPoster = false
                }

                if !isVideoPoster {
                    drafts.append(
                        ExplorePostComposerMediaDraft(
                            id: "image-\(imageIndex)-\(reference.serializedPath)",
                            kind: .image,
                            previewPath: reference.serializedPath,
                            sourceMediaId: scanId.map { "scan:\($0):image:\(imageIndex)" },
                            sourceIndex: imageIndex,
                            thumbnailSourceIndex: nil,
                            url: nil,
                            thumbnailUrl: nil,
                            isIncluded: true
                        )
                    )
                }

                imageIndex += 1

            case .video(let reference):
                let thumbnailPaths = snapshot.thumbnailImagePaths
                let legacyThumbnailIndex = previousImageIndex(before: index, in: items)
                let previewPath = reference.thumbnailPath
                    ?? legacyThumbnailIndex.flatMap { imagePath(at: $0, in: items) }
                    ?? ""
                let thumbnailSourceIndex = thumbnailPaths.firstIndex(of: previewPath) ?? legacyThumbnailIndex
                guard let thumbnailSourceIndex, !previewPath.isEmpty else {
                    videoIndex += 1
                    continue
                }

                drafts.append(
                    ExplorePostComposerMediaDraft(
                        id: "video-\(videoIndex)-\(reference.serializedPath)",
                        kind: .video,
                        previewPath: previewPath,
                        sourceMediaId: scanId.map { "scan:\($0):video:\(videoIndex)" },
                        sourceIndex: videoIndex,
                        thumbnailSourceIndex: thumbnailSourceIndex,
                        url: nil,
                        thumbnailUrl: nil,
                        isIncluded: true
                    )
                )
                videoIndex += 1

            case .audio(let reference):
                drafts.append(
                    ExplorePostComposerMediaDraft(
                        id: "audio-\(audioIndex)-\(reference.serializedPath)",
                        kind: .audio,
                        previewPath: reference.serializedPath,
                        sourceMediaId: scanId.map { "scan:\($0):audio:\(audioIndex)" },
                        sourceIndex: audioIndex,
                        thumbnailSourceIndex: nil,
                        url: nil,
                        thumbnailUrl: nil,
                        isIncluded: true
                    )
                )
                audioIndex += 1

            case .description:
                continue
            }
        }

        return drafts
    }

    static func existingPostItems(from mediaItems: [ExploreMediaItem]) -> [ExplorePostComposerMediaDraft] {
        mediaItems
            .sorted { $0.orderIndex < $1.orderIndex }
            .enumerated()
            .compactMap { offset, item in
                let previewPath = (item.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? item.thumbnailUrl!
                    : item.url
                let kind: ExplorePostComposerMediaKind
                switch item.kind {
                case .image:
                    kind = .image
                case .video:
                    kind = .video
                case .audio:
                    kind = .audio
                }

                let trimmedUrl = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedUrl.isEmpty else { return nil }

                return ExplorePostComposerMediaDraft(
                    id: "existing-\(offset)-\(trimmedUrl)",
                    kind: kind,
                    previewPath: previewPath,
                    sourceMediaId: nil,
                    sourceIndex: nil,
                    thumbnailSourceIndex: nil,
                    url: trimmedUrl,
                    thumbnailUrl: item.thumbnailUrl,
                    isIncluded: true
                )
            }
    }

    static func sourceItems(from mediaItems: [ExploreComposerMediaItem]) -> [ExplorePostComposerMediaDraft] {
        mediaItems
            .sorted { lhs, rhs in
                switch (lhs.selectionOrderIndex, rhs.selectionOrderIndex) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.orderIndex < rhs.orderIndex
                }
            }
            .map { item in
                let kind: ExplorePostComposerMediaKind
                switch item.kind {
                case .image: kind = .image
                case .video: kind = .video
                case .audio: kind = .audio
                }
                let previewPath = item.thumbnailUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? item.url
                    : item.thumbnailUrl

                return ExplorePostComposerMediaDraft(
                    id: item.sourceMediaId,
                    kind: kind,
                    previewPath: previewPath,
                    sourceMediaId: item.sourceMediaId,
                    sourceIndex: nil,
                    thumbnailSourceIndex: nil,
                    url: nil,
                    thumbnailUrl: item.thumbnailUrl,
                    isIncluded: item.isSelected ?? true
                )
            }
    }

    private static func previousImageIndex(before itemIndex: Int, in items: [SerializedMediaItem]) -> Int? {
        guard itemIndex > 0 else { return nil }
        var imageIndex = 0
        var mostRecentImageIndex: Int?

        for index in 0..<itemIndex {
            if case .image = items[index] {
                mostRecentImageIndex = imageIndex
                imageIndex += 1
            }
        }

        return mostRecentImageIndex
    }

    private static func imagePath(at targetImageIndex: Int, in items: [SerializedMediaItem]) -> String? {
        var imageIndex = 0
        for item in items {
            guard case .image(let reference) = item else { continue }
            if imageIndex == targetImageIndex {
                return reference.serializedPath
            }
            imageIndex += 1
        }
        return nil
    }
}

struct ExplorePostComposerDraft {
    let selectedCommonName: String
    let fieldNotes: String?
    let fieldNotesArePublic: Bool
    let hashtags: [String]
    let locationSharing: ExplorePostLocationSharing
    let mediaItems: [ExplorePostMediaSelection]?

    var publicFieldNotes: String? {
        fieldNotesArePublic ? fieldNotes : nil
    }
}
