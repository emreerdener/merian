import Foundation

private struct CloudScanImageRepairCandidate: Sendable {
    let sourceURL: String
    let localURL: URL
}

actor CloudScanImageRepairActor {
    struct Dependencies: Sendable {
        let shouldRun: @Sendable () -> Bool
        let now: @Sendable () -> Date
        let fileExists: @Sendable (URL) -> Bool
        let isVerifiedRecovery: @Sendable (URL, URL) -> Bool
        let fileSizeBytes: @Sendable (URL) -> Int?
        let makeUUID: @Sendable () -> UUID
        let inspect:
            @Sendable (String) async throws -> ScanImageCloudInspection
        let generateUploadURLs:
            @Sendable ([StagingUploadFile]) async throws -> [PreSignedURL]
        let upload:
            @Sendable (PreSignedURL, URL, String) async throws -> Void
        let repair:
            @Sendable (String, String) async throws -> ScanImageCloudInspection
        let publishLibraryChanged: @Sendable () async -> Void

        static let live = Dependencies(
            shouldRun: {
                ProcessInfo.processInfo
                    .environment["XCTestConfigurationFilePath"] == nil
            },
            now: { Date() },
            fileExists: { url in
                FileManager.default.fileExists(atPath: url.path)
            },
            isVerifiedRecovery: { sourceURL, localURL in
                LocalScanMediaRecoveryResolver.existingLocalImageURL(
                    for: sourceURL,
                    allowTimestampFallback: false
                )?.standardizedFileURL == localURL.standardizedFileURL
            },
            fileSizeBytes: { url in
                guard let attributes = try? FileManager.default
                    .attributesOfItem(atPath: url.path) else {
                    return nil
                }
                return (attributes[.size] as? NSNumber)?.intValue
            },
            makeUUID: { UUID() },
            inspect: { sourceURL in
                try await MerianNetworkClient.shared
                    .inspectScanImageCloudStatus(sourceUrl: sourceURL)
            },
            generateUploadURLs: { files in
                try await MerianNetworkClient.shared.generateUploadURLs(
                    uploadFiles: files
                )
            },
            upload: { uploadURL, fileURL, contentType in
                try await MerianNetworkClient.shared.uploadToR2(
                    uploadURL: uploadURL,
                    fileURL: fileURL,
                    contentType: contentType
                )
            },
            repair: { sourceURL, objectKey in
                try await MerianNetworkClient.shared
                    .repairScanImageCloudReference(
                        sourceUrl: sourceURL,
                        restoredObjectKey: objectKey
                    )
            },
            publishLibraryChanged: {
                await MainActor.run {
                    AppDIContainer.shared.appEventPublisher.send(
                        .scanLibraryChanged
                    )
                }
            }
        )
    }

    static let shared = CloudScanImageRepairActor()

    private var pending: [CloudScanImageRepairCandidate] = []
    private var queuedOrInFlightSourceURLs: Set<String> = []
    private var completedSourceURLs: Set<String> = []
    private var processingTask: Task<Void, Never>?
    private var serviceUnavailableUntil: Date?
    private let dependencies: Dependencies
    private let retryDelay: TimeInterval

    init(
        dependencies: Dependencies = .live,
        retryDelay: TimeInterval = 15 * 60
    ) {
        self.dependencies = dependencies
        self.retryDelay = retryDelay
    }

    func enqueue(sourceUrl: URL, localUrl: URL) {
        guard dependencies.shouldRun(),
              let candidate = candidate(
                  sourceURL: sourceUrl,
                  localURL: localUrl
              ),
              !completedSourceURLs.contains(candidate.sourceURL),
              !queuedOrInFlightSourceURLs.contains(candidate.sourceURL),
              serviceUnavailableUntil.map({
                  $0 <= dependencies.now()
              }) ?? true else {
            return
        }

        pending.append(candidate)
        queuedOrInFlightSourceURLs.insert(candidate.sourceURL)
        guard processingTask == nil else { return }

        processingTask = Task(priority: .utility) {
            await self.drainQueue()
        }
    }

    func waitUntilIdle() async {
        await processingTask?.value
    }

    private func drainQueue() async {
        while !pending.isEmpty {
            if let serviceUnavailableUntil,
               serviceUnavailableUntil > dependencies.now() {
                pending.removeAll()
                queuedOrInFlightSourceURLs.removeAll()
                break
            }

            let candidate = pending.removeFirst()

            do {
                if try await repairIfMissing(candidate) {
                    completedSourceURLs.insert(candidate.sourceURL)
                }
                queuedOrInFlightSourceURLs.remove(candidate.sourceURL)
            } catch {
                serviceUnavailableUntil = dependencies.now()
                    .addingTimeInterval(retryDelay)
                pending.removeAll()
                queuedOrInFlightSourceURLs.removeAll()
                MerianLog.network.error(
                    "Cloud scan image repair paused after a failed request; retrying later."
                )
            }
        }

        processingTask = nil
    }

    private func repairIfMissing(
        _ candidate: CloudScanImageRepairCandidate
    ) async throws -> Bool {
        guard isVerifiedRecovery(candidate) else { return false }
        let inspection = try await dependencies.inspect(candidate.sourceURL)
        guard inspection.status == .missing else { return true }
        guard isVerifiedRecovery(candidate) else { return false }

        let sizeBytes = dependencies.fileSizeBytes(candidate.localURL) ?? 0
        guard sizeBytes > 0,
              sizeBytes <= MerianConfig.stagedImagePayloadMaxBytes,
              let contentType = Self.contentType(for: candidate.localURL) else {
            return false
        }

        let fileExtension = candidate.localURL.pathExtension.lowercased()
        let uploadFile = StagingUploadFile(
            fileName:
                "repair_\(dependencies.makeUUID().uuidString.lowercased()).\(fileExtension)",
            mediaKind: .image,
            contentType: contentType,
            sizeBytes: sizeBytes
        )
        let uploadURLs = try await dependencies.generateUploadURLs(
            [uploadFile]
        )
        guard let uploadURL = uploadURLs.first, uploadURLs.count == 1 else {
            throw MerianError.invalidResponse
        }

        guard isVerifiedRecovery(candidate) else { return false }
        try await dependencies.upload(
            uploadURL,
            candidate.localURL,
            contentType
        )
        guard isVerifiedRecovery(candidate) else { return false }
        let result = try await dependencies.repair(
            candidate.sourceURL,
            uploadURL.objectKey
        )
        guard result.status == .repaired || result.status == .healthy else {
            throw MerianError.invalidResponse
        }

        guard result.status == .repaired else { return true }

        MerianLog.network.info(
            "Cloud scan image repair restored \(result.updatedScanCount, privacy: .public) scan record(s) and \(result.updatedPostMediaCount, privacy: .public) Explore media record(s)."
        )
        await dependencies.publishLibraryChanged()
        return true
    }

    private func isVerifiedRecovery(_ candidate: CloudScanImageRepairCandidate) -> Bool {
        guard let sourceURL = URL(string: candidate.sourceURL) else { return false }
        return dependencies.isVerifiedRecovery(sourceURL, candidate.localURL)
    }

    private func candidate(
        sourceURL: URL,
        localURL: URL
    ) -> CloudScanImageRepairCandidate? {
        guard let canonicalSourceURL = LocalScanMediaRecoveryResolver
            .canonicalRecoverySourceURL(for: sourceURL),
              localURL.isFileURL,
              dependencies.fileExists(localURL),
              dependencies.isVerifiedRecovery(canonicalSourceURL, localURL),
              Self.contentType(for: localURL) != nil else {
            return nil
        }

        return CloudScanImageRepairCandidate(
            sourceURL: canonicalSourceURL.absoluteString,
            localURL: localURL
        )
    }

    private static func contentType(for fileURL: URL) -> String? {
        switch fileURL.pathExtension.lowercased() {
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
