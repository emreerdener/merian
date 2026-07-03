import Foundation

enum ExploreWidgetConstants {
    static let appGroupIdentifier = "group.app.merian.shared"
    static let kind = "ExploreCarouselWidget"
    static let maxItemCount = 12
    static let imageMaxDimension = 512
    static let imageCompressionQuality = 0.84
    static let rotationInterval: TimeInterval = 30 * 60
    static let emptyStateRefreshInterval: TimeInterval = 60 * 60

    private static let snapshotFilename = "explore-widget-snapshot.json"
    private static let imageDirectoryName = "ExploreWidgetImages"

    static func snapshotURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?.appendingPathComponent(snapshotFilename)
    }

    static func imageDirectoryURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?.appendingPathComponent(imageDirectoryName, isDirectory: true)
    }

    static func imageURL(for filename: String, fileManager: FileManager = .default) -> URL? {
        imageDirectoryURL(fileManager: fileManager)?.appendingPathComponent(filename)
    }

    static func imageFilename(postId: String, index: Int) -> String {
        let safePostId = postId
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return "\(index)-\(safePostId).jpg"
    }

    static func deepLinkURL(postId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "merian"
        components.host = "explore"
        components.path = "/post/\(postId)"
        return components.url
    }

    private static func containerURL(fileManager: FileManager) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
}

struct ExploreWidgetItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    let postId: String
    let imageFilename: String
    let sharedAt: String
    let speciesCommonName: String?
    let speciesScientificName: String?
    let hasVideo: Bool?

    var id: String { postId }
}

struct ExploreWidgetSnapshot: Codable, Equatable, Sendable {
    let updatedAt: Date
    let items: [ExploreWidgetItem]
}

enum ExploreWidgetCache {
    static func loadSnapshot(fileManager: FileManager = .default) -> ExploreWidgetSnapshot? {
        guard let url = ExploreWidgetConstants.snapshotURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(ExploreWidgetSnapshot.self, from: data)
    }

    static func writeSnapshot(
        _ snapshot: ExploreWidgetSnapshot,
        fileManager: FileManager = .default
    ) throws {
        guard let snapshotURL = ExploreWidgetConstants.snapshotURL(fileManager: fileManager),
              let imageDirectoryURL = ExploreWidgetConstants.imageDirectoryURL(fileManager: fileManager) else {
            throw CocoaError(.fileNoSuchFile)
        }

        try fileManager.createDirectory(
            at: imageDirectoryURL,
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotURL, options: [.atomic])
    }

    static func removeImagesNotInSnapshot(
        _ snapshot: ExploreWidgetSnapshot,
        fileManager: FileManager = .default
    ) {
        guard let imageDirectoryURL = ExploreWidgetConstants.imageDirectoryURL(fileManager: fileManager),
              let contents = try? fileManager.contentsOfDirectory(
                at: imageDirectoryURL,
                includingPropertiesForKeys: nil
              ) else {
            return
        }

        let retainedFilenames = Set(snapshot.items.map(\.imageFilename))
        for fileURL in contents where !retainedFilenames.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
