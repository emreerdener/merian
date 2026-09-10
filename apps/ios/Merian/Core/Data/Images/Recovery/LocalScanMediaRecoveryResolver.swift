import Foundation

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
            for: records.map(LocalScanMediaRecoverySnapshot.init(record:)),
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
            for: responses.map(
                LocalScanMediaRecoverySnapshot.init(response:)
            ),
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    static func registerRecoveryMappings(
        for snapshots: [LocalScanMediaRecoverySnapshot],
        documentsDirectory: URL = .documentsDirectory,
        fileManager: FileManager = .default
    ) -> Int {
        registerRecoveryMappings(
            snapshots,
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    static func registerStrongEvidenceRecoveryMappings(
        for snapshots: [LocalScanMediaRecoverySnapshot],
        documentsDirectory: URL = .documentsDirectory,
        fileManager: FileManager = .default
    ) -> Int {
        registerStrongEvidenceRecoveryMappings(
            snapshots,
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    static func registerTimestampRecoveryMappings(
        for snapshots: [LocalScanMediaRecoverySnapshot],
        documentsDirectory: URL = .documentsDirectory,
        fileManager: FileManager = .default
    ) -> Int {
        registerTimestampRecoveryMappings(
            timestampRecoveryCandidates(for: snapshots),
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
        return registry.registerStrongMapping(
            remoteURL: remoteURL,
            fileName: localFileName
        )
    }

    static func resetRegisteredRecoveryMappingsForTesting() {
        resetRegisteredRecoveryMappings()
    }

    static func resetRegisteredRecoveryMappings() {
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
        guard let canonicalURL = canonicalRecoverySourceURL(
            for: remoteURL
        ) else {
            return []
        }

        let publicFileName = canonicalURL.lastPathComponent

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

    static func canonicalRecoverySourceURL(for remoteURL: URL) -> URL? {
        guard let secureURL = SecureTransportPolicy.httpsURL(
            from: remoteURL.absoluteString
        ), var components = URLComponents(
            url: secureURL,
            resolvingAgainstBaseURL: false
        ), let host = components.host?.lowercased(), host == mediaHost,
        durableScanMediaPathPrefixes.contains(where: {
            secureURL.path.lowercased().hasPrefix($0)
        }) else {
            return nil
        }

        components.scheme = "https"
        components.host = host
        if components.port == 443 {
            components.port = nil
        }
        components.query = nil
        components.fragment = nil
        guard let canonicalURL = components.url,
              isSafeImageFileName(canonicalURL.lastPathComponent) else {
            return nil
        }
        return canonicalURL
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
        _ currentScans: [LocalScanMediaRecoverySnapshot],
        documentsDirectory: URL,
        fileManager: FileManager
    ) -> Int {
        guard legacyIndex.hasRecords else { return 0 }

        return registerStrongEvidenceRecoveryMappings(
            currentScans,
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        ) + registerTimestampRecoveryMappings(
            for: currentScans,
            documentsDirectory: documentsDirectory,
            fileManager: fileManager
        )
    }

    private static func registerStrongEvidenceRecoveryMappings(
        _ currentScans: [LocalScanMediaRecoverySnapshot],
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
            ), registry.registerStrongMapping(
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

        return registeredCount
    }

    private static func timestampRecoveryCandidates(
        for currentScans: [LocalScanMediaRecoverySnapshot]
    ) -> [TimestampScanRecoveryCandidate] {
        currentScans.compactMap { currentScan
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

        for scan in scans.sorted(by: {
            if $0.timestamp == $1.timestamp {
                return $0.scanID < $1.scanID
            }
            return $0.timestamp < $1.timestamp
        }) {
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
            guard registry.registerTimestampMappings(
                remoteURLs: scan.remoteImageURLs,
                fileNames: group.fileNames
            ) else {
                continue
            }

            registeredCount += group.fileNames.count
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
            ), registry.registerStrongMapping(
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
