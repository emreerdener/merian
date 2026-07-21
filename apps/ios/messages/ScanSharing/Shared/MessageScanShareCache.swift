import Foundation

enum MessageScanShareCacheConstants {
    static let appGroupIdentifier = "group.app.merian.shared"
    static let maxRecordCount = 100
    static let thumbnailMaxDimension = 512
    static let attachmentMaxDimension = 1600
    static let imageCompressionQuality = 0.84

    static let snapshotFilename = "message-scan-share-cache.json"
    static let thumbnailDirectoryName = "MessageScanThumbnails"
    static let attachmentDirectoryName = "MessageScanAttachments"
}

struct MessageScanShareCacheSnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    let records: [MessageScanShareCacheRecord]

    static let empty = MessageScanShareCacheSnapshot(generatedAt: .distantPast, records: [])
}

struct MessageScanShareCacheRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let commonName: String
    let scientificName: String
    let timestamp: Date
    let locationName: String?
    let confidenceScore: Double?
    let thumbnailFilename: String?
    let attachmentFilename: String?
    let publicExplorePostId: String?
    let fieldNotes: String?

    var hasImageAttachment: Bool {
        attachmentFilename?.isEmpty == false
    }

    var publicExploreURL: URL? {
        guard let publicExplorePostId,
              !publicExplorePostId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return PublicBrand.websiteURL(path: "explore/post/\(publicExplorePostId)")
    }

    var cardURL: URL {
        publicExploreURL ?? PublicBrand.websiteURL
    }

    var scanDeepLinkURL: URL? {
        MerianDeepLinkRoute.scan(id).url
    }
}

enum MessageScanShareCacheStore {
    static func appGroupRootURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: MessageScanShareCacheConstants.appGroupIdentifier
        )
    }

    static func snapshotURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(MessageScanShareCacheConstants.snapshotFilename)
    }

    static func thumbnailDirectoryURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(MessageScanShareCacheConstants.thumbnailDirectoryName, isDirectory: true)
    }

    static func attachmentDirectoryURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(MessageScanShareCacheConstants.attachmentDirectoryName, isDirectory: true)
    }

    static func thumbnailURL(for record: MessageScanShareCacheRecord, rootURL: URL) -> URL? {
        guard let filename = record.thumbnailFilename, !filename.isEmpty else { return nil }
        return thumbnailDirectoryURL(rootURL: rootURL).appendingPathComponent(filename)
    }

    static func attachmentURL(for record: MessageScanShareCacheRecord, rootURL: URL) -> URL? {
        guard let filename = record.attachmentFilename, !filename.isEmpty else { return nil }
        return attachmentDirectoryURL(rootURL: rootURL).appendingPathComponent(filename)
    }

    static func loadSnapshot(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) -> MessageScanShareCacheSnapshot? {
        guard let rootURL = rootURL ?? appGroupRootURL(fileManager: fileManager) else {
            return nil
        }

        let url = snapshotURL(rootURL: rootURL)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(MessageScanShareCacheSnapshot.self, from: data)
    }

    static func writeSnapshot(
        _ snapshot: MessageScanShareCacheSnapshot,
        fileManager: FileManager = .default,
        rootURL: URL
    ) throws {
        try fileManager.createDirectory(
            at: thumbnailDirectoryURL(rootURL: rootURL),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: attachmentDirectoryURL(rootURL: rootURL),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotURL(rootURL: rootURL), options: [.atomic])
    }

    static func removeImagesNotReferenced(
        by snapshot: MessageScanShareCacheSnapshot,
        fileManager: FileManager = .default,
        rootURL: URL
    ) {
        let retainedThumbnails = Set(snapshot.records.compactMap(\.thumbnailFilename))
        let retainedAttachments = Set(snapshot.records.compactMap(\.attachmentFilename))

        removeUnreferencedFiles(
            in: thumbnailDirectoryURL(rootURL: rootURL),
            retaining: retainedThumbnails,
            fileManager: fileManager
        )
        removeUnreferencedFiles(
            in: attachmentDirectoryURL(rootURL: rootURL),
            retaining: retainedAttachments,
            fileManager: fileManager
        )
    }

    private static func removeUnreferencedFiles(
        in directoryURL: URL,
        retaining retainedFilenames: Set<String>,
        fileManager: FileManager
    ) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for fileURL in contents where !retainedFilenames.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}

enum MessageScanShareTextBuilder {
    static func descriptionText(
        for record: MessageScanShareCacheRecord,
        includeFieldNotes: Bool = false
    ) -> String {
        let commonName = normalizedName(record.commonName, fallback: "a nature find")
        let scientificName = normalizedName(record.scientificName, fallback: "unknown species")

        return "Check out this \(commonName) (\(scientificName)) I discovered!"
    }

    static func cardCaption(for record: MessageScanShareCacheRecord) -> String {
        contextPieces(for: record).joined(separator: " ")
    }

    private static func contextPieces(for record: MessageScanShareCacheRecord) -> [String] {
        var pieces: [String] = []

        let dateLabel = dateFormatter.string(from: record.timestamp)
        if !dateLabel.isEmpty {
            pieces.append("Discovered \(dateLabel).")
        }

        if let location = trimmedNonEmpty(record.locationName) {
            pieces.append("Near \(location).")
        }

        return pieces
    }

    private static func normalizedName(_ value: String, fallback: String) -> String {
        trimmedNonEmpty(value) ?? fallback
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

enum MerianDeepLinkRoute: Equatable {
    case explorePost(String)
    case speciesDictionary(String)
    case scan(String)
    case scansLibrary

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if scheme == "https", PublicBrand.acceptedWebHosts.contains(host) {
            if pathComponents.count == 3,
               pathComponents[0] == "explore",
               pathComponents[1] == "post",
               !pathComponents[2].isEmpty {
                self = .explorePost(pathComponents[2])
                return
            }

            if (pathComponents.count == 2 || pathComponents.count == 3),
               pathComponents[0] == "species",
               let speciesId = Self.normalizedSpeciesDictionaryID(pathComponents[1]),
               pathComponents.count == 2 || !pathComponents[2].isEmpty {
                self = .speciesDictionary(speciesId)
                return
            }

            return nil
        }

        guard PublicBrand.acceptedSchemes.contains(scheme) else {
            return nil
        }

        switch host {
        case "explore":
            guard pathComponents.count == 2,
                  pathComponents[0] == "post",
                  !pathComponents[1].isEmpty else {
                return nil
            }
            self = .explorePost(pathComponents[1])
        case "scan":
            guard pathComponents.count == 1,
                  !pathComponents[0].isEmpty else {
                return nil
            }
            self = .scan(pathComponents[0])
        case "species":
            guard pathComponents.count == 1,
                  let speciesId = Self.normalizedSpeciesDictionaryID(pathComponents[0]) else {
                return nil
            }
            self = .speciesDictionary(speciesId)
        case "scans":
            guard pathComponents.isEmpty else {
                return nil
            }
            self = .scansLibrary
        default:
            return nil
        }
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = PublicBrand.canonicalScheme

        switch self {
        case .explorePost(let postId):
            components.host = "explore"
            components.path = "/post/\(postId)"
        case .speciesDictionary(let speciesId):
            components.host = "species"
            components.path = "/\(speciesId)"
        case .scan(let scanId):
            components.host = "scan"
            components.path = "/\(scanId)"
        case .scansLibrary:
            components.host = "scans"
        }

        return components.url
    }

    private static func normalizedSpeciesDictionaryID(_ value: String) -> String? {
        guard let uuid = UUID(uuidString: value) else { return nil }
        return uuid.uuidString.lowercased()
    }
}
