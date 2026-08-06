import CoreImage
import Foundation
import SQLite3
import SwiftUI

enum ExternalReferenceImagePolicy {
    private static let suppressedHost = "inaturalist-open-data.s3.amazonaws.com"
    private static let suppressedPathPrefix = "/photos/605615444/"

    /// Suppresses the disturbing roadkill photo exposed by GBIF occurrence 5938154750.
    /// Matching its iNaturalist media directory also catches resized filename variants
    /// and query strings without affecting any other European wildcat imagery.
    static func isAllowed(_ url: URL) -> Bool {
        guard SecureTransportPolicy.isSecureRemoteURL(url) else { return false }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        return host != suppressedHost || !path.hasPrefix(suppressedPathPrefix)
    }

    static func isAllowed(_ rawValue: String) -> Bool {
        guard let url = SecureTransportPolicy.httpsURL(from: rawValue) else {
            return false
        }
        return isAllowed(url)
    }

    static func sanitizedURL(_ rawValue: String?) -> String? {
        guard let url = SecureTransportPolicy.httpsURL(from: rawValue),
              isAllowed(url) else {
            return nil
        }
        return url.absoluteString
    }

    static func url(from rawValue: String?) -> URL? {
        guard let url = SecureTransportPolicy.httpsURL(from: rawValue),
              isAllowed(url) else {
            return nil
        }
        return url
    }

    static func allowedURLStrings(from rawValue: String?) -> [String] {
        rawValue?
            .components(separatedBy: ",")
            .compactMap { sanitizedURL($0) } ?? []
    }

    static func sanitizedURLList(_ rawValue: String?) -> String? {
        let joined = allowedURLStrings(from: rawValue).joined(separator: ",")
        return joined.isEmpty ? nil : joined
    }
}

actor AsyncPermitPool {
    private var availablePermits: Int
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    init(limit: Int) {
        availablePermits = max(1, limit)
    }

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if availablePermits > 0 {
            availablePermits -= 1
            return true
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiterOrder.append(id)
                waiters[id] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id)
            }
        }
    }

    func release() {
        while let id = waiterOrder.first {
            waiterOrder.removeFirst()
            guard let continuation = waiters.removeValue(forKey: id) else { continue }
            continuation.resume(returning: true)
            return
        }
        availablePermits += 1
    }

    private func cancelWaiter(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        waiterOrder.removeAll { $0 == id }
        continuation.resume(returning: false)
    }
}

enum RemoteImageRetryPolicy {
    static let maximumAttempts = 3

    static func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 ||
            statusCode == 425 ||
            statusCode == 429 ||
            (500...599).contains(statusCode)
    }

    static func shouldRetry(urlErrorCode: URLError.Code) -> Bool {
        switch urlErrorCode {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .resourceUnavailable,
             .cannotLoadFromNetwork,
             .secureConnectionFailed,
             .badServerResponse,
             .zeroByteResource,
             .backgroundSessionWasDisconnected:
            return true
        default:
            // A reconnect changes the SwiftUI task identity and retries
            // .notConnectedToInternet without spinning while fully offline.
            return false
        }
    }

    static func delayMilliseconds(afterAttempt attempt: Int) -> Int {
        switch attempt {
        case 1: return 250
        default: return 750
        }
    }
}

enum LocalScanMediaRecoveryResolver {
    private static let mediaHost = "media.merian.app"
    private static let durableScanMediaPathPrefixes = [
        "/public_uploads/free/",
        "/public_uploads/pro/"
    ]
    private static let supportedImageExtensions: Set<String> = [
        "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
    ]
    private static let registry = LocalScanMediaRecoveryRegistry()
    private static let legacyIndex = LegacyScanMediaRecoveryIndex()

    static func existingLocalImageURL(
        for remoteURL: URL,
        documentsDirectory: URL = .documentsDirectory,
        fileManager: FileManager = .default
    ) -> URL? {
        let registeredFileName = registry.fileName(for: remoteURL)
        let fileNames = [registeredFileName].compactMap { $0 } +
            candidateFileNames(for: remoteURL)

        for fileName in fileNames {
            let candidateURL = documentsDirectory.appendingPathComponent(
                fileName,
                isDirectory: false
            )
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: candidateURL.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue else {
                continue
            }
            return candidateURL
        }
        return nil
    }

    static var hasLegacyRecoveryIndex: Bool {
        legacyIndex.hasRecords
    }

    @discardableResult
    static func registerRecoveryMappings(
        for records: [LocalScanRecord],
        documentsDirectory: URL = .documentsDirectory,
        fileManager: FileManager = .default
    ) -> Int {
        registerRecoveryMappings(
            records.map {
                CurrentScanRecoveryMedia(
                    scanID: $0.id,
                    timestamp: $0.timestamp,
                    coverImagePath: $0.coverImagePath,
                    items: $0.serializedCapturedMediaItems
                )
            },
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    static func registerRecoveryMappings(
        for responses: [HistoricalScanResponse],
        documentsDirectory: URL = .documentsDirectory,
        fileManager: FileManager = .default
    ) -> Int {
        registerRecoveryMappings(
            responses.map { response in
                let items = CapturedMediaSnapshot.cloudHydratedItems(
                    capturedMediaItems: response.captured_media,
                    imageStorageURLs: response.image_storage_urls,
                    videoStorageURLs: response.video_storage_urls
                )
                return CurrentScanRecoveryMedia(
                    scanID: response.id,
                    timestamp: historicalDate(response.created_at),
                    coverImagePath: CapturedMediaSnapshot(
                        items: items
                    ).primaryImagePath ??
                        response.image_storage_urls?.first,
                    items: items
                )
            },
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    static func registerRecoveryMapping(
        remoteURL: URL,
        localFileName: String
    ) -> Bool {
        guard !candidateFileNames(for: remoteURL).isEmpty,
              isSafeImageFileName(localFileName) else {
            return false
        }
        return registry.register(remoteURL: remoteURL, fileName: localFileName)
    }

    static func resetRegisteredRecoveryMappingsForTesting() {
        registry.reset()
    }

    @discardableResult
    static func registerTimestampRecoveryMappingsForTesting(
        scanID: String,
        timestamp: Date,
        remoteImageURLs: [URL],
        documentsDirectory: URL,
        fileManager: FileManager = .default
    ) -> Int {
        registerTimestampRecoveryMappings(
            [
                TimestampScanRecoveryCandidate(
                    scanID: scanID,
                    timestamp: timestamp,
                    remoteImageURLs: remoteImageURLs
                )
            ],
            documentsDirectory: documentsDirectory,
            fileManager: fileManager,
            requiresLegacyIndex: false
        )
    }

    static func candidateFileNames(for remoteURL: URL) -> [String] {
        guard remoteURL.scheme?.lowercased() == "https",
              remoteURL.host?.lowercased() == mediaHost,
              durableScanMediaPathPrefixes.contains(where: {
                  remoteURL.path.lowercased().hasPrefix($0)
              }) else {
            return []
        }

        let publicFileName = remoteURL.lastPathComponent
        guard isSafeImageFileName(publicFileName) else { return [] }

        var candidates = [publicFileName]

        // Current staging names are `{scanId}_{Documents filename}`. Promotion
        // preserves that basename, while the surviving local file keeps only
        // the Documents filename.
        if let separator = publicFileName.firstIndex(of: "_") {
            let scanId = String(publicFileName[..<separator])
            let localFileName = String(publicFileName[publicFileName.index(after: separator)...])
            if UUID(uuidString: scanId) != nil,
               isSafeImageFileName(localFileName),
               localFileName != publicFileName {
                candidates.append(localFileName)
            }
        }

        return candidates
    }

    private static func isSafeImageFileName(_ fileName: String) -> Bool {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              fileName == (fileName as NSString).lastPathComponent,
              supportedImageExtensions.contains(
                  (fileName as NSString).pathExtension.lowercased()
              ) else {
            return false
        }

        return fileName.range(
            of: #"^[A-Za-z0-9_.-]+$"#,
            options: .regularExpression
        ) != nil
    }

    private static func registerRecoveryMappings(
        _ currentScans: [CurrentScanRecoveryMedia],
        documentsDirectory: URL,
        fileManager: FileManager
    ) -> Int {
        guard legacyIndex.hasRecords else { return 0 }

        var registeredCount = 0
        for currentScan in currentScans {
            guard let legacyRecord = legacyIndex.record(
                for: currentScan.scanID
            ) else {
                continue
            }

            let legacySnapshot = CapturedMediaSnapshot(
                jsonString: legacyRecord.capturedMediaJSON
            )
            let currentSnapshot = CapturedMediaSnapshot(
                items: currentScan.items
            )

            if let remoteURL = durableRemoteImageURL(
                from: currentScan.coverImagePath
            ), let localFileName = existingLocalImageFileName(
                from: legacyRecord.coverImagePath,
                documentsDirectory: documentsDirectory,
                fileManager: fileManager
            ), registry.register(
                remoteURL: remoteURL,
                fileName: localFileName
            ) {
                registeredCount += 1
            }

            registeredCount += registerAlignedReferences(
                legacySnapshot.imageReferences,
                currentSnapshot.imageReferences,
                documentsDirectory: documentsDirectory,
                fileManager: fileManager
            )
            registeredCount += registerAlignedReferences(
                legacySnapshot.videoThumbnailReferences,
                currentSnapshot.videoThumbnailReferences,
                documentsDirectory: documentsDirectory,
                fileManager: fileManager
            )
        }

        let timestampCandidates = currentScans.compactMap { currentScan
            -> TimestampScanRecoveryCandidate? in
            guard legacyIndex.record(for: currentScan.scanID) == nil,
                  let timestamp = currentScan.timestamp else {
                return nil
            }

            let snapshot = CapturedMediaSnapshot(items: currentScan.items)
            let rawReferences = [currentScan.coverImagePath] +
                snapshot.imageReferences.map(\.serializedPath) +
                snapshot.videoThumbnailReferences.map(\.serializedPath)
            var seenURLs = Set<String>()
            let remoteImageURLs = rawReferences.compactMap {
                durableRemoteImageURL(from: $0)
            }.filter {
                seenURLs.insert($0.absoluteString).inserted
            }
            guard !remoteImageURLs.isEmpty else { return nil }

            return TimestampScanRecoveryCandidate(
                scanID: currentScan.scanID,
                timestamp: timestamp,
                remoteImageURLs: remoteImageURLs
            )
        }
        registeredCount += registerTimestampRecoveryMappings(
            timestampCandidates,
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        )
        return registeredCount
    }

    private static func registerTimestampRecoveryMappings(
        _ scans: [TimestampScanRecoveryCandidate],
        documentsDirectory: URL,
        fileManager: FileManager,
        requiresLegacyIndex: Bool = true
    ) -> Int {
        guard !requiresLegacyIndex || legacyIndex.hasRecords else { return 0 }

        var usedFileNames = registry.registeredFileNames
        for scan in scans {
            for remoteURL in scan.remoteImageURLs {
                if let localURL = existingLocalImageURL(
                    for: remoteURL,
                    documentsDirectory: documentsDirectory,
                    fileManager: fileManager
                ) {
                    usedFileNames.insert(localURL.lastPathComponent)
                }
            }
        }

        var availableGroups = timestampRecoveryGroups(
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        )
        var registeredCount = 0

        for scan in scans.sorted(by: { $0.timestamp < $1.timestamp }) {
            // A direct filename or rescue-store match is stronger than time.
            guard !scan.remoteImageURLs.contains(where: {
                existingLocalImageURL(
                    for: $0,
                    documentsDirectory: documentsDirectory,
                    fileManager: fileManager
                ) != nil
            }) else {
                continue
            }

            let candidates = availableGroups.indices.filter { index in
                let group = availableGroups[index]
                let delay = scan.timestamp.timeIntervalSince(
                    group.modificationDate
                )
                return group.fileNames.count == scan.remoteImageURLs.count &&
                    (0 ... 60).contains(delay) &&
                    group.fileNames.allSatisfy {
                        !usedFileNames.contains($0)
                    }
            }.sorted {
                availableGroups[$0].modificationDate >
                    availableGroups[$1].modificationDate
            }

            guard let selectedIndex = candidates.first else { continue }
            if candidates.count > 1 {
                let selectedDate = availableGroups[selectedIndex]
                    .modificationDate
                let nextDate = availableGroups[candidates[1]]
                    .modificationDate
                guard selectedDate.timeIntervalSince(nextDate) >= 3 else {
                    continue
                }
            }

            let group = availableGroups[selectedIndex]
            let groupRegistrationCount = zip(
                scan.remoteImageURLs,
                group.fileNames
            ).reduce(into: 0) { count, pair in
                let (remoteURL, fileName) = pair
                if registry.register(
                    remoteURL: remoteURL,
                    fileName: fileName
                ) {
                    count += 1
                }
            }
            guard groupRegistrationCount == group.fileNames.count else {
                continue
            }

            registeredCount += groupRegistrationCount
            usedFileNames.formUnion(group.fileNames)
            availableGroups.remove(at: selectedIndex)
        }
        return registeredCount
    }

    private static func timestampRecoveryGroups(
        documentsDirectory: URL,
        fileManager: FileManager
    ) -> [TimestampScanRecoveryFileGroup] {
        let resourceKeys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .isRegularFileKey
        ]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entriesBySecond: [Int: [TimestampScanRecoveryFileEntry]] = [:]
        for url in urls {
            let fileName = url.lastPathComponent
            guard isSafeImageFileName(fileName),
                  let role = timestampRecoveryRole(for: fileName),
                  let values = try? url.resourceValues(
                      forKeys: resourceKeys
                  ),
                  values.isRegularFile == true,
                  let modificationDate = values.contentModificationDate else {
                continue
            }
            let second = Int(
                modificationDate.timeIntervalSince1970.rounded(.down)
            )
            entriesBySecond[second, default: []].append(
                TimestampScanRecoveryFileEntry(
                    fileName: fileName,
                    modificationDate: modificationDate,
                    role: role
                )
            )
        }

        return entriesBySecond.values.compactMap { entries in
            let primaryEntries = entries.filter { $0.role == .primary }
            guard primaryEntries.count == 1 else { return nil }

            let additionalEntries = entries.compactMap { entry
                -> (index: Int, entry: TimestampScanRecoveryFileEntry)? in
                guard case .additional(let index) = entry.role else {
                    return nil
                }
                return (index, entry)
            }.sorted { $0.index < $1.index }
            guard additionalEntries.enumerated().allSatisfy({
                $0.offset + 1 == $0.element.index
            }) else {
                return nil
            }

            let primary = primaryEntries[0]
            return TimestampScanRecoveryFileGroup(
                modificationDate: primary.modificationDate,
                fileNames: [primary.fileName] +
                    additionalEntries.map(\.entry.fileName)
            )
        }.sorted { $0.modificationDate < $1.modificationDate }
    }

    private static func timestampRecoveryRole(
        for fileName: String
    ) -> TimestampScanRecoveryFileRole? {
        let stem = (fileName as NSString).deletingPathExtension.lowercased()
        if stem.hasSuffix("_scan") {
            return .primary
        }

        guard let match = stem.range(
            of: #"_additional_([1-9][0-9]*)$"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let suffix = stem[match]
        guard let separator = suffix.lastIndex(of: "_"),
              let index = Int(suffix[suffix.index(after: separator)...]) else {
            return nil
        }
        return .additional(index)
    }

    private static func historicalDate(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        return DateUtilities.iso8601FractionalFormatter.date(from: timestamp)
            ?? DateUtilities.iso8601Formatter.date(from: timestamp)
    }

    private static func registerAlignedReferences(
        _ legacyReferences: [StoredMediaReference],
        _ currentReferences: [StoredMediaReference],
        documentsDirectory: URL,
        fileManager: FileManager
    ) -> Int {
        guard legacyReferences.count == currentReferences.count else {
            return 0
        }

        var registeredCount = 0
        for (legacyReference, currentReference) in zip(
            legacyReferences,
            currentReferences
        ) {
            guard let remoteURL = durableRemoteImageURL(
                from: currentReference.serializedPath
            ), let localFileName = existingLocalImageFileName(
                from: legacyReference.serializedPath,
                documentsDirectory: documentsDirectory,
                fileManager: fileManager
            ), registry.register(
                remoteURL: remoteURL,
                fileName: localFileName
            ) else {
                continue
            }
            registeredCount += 1
        }
        return registeredCount
    }

    private static func durableRemoteImageURL(from rawValue: String?) -> URL? {
        guard let url = ExternalReferenceImagePolicy.url(from: rawValue),
              !candidateFileNames(for: url).isEmpty else {
            return nil
        }
        return url
    }

    private static func existingLocalImageFileName(
        from rawValue: String?,
        documentsDirectory: URL,
        fileManager: FileManager
    ) -> String? {
        guard let rawValue,
              !rawValue.lowercased().hasPrefix("http://"),
              !rawValue.lowercased().hasPrefix("https://") else {
            return nil
        }

        let fileName = (rawValue as NSString).lastPathComponent
        guard isSafeImageFileName(fileName) else { return nil }

        let fileURL = documentsDirectory.appendingPathComponent(
            fileName,
            isDirectory: false
        )
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: fileURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            return nil
        }
        return fileName
    }
}

private struct CurrentScanRecoveryMedia {
    let scanID: String
    let timestamp: Date?
    let coverImagePath: String?
    let items: [SerializedMediaItem]
}

private struct TimestampScanRecoveryCandidate {
    let scanID: String
    let timestamp: Date
    let remoteImageURLs: [URL]
}

private struct TimestampScanRecoveryFileGroup {
    let modificationDate: Date
    let fileNames: [String]
}

private struct TimestampScanRecoveryFileEntry {
    let fileName: String
    let modificationDate: Date
    let role: TimestampScanRecoveryFileRole
}

private enum TimestampScanRecoveryFileRole: Equatable {
    case primary
    case additional(Int)
}

private struct LegacyScanMediaRecoveryRecord {
    let coverImagePath: String?
    let capturedMediaJSON: String?
}

private final class LocalScanMediaRecoveryRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var fileNamesByRemoteURL: [String: String] = [:]

    func fileName(for remoteURL: URL) -> String? {
        guard let key = canonicalKey(for: remoteURL) else { return nil }
        return lock.withLock {
            fileNamesByRemoteURL[key]
        }
    }

    @discardableResult
    func register(remoteURL: URL, fileName: String) -> Bool {
        guard let key = canonicalKey(for: remoteURL) else { return false }
        return lock.withLock {
            if fileNamesByRemoteURL[key] != nil {
                return false
            }
            fileNamesByRemoteURL[key] = fileName
            return true
        }
    }

    var registeredFileNames: Set<String> {
        lock.withLock {
            Set(fileNamesByRemoteURL.values)
        }
    }

    func reset() {
        lock.withLock {
            fileNamesByRemoteURL.removeAll()
        }
    }

    private func canonicalKey(for url: URL) -> String? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }
}

private final class LegacyScanMediaRecoveryIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedRecords: [String: LegacyScanMediaRecoveryRecord]?

    var hasRecords: Bool {
        !records().isEmpty
    }

    func record(for scanID: String) -> LegacyScanMediaRecoveryRecord? {
        records()[scanID.lowercased()]
    }

    private func records() -> [String: LegacyScanMediaRecoveryRecord] {
        lock.withLock {
            if let cachedRecords {
                return cachedRecords
            }
            let loadedRecords = loadRecords()
            cachedRecords = loadedRecords
            return loadedRecords
        }
    }

    private func loadRecords(
        applicationSupportDirectory: URL = .applicationSupportDirectory,
        fileManager: FileManager = .default
    ) -> [String: LegacyScanMediaRecoveryRecord] {
        let rescueRoot = applicationSupportDirectory.appendingPathComponent(
            "store-rescue",
            isDirectory: true
        )
        guard let archiveDirectories = try? fileManager.contentsOfDirectory(
            at: rescueRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        let storeURLs = archiveDirectories
            .map {
                $0.appendingPathComponent("default.store", isDirectory: false)
            }
            .filter { fileManager.fileExists(atPath: $0.path) }
            .sorted { $0.path > $1.path }

        var recordsByID: [String: LegacyScanMediaRecoveryRecord] = [:]
        for storeURL in storeURLs {
            for (scanID, record) in readRecords(from: storeURL)
                where recordsByID[scanID] == nil {
                recordsByID[scanID] = record
            }
        }
        return recordsByID
    }

    private func readRecords(
        from storeURL: URL
    ) -> [String: LegacyScanMediaRecoveryRecord] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            if database != nil {
                sqlite3_close(database)
            }
            return [:]
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT ZID, ZCOVERIMAGEPATH, ZCAPTUREDMEDIAJSON
        FROM ZLOCALSCANRECORD
        WHERE ZID IS NOT NULL
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            query,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var recordsByID: [String: LegacyScanMediaRecoveryRecord] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let scanID = stringValue(
                from: statement,
                column: 0
            )?.lowercased() else {
                continue
            }
            recordsByID[scanID] = LegacyScanMediaRecoveryRecord(
                coverImagePath: stringValue(from: statement, column: 1),
                capturedMediaJSON: stringValue(from: statement, column: 2)
            )
        }
        return recordsByID
    }

    private func stringValue(
        from statement: OpaquePointer,
        column: Int32
    ) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: text)
    }
}

private struct CloudScanImageRepairCandidate: Sendable {
    let sourceUrl: String
    let localUrl: URL
}

actor CloudScanImageRepairActor {
    static let shared = CloudScanImageRepairActor()

    private var pending: [CloudScanImageRepairCandidate] = []
    private var pendingSourceUrls: Set<String> = []
    private var completedSourceUrls: Set<String> = []
    private var isProcessing = false
    private var serviceUnavailableUntil: Date?
    private let retryDelay: TimeInterval = 15 * 60

    func enqueue(sourceUrl: URL, localUrl: URL) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let candidate = Self.candidate(sourceUrl: sourceUrl, localUrl: localUrl),
              !completedSourceUrls.contains(candidate.sourceUrl),
              !pendingSourceUrls.contains(candidate.sourceUrl),
              serviceUnavailableUntil.map({ $0 <= Date() }) ?? true else {
            return
        }

        pending.append(candidate)
        pendingSourceUrls.insert(candidate.sourceUrl)
        guard !isProcessing else { return }

        isProcessing = true
        Task(priority: .utility) {
            await self.drainQueue()
        }
    }

    private func drainQueue() async {
        while !pending.isEmpty {
            if let serviceUnavailableUntil, serviceUnavailableUntil > Date() {
                pending.removeAll()
                pendingSourceUrls.removeAll()
                break
            }

            let candidate = pending.removeFirst()
            pendingSourceUrls.remove(candidate.sourceUrl)

            do {
                try await repairIfMissing(candidate)
                completedSourceUrls.insert(candidate.sourceUrl)
            } catch {
                serviceUnavailableUntil = Date().addingTimeInterval(retryDelay)
                pending.removeAll()
                pendingSourceUrls.removeAll()
                MerianLog.network.error(
                    "Cloud scan image repair paused after a failed request; retrying later."
                )
            }
        }

        isProcessing = false
    }

    private func repairIfMissing(_ candidate: CloudScanImageRepairCandidate) async throws {
        let inspection = try await MerianNetworkClient.shared.inspectScanImageCloudStatus(
            sourceUrl: candidate.sourceUrl
        )
        guard inspection.status == .missing else { return }

        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: candidate.localUrl.path
        ) else {
            return
        }
        let sizeBytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard sizeBytes > 0,
              sizeBytes <= MerianConfig.stagedImagePayloadMaxBytes,
              let contentType = Self.contentType(for: candidate.localUrl) else {
            return
        }

        let fileExtension = candidate.localUrl.pathExtension.lowercased()
        let uploadFile = StagingUploadFile(
            fileName: "repair_\(UUID().uuidString.lowercased()).\(fileExtension)",
            mediaKind: .image,
            contentType: contentType,
            sizeBytes: sizeBytes
        )
        let uploadUrls = try await MerianNetworkClient.shared.generateUploadURLs(
            uploadFiles: [uploadFile]
        )
        guard let uploadUrl = uploadUrls.first, uploadUrls.count == 1 else {
            throw MerianError.invalidResponse
        }

        try await MerianNetworkClient.shared.uploadToR2(
            uploadURL: uploadUrl,
            fileURL: candidate.localUrl,
            contentType: contentType
        )
        let result = try await MerianNetworkClient.shared.repairScanImageCloudReference(
            sourceUrl: candidate.sourceUrl,
            restoredObjectKey: uploadUrl.objectKey
        )
        guard result.status == .repaired || result.status == .healthy else {
            throw MerianError.invalidResponse
        }

        if result.status == .repaired {
            MerianLog.network.info(
                "Cloud scan image repair restored \(result.updatedScanCount, privacy: .public) scan record(s) and \(result.updatedPostMediaCount, privacy: .public) Explore media record(s)."
            )
            await MainActor.run {
                ScanLibraryEvents.postLibraryDidUpdate()
            }
        }
    }

    private static func candidate(
        sourceUrl: URL,
        localUrl: URL
    ) -> CloudScanImageRepairCandidate? {
        guard LocalScanMediaRecoveryResolver.candidateFileNames(
            for: sourceUrl
        ).isEmpty == false,
              FileManager.default.fileExists(atPath: localUrl.path),
              contentType(for: localUrl) != nil,
              var components = URLComponents(
                  url: sourceUrl,
                  resolvingAgainstBaseURL: false
              ) else {
            return nil
        }

        components.query = nil
        components.fragment = nil
        guard let canonicalUrl = components.url?.absoluteString else {
            return nil
        }
        return CloudScanImageRepairCandidate(
            sourceUrl: canonicalUrl,
            localUrl: localUrl
        )
    }

    private static func contentType(for fileUrl: URL) -> String? {
        switch fileUrl.pathExtension.lowercased() {
        case "webp":
            return "image/webp"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        default:
            return nil
        }
    }
}

private actor RemoteImageLoadDiagnostics {
    static let shared = RemoteImageLoadDiagnostics()

    private var lastLoggedAt: [String: Date] = [:]
    private let throttleInterval: TimeInterval = 30

    func recordHTTPFailure(url: URL, statusCode: Int) {
        let host = sanitizedHost(for: url)
        guard shouldLog(key: "\(host)|http|\(statusCode)") else { return }
        MerianLog.network.error(
            "LocalImageLoader: remote media HTTP failure host=\(host, privacy: .public) status=\(statusCode, privacy: .public)"
        )
    }

    func recordTransportFailure(url: URL, errorDomain: String, errorCode: Int) {
        let host = sanitizedHost(for: url)
        guard shouldLog(key: "\(host)|transport|\(errorDomain)|\(errorCode)") else { return }
        MerianLog.network.error(
            "LocalImageLoader: remote media transport failure host=\(host, privacy: .public) domain=\(errorDomain, privacy: .public) code=\(errorCode, privacy: .public)"
        )
    }

    func recordInvalidResponse(url: URL) {
        let host = sanitizedHost(for: url)
        guard shouldLog(key: "\(host)|invalid-response") else { return }
        MerianLog.network.error(
            "LocalImageLoader: remote media returned a non-HTTP response host=\(host, privacy: .public)"
        )
    }

    func recordDecodeFailure(url: URL) {
        let host = sanitizedHost(for: url)
        guard shouldLog(key: "\(host)|decode") else { return }
        MerianLog.network.error(
            "LocalImageLoader: remote media decode failed host=\(host, privacy: .public)"
        )
    }

    func recordLocalRecovery(url: URL) {
        let host = sanitizedHost(for: url)
        guard shouldLog(key: "\(host)|local-recovery") else { return }
        MerianLog.network.info(
            "LocalImageLoader: recovered durable scan image from Documents host=\(host, privacy: .public)"
        )
    }

    private func sanitizedHost(for url: URL) -> String {
        url.host?.lowercased() ?? "unknown"
    }

    private func shouldLog(key: String) -> Bool {
        let now = Date()
        if let lastLogged = lastLoggedAt[key],
           now.timeIntervalSince(lastLogged) < throttleInterval {
            return false
        }
        lastLoggedAt[key] = now
        return true
    }
}

// MARK: - Core Image Processing Engine
/// Unifies APFS file rendering, sandbox extractions, and Cloudflare R2 loading autonomously handling physical cache networks natively.
actor LocalImageLoader {
    // MARK: - Singleton Architecture
    static let shared = LocalImageLoader()
    
    // MARK: - Thread-Safe Task Queues
    private var activeTasks: [String: Task<UIImage?, Never>] = [:]

    // Suspends excess decode tasks without blocking an OS thread. ImageIO still runs on
    // an explicit QoS queue so synchronous Core Graphics work never occupies a Swift
    // cooperative-executor thread.
    private static let decodePermits = AsyncPermitPool(limit: 4)
    private static let decodeQueue = DispatchQueue(
        label: "app.merian.image-decode",
        qos: .userInitiated,
        attributes: .concurrent
    )

    // Isolated session for media downloads (R2, Wikipedia thumbnails, GBIF images).
    // Separate from URLSession.shared to avoid inheriting the system-wide pool and to
    // enforce explicit timeouts without cross-contaminating auth sessions.
    private static let mediaSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpMaximumConnectionsPerHost = 4
        config.httpShouldSetCookies = false
        // Explore/profile thumbnails are immutable, versioned media URLs. Keep their
        // responses across view reconstruction and app launches instead of forcing R2
        // to serve the same bytes whenever the in-memory UIImage cache is cold.
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "MerianMediaCache"
        )
        return URLSession(configuration: config)
    }()
    
    // MARK: - Asset Orchestration
    func loadImage(fromPath imagePath: String?, fallbackUrl: String? = nil, maxDimension: Int = 1024) async -> UIImage? {
        let safeImagePath: String?
        if let imagePath {
            let trimmed = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = URL(string: trimmed),
               parsed.scheme != nil,
               !parsed.isFileURL {
                safeImagePath = ExternalReferenceImagePolicy.sanitizedURL(trimmed)
            } else {
                safeImagePath = trimmed.isEmpty ? nil : trimmed
            }
        } else {
            safeImagePath = nil
        }
        let safeFallbackUrl = ExternalReferenceImagePolicy.sanitizedURLList(fallbackUrl)

        guard let baseKey = safeImagePath ?? safeFallbackUrl else {
            return nil
        }
        
        let cacheKey = "\(baseKey)_\(maxDimension)"
        
        // 1. RAM Cache Hit
        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            return cached
        }
        
        // 2. Thundering Herd Request Coalescing
        if let existingTask = activeTasks[cacheKey] {
            return await existingTask.value
        }
        
        let fetchTask = Task.detached(priority: .userInitiated) { () -> UIImage? in
            // 3. Remote URL Execution (if 'imagePath' is actually a cloud URL payload directly)
            if let remoteUrl = ExternalReferenceImagePolicy.url(
                from: safeImagePath
            ) {
                if let localURL = LocalScanMediaRecoveryResolver.existingLocalImageURL(for: remoteUrl),
                   let localImage = await LocalImageLoader.decodeImage(
                       url: localURL,
                       cacheKey: cacheKey,
                       maxSize: CGFloat(maxDimension)
                   ) {
                    await RemoteImageLoadDiagnostics.shared.recordLocalRecovery(url: remoteUrl)
                    await CloudScanImageRepairActor.shared.enqueue(
                        sourceUrl: remoteUrl,
                        localUrl: localURL
                    )
                    return localImage
                }

                if let networkImage = await LocalImageLoader.fetchRemote(url: remoteUrl, cacheKey: cacheKey, maxSize: CGFloat(maxDimension)) {
                    return networkImage
                }
            }
            // 4. Local File Extraction directly off Main Thread
            else if let safePath = safeImagePath, !safePath.isEmpty {
                if let image = await LocalImageLoader.loadLocal(
                    path: safePath,
                    cacheKey: cacheKey,
                    maxSize: CGFloat(maxDimension)
                ) {
                    return image
                }
            }

            // 5. Explicit Network Fallback explicitly routing legacy bounds
            if let fallbackUrlString = safeFallbackUrl {
                let urls = fallbackUrlString.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .compactMap { ExternalReferenceImagePolicy.url(from: $0) }

                for url in urls {
                    // We intentionally do NOT check `Task.isCancelled` here because this is a
                    // detached task serving multiple coalesced callers. We want it to finish caching.
                    if let localURL = LocalScanMediaRecoveryResolver.existingLocalImageURL(for: url),
                       let localImage = await LocalImageLoader.decodeImage(
                           url: localURL,
                           cacheKey: cacheKey,
                           maxSize: CGFloat(maxDimension)
                    ) {
                        await RemoteImageLoadDiagnostics.shared.recordLocalRecovery(url: url)
                        await CloudScanImageRepairActor.shared.enqueue(
                            sourceUrl: url,
                            localUrl: localURL
                        )
                        return localImage
                    }

                    if let networkImage = await LocalImageLoader.fetchRemote(url: url, cacheKey: cacheKey, maxSize: CGFloat(maxDimension)) {
                        return networkImage
                    }
                }
            }

            return nil
        }
        
        activeTasks[cacheKey] = fetchTask
        
        defer {
            if activeTasks[cacheKey] == fetchTask {
                activeTasks.removeValue(forKey: cacheKey)
            }
        }
        
        return await fetchTask.value
    }
    
    // MARK: - Prefetch API

    /// Warms the in-memory cache for a leading set of thumbnails before the grid renders.
    /// Results land in ImageCache so ScanThumbnail.task gets an immediate cache hit instead
    /// of starting a cold decode after the cell becomes visible.
    ///
    /// Uses .utility priority: runs immediately and freely on background threads without
    /// competing with the main render loop or camera capture (which runs on its own
    /// DispatchQueue entirely outside the Swift concurrency thread pool).
    /// Concurrency is capped at 4 to avoid thermal spikes on older devices.
    nonisolated func prefetch(
        records: [(imagePath: String?, fallbackUrl: String?)],
        maxDimension: Int
    ) {
        Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for record in records {
                    if inFlight >= 4 {
                        await group.next()
                        inFlight -= 1
                    }
                    group.addTask(priority: .utility) {
                        _ = await self.loadImage(
                            fromPath: record.imagePath,
                            fallbackUrl: record.fallbackUrl,
                            maxDimension: maxDimension
                        )
                    }
                    inFlight += 1
                }
            }
        }
    }

    // MARK: - Nonisolated Fetch Helpers
    // Static nonisolated functions so the Task.detached body above never re-enters the actor's
    // executor mid-operation. All I/O and CGImage work runs on the detached task's thread pool;
    // only the final ImageCache.shared.set call crosses into the cache (which is @unchecked Sendable).

    /// Decodes a local APFS file path into a UIImage without touching the actor's executor.
    private static nonisolated func loadLocal(
        path: String,
        cacheKey: String,
        maxSize: CGFloat
    ) async -> UIImage? {
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else if let fileURL = URL(string: path), fileURL.isFileURL {
            url = fileURL
        } else {
            let filename = (path as NSString).lastPathComponent
            url = URL.documentsDirectory.appendingPathComponent(filename)
        }
        
        return await decodeImage(url: url, cacheKey: cacheKey, maxSize: maxSize)
    }

    /// Downloads a remote URL, downsamples, and caches — entirely off the actor executor.
    static nonisolated func fetchRemote(url: URL, cacheKey: String, maxSize: CGFloat = 500) async -> UIImage? {
        if Task.isCancelled
            || !SecureTransportPolicy.isSecureRemoteURL(url)
            || !ExternalReferenceImagePolicy.isAllowed(url) {
            return nil
        }

        for attempt in 1...RemoteImageRetryPolicy.maximumAttempts {
            if Task.isCancelled { return nil }

            do {
                var request = URLRequest(url: url)
                if attempt > 1 {
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                }

                let (tempURL, response) = try await LocalImageLoader.mediaSession.download(for: request)
                defer { try? FileManager.default.removeItem(at: tempURL) }

                guard let httpResponse = response as? HTTPURLResponse else {
                    await RemoteImageLoadDiagnostics.shared.recordInvalidResponse(url: url)
                    return nil
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    if attempt < RemoteImageRetryPolicy.maximumAttempts,
                       RemoteImageRetryPolicy.shouldRetry(statusCode: httpResponse.statusCode),
                       await waitBeforeRemoteRetry(afterAttempt: attempt) {
                        continue
                    }

                    await RemoteImageLoadDiagnostics.shared.recordHTTPFailure(
                        url: url,
                        statusCode: httpResponse.statusCode
                    )
                    return nil
                }

                if Task.isCancelled { return nil }
                if let image = await decodeImage(
                    url: tempURL,
                    cacheKey: cacheKey,
                    maxSize: maxSize
                ) {
                    return image
                }

                if attempt < RemoteImageRetryPolicy.maximumAttempts,
                   await waitBeforeRemoteRetry(afterAttempt: attempt) {
                    continue
                }

                await RemoteImageLoadDiagnostics.shared.recordDecodeFailure(url: url)
                return nil
            } catch is CancellationError {
                return nil
            } catch {
                let nsError = error as NSError
                let urlErrorCode = (error as? URLError)?.code

                if attempt < RemoteImageRetryPolicy.maximumAttempts,
                   let urlErrorCode,
                   RemoteImageRetryPolicy.shouldRetry(urlErrorCode: urlErrorCode),
                   await waitBeforeRemoteRetry(afterAttempt: attempt) {
                    continue
                }

                if urlErrorCode != .cancelled {
                    await RemoteImageLoadDiagnostics.shared.recordTransportFailure(
                        url: url,
                        errorDomain: nsError.domain,
                        errorCode: nsError.code
                    )
                }
                return nil
            }
        }

        return nil
    }

    private static nonisolated func waitBeforeRemoteRetry(afterAttempt attempt: Int) async -> Bool {
        do {
            try await Task.sleep(
                for: .milliseconds(RemoteImageRetryPolicy.delayMilliseconds(afterAttempt: attempt))
            )
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private static nonisolated func decodeImage(
        url: URL,
        cacheKey: String,
        maxSize: CGFloat
    ) async -> UIImage? {
        guard await decodePermits.acquire() else { return nil }
        if Task.isCancelled {
            await decodePermits.release()
            return nil
        }

        let image: UIImage? = await withCheckedContinuation { continuation in
            decodeQueue.async {
                guard let cgImage = ImageDownsampler.downsample(url: url, maxSize: maxSize) else {
                    continuation.resume(returning: nil)
                    return
                }
                let result = UIImage(cgImage: cgImage)
                ImageCache.shared.set(result, forKey: cacheKey)
                continuation.resume(returning: result)
            }
        }
        await decodePermits.release()
        return image
    }
}
