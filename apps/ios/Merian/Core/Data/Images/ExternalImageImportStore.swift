import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PendingExternalImageImport: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let storedFilename: String
    let receivedAt: Date
}

enum ExternalImageImportError: LocalizedError, Equatable {
    case unsupportedURL
    case unavailableApplicationSupportDirectory
    case inboxFull

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "Naturebook can only import image files."
        case .unavailableApplicationSupportDirectory:
            return "Naturebook could not prepare its image import inbox."
        case .inboxFull:
            return "Naturebook's image import inbox is full."
        }
    }
}

enum ExternalImageImportURLClassifier {
    nonisolated static func isSupportedImageFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           contentType.conforms(to: .image) {
            return true
        }

        guard !url.pathExtension.isEmpty,
              let inferredType = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return inferredType.conforms(to: .image)
    }
}

struct ExternalImageImportSecurityScope: Sendable {
    let startAccessing: @Sendable (URL) -> Bool
    let stopAccessing: @Sendable (URL) -> Void

    static let live = ExternalImageImportSecurityScope(
        startAccessing: { $0.startAccessingSecurityScopedResource() },
        stopAccessing: { $0.stopAccessingSecurityScopedResource() }
    )
}

actor ExternalImageImportStore {
    static let shared = ExternalImageImportStore()

    private struct Snapshot: Codable {
        var imports: [PendingExternalImageImport]
        var discardedFilenames: [String]?
        var terminalFailureCount: Int?

        static let empty = Snapshot(
            imports: [],
            discardedFilenames: [],
            terminalFailureCount: 0
        )
    }

    private let fileManager: FileManager
    private let rootURL: URL?
    private let snapshotFilename = "pending-image-imports.json"
    private let securityScope: ExternalImageImportSecurityScope
    private let fileTypeValidator: @Sendable (URL) -> Bool
    private let maxPendingImports: Int

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        securityScope: ExternalImageImportSecurityScope = .live,
        maxPendingImports: Int = 8,
        fileTypeValidator: @escaping @Sendable (URL) -> Bool = {
            ExternalImageImportURLClassifier.isSupportedImageFileURL($0)
        }
    ) {
        self.fileManager = fileManager
        self.securityScope = securityScope
        self.maxPendingImports = maxPendingImports
        self.fileTypeValidator = fileTypeValidator
        if let rootURL {
            self.rootURL = rootURL
        } else {
            self.rootURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("ExternalImageImports", isDirectory: true)
        }
    }

    func stageIncomingImage(at sourceURL: URL) throws -> PendingExternalImageImport {
        guard let rootURL else {
            throw ExternalImageImportError.unavailableApplicationSupportDirectory
        }

        try prepareRootDirectory(rootURL)

        let didAccessSecurityScopedResource = securityScope.startAccessing(sourceURL)
        defer {
            if didAccessSecurityScopedResource {
                securityScope.stopAccessing(sourceURL)
            }
        }

        guard fileTypeValidator(sourceURL) else {
            throw ExternalImageImportError.unsupportedURL
        }

        var snapshot = try reconcileInbox(rootURL: rootURL)
        guard snapshot.imports.count < maxPendingImports else {
            throw ExternalImageImportError.inboxFull
        }

        let id = UUID()
        let pathExtension = sourceURL.pathExtension.isEmpty ? "image" : sourceURL.pathExtension.lowercased()
        let storedFilename = id.uuidString.appending(".").appending(pathExtension)
        let destinationURL = rootURL.appendingPathComponent(storedFilename, isDirectory: false)
        let temporaryURL = rootURL.appendingPathComponent(".incoming-\(id.uuidString)", isDirectory: false)

        do {
            try coordinatedCopy(from: sourceURL, to: temporaryURL)
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            excludeFromBackup(destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }

        let pendingImport = PendingExternalImageImport(
            id: id,
            storedFilename: storedFilename,
            receivedAt: Date()
        )

        do {
            snapshot.imports.append(pendingImport)
            try writeSnapshot(snapshot, rootURL: rootURL)
            return pendingImport
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    func pendingImports() -> [PendingExternalImageImport] {
        guard let rootURL else { return [] }
        let snapshot = (try? reconcileInbox(rootURL: rootURL)) ?? loadSnapshot(rootURL: rootURL)
        return snapshot.imports.sorted { $0.receivedAt < $1.receivedAt }
    }

    func fileURL(for pendingImport: PendingExternalImageImport) -> URL? {
        guard let rootURL else { return nil }
        let url = fileURL(for: pendingImport, rootURL: rootURL)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func remove(_ pendingImport: PendingExternalImageImport) {
        guard let rootURL else { return }

        var snapshot = (try? reconcileInbox(rootURL: rootURL)) ?? loadSnapshot(rootURL: rootURL)
        snapshot.imports.removeAll { $0.id == pendingImport.id }
        var discardedFilenames = Set(snapshot.discardedFilenames ?? [])
        discardedFilenames.insert(pendingImport.storedFilename)
        snapshot.discardedFilenames = discardedFilenames.sorted()

        do {
            try writeSnapshot(snapshot, rootURL: rootURL)
        } catch {
            // If the tombstone cannot be committed, deleting the file still prevents a
            // duplicate import; the stale manifest entry is pruned during reconciliation.
            try? fileManager.removeItem(at: fileURL(for: pendingImport, rootURL: rootURL))
            return
        }

        discardTombstonedFiles(in: &snapshot, rootURL: rootURL)
        try? writeSnapshot(snapshot, rootURL: rootURL)
    }

    func recordTerminalFailure() {
        guard let rootURL else { return }
        var snapshot = (try? reconcileInbox(rootURL: rootURL)) ?? loadSnapshot(rootURL: rootURL)
        snapshot.terminalFailureCount = min((snapshot.terminalFailureCount ?? 0) + 1, 8)
        try? writeSnapshot(snapshot, rootURL: rootURL)
    }

    func consumeTerminalFailure() -> Bool {
        guard let rootURL else { return false }
        var snapshot = (try? reconcileInbox(rootURL: rootURL)) ?? loadSnapshot(rootURL: rootURL)
        let count = snapshot.terminalFailureCount ?? 0
        guard count > 0 else { return false }
        snapshot.terminalFailureCount = count - 1
        try? writeSnapshot(snapshot, rootURL: rootURL)
        return true
    }

    private func snapshotURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    private func fileURL(for pendingImport: PendingExternalImageImport, rootURL: URL) -> URL {
        rootURL.appendingPathComponent(pendingImport.storedFilename, isDirectory: false)
    }

    private func prepareRootDirectory(_ rootURL: URL) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        excludeFromBackup(rootURL)
    }

    private func coordinatedCopy(from sourceURL: URL, to destinationURL: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try fileManager.copyItem(at: coordinatedURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }
    }

    private func reconcileInbox(rootURL: URL) throws -> Snapshot {
        try prepareRootDirectory(rootURL)
        var snapshot = loadSnapshot(rootURL: rootURL)
        discardTombstonedFiles(in: &snapshot, rootURL: rootURL)

        let existingImports = snapshot.imports.filter {
            fileManager.fileExists(atPath: fileURL(for: $0, rootURL: rootURL).path)
        }
        var importsByFilename: [String: PendingExternalImageImport] = [:]
        for pendingImport in existingImports {
            if let existing = importsByFilename[pendingImport.storedFilename],
               existing.receivedAt <= pendingImport.receivedAt {
                continue
            }
            importsByFilename[pendingImport.storedFilename] = pendingImport
        }
        let discardedFilenames = Set(snapshot.discardedFilenames ?? [])
        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]
        )

        for url in urls {
            let filename = url.lastPathComponent
            if filename == snapshotFilename || discardedFilenames.contains(filename) {
                continue
            }
            if filename.hasPrefix(".incoming-") {
                try? fileManager.removeItem(at: url)
                continue
            }
            if importsByFilename[filename] != nil {
                continue
            }

            let identifierText = url.deletingPathExtension().lastPathComponent
            guard let identifier = UUID(uuidString: identifierText) else {
                try? fileManager.removeItem(at: url)
                continue
            }
            let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let receivedAt = resourceValues?.creationDate ?? resourceValues?.contentModificationDate ?? Date()
            importsByFilename[filename] = PendingExternalImageImport(
                id: identifier,
                storedFilename: filename,
                receivedAt: receivedAt
            )
        }

        snapshot.imports = importsByFilename.values.sorted { $0.receivedAt < $1.receivedAt }
        try writeSnapshot(snapshot, rootURL: rootURL)
        return snapshot
    }

    private func discardTombstonedFiles(in snapshot: inout Snapshot, rootURL: URL) {
        var remaining: [String] = []
        for filename in snapshot.discardedFilenames ?? [] {
            let url = rootURL.appendingPathComponent(filename, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                remaining.append(filename)
            }
        }
        snapshot.discardedFilenames = remaining
    }

    private func excludeFromBackup(_ url: URL) {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    private func loadSnapshot(rootURL: URL) -> Snapshot {
        let url = snapshotURL(rootURL: rootURL)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    private func writeSnapshot(_ snapshot: Snapshot, rootURL: URL) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotURL(rootURL: rootURL), options: [.atomic])
        excludeFromBackup(snapshotURL(rootURL: rootURL))
    }
}

struct ImportedImageMetadata: Equatable, Sendable {
    let captureDate: Date?
    let latitude: Double?
    let longitude: Double?

    var hasCoordinate: Bool {
        latitude != nil && longitude != nil
    }
}

enum ImportedImageMetadataExtractor {
    nonisolated static func extract(from fileURL: URL) -> ImportedImageMetadata {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ImportedImageMetadata(captureDate: nil, latitude: nil, longitude: nil)
        }
        return metadata(fromProperties: properties)
    }

    nonisolated static func metadata(
        fromProperties properties: [CFString: Any],
        defaultTimeZone: TimeZone = .current
    ) -> ImportedImageMetadata {
        let exif = dictionary(properties[kCGImagePropertyExifDictionary])
        let tiff = dictionary(properties[kCGImagePropertyTIFFDictionary])
        let gps = dictionary(properties[kCGImagePropertyGPSDictionary])

        let dateText = string(exif?[kCGImagePropertyExifDateTimeOriginal])
            ?? string(exif?[kCGImagePropertyExifDateTimeDigitized])
            ?? string(tiff?[kCGImagePropertyTIFFDateTime])
        let offsetText = string(exif?["OffsetTimeOriginal" as CFString])
        let captureDate = dateText.flatMap {
            parseExifDate($0, offset: offsetText, defaultTimeZone: defaultTimeZone)
        }

        let latitude = coordinate(
            value: gps?[kCGImagePropertyGPSLatitude],
            reference: string(gps?[kCGImagePropertyGPSLatitudeRef]),
            maximumMagnitude: 90,
            positiveReference: "N",
            negativeReference: "S"
        )
        let longitude = coordinate(
            value: gps?[kCGImagePropertyGPSLongitude],
            reference: string(gps?[kCGImagePropertyGPSLongitudeRef]),
            maximumMagnitude: 180,
            positiveReference: "E",
            negativeReference: "W"
        )

        guard latitude != nil, longitude != nil else {
            return ImportedImageMetadata(captureDate: captureDate, latitude: nil, longitude: nil)
        }
        return ImportedImageMetadata(captureDate: captureDate, latitude: latitude, longitude: longitude)
    }

    private nonisolated static func dictionary(_ value: Any?) -> [CFString: Any]? {
        if let dictionary = value as? [CFString: Any] {
            return dictionary
        }
        if let dictionary = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key as CFString, $0.value) })
        }
        return nil
    }

    private nonisolated static func string(_ value: Any?) -> String? {
        if let value = value as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private nonisolated static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let number = value as? Double {
            return number
        }
        if let text = value as? String {
            return Double(text)
        }
        return nil
    }

    private nonisolated static func coordinate(
        value: Any?,
        reference: String?,
        maximumMagnitude: Double,
        positiveReference: String,
        negativeReference: String
    ) -> Double? {
        guard let magnitude = number(value),
              magnitude.isFinite,
              magnitude >= 0,
              magnitude <= maximumMagnitude else {
            return nil
        }

        let normalizedReference = reference?.uppercased()
        guard normalizedReference == positiveReference || normalizedReference == negativeReference else {
            return nil
        }
        return normalizedReference == negativeReference ? -magnitude : magnitude
    }

    private nonisolated static func parseExifDate(
        _ value: String,
        offset: String?,
        defaultTimeZone: TimeZone
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)

        if let offset, !offset.isEmpty {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.date(from: value + offset)
        }

        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = defaultTimeZone
        return formatter.date(from: value)
    }
}
