import Foundation
import os

enum ShareImportLog {
    static let logger = Logger(subsystem: "com.merian.app", category: "ShareImport")
}

enum ShareImportReceiptStatus: String, Codable, Sendable {
    case queued
    case completed
    case failed
}

struct ShareImportReceipt: Codable, Equatable, Identifiable, Sendable {
    var id: String { scanId }
    let scanId: String
    let createdAt: Date
    var status: ShareImportReceiptStatus
    var localImageFilename: String?
    var imageContentType: String?
    var capturedAt: String?
    var gpsLatitude: Double?
    var gpsLongitude: Double?
    var gpsElevation: Double?

    init(
        scanId: String,
        createdAt: Date,
        status: ShareImportReceiptStatus,
        localImageFilename: String? = nil,
        imageContentType: String? = nil,
        capturedAt: String? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil,
        gpsElevation: Double? = nil
    ) {
        self.scanId = scanId
        self.createdAt = createdAt
        self.status = status
        self.localImageFilename = localImageFilename
        self.imageContentType = imageContentType
        self.capturedAt = capturedAt
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.gpsElevation = gpsElevation
    }
}

struct ShareImportReceiptSnapshot: Codable, Equatable, Sendable {
    var receipts: [ShareImportReceipt]

    static let empty = ShareImportReceiptSnapshot(receipts: [])
}

enum ShareImportReceiptStore {
    static let imageDirectoryName = "ShareImportImages"

    static func appGroupRootURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: ShareImportSharedConstants.appGroupIdentifier)
    }

    static func receiptsURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(ShareImportSharedConstants.receiptsFilename)
    }

    static func imageDirectoryURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(imageDirectoryName, isDirectory: true)
    }

    static func localImageURL(for receipt: ShareImportReceipt, rootURL: URL) -> URL? {
        guard let filename = receipt.localImageFilename, !filename.isEmpty else { return nil }
        return imageDirectoryURL(rootURL: rootURL).appendingPathComponent(filename)
    }

    static func writeLocalImage(
        data: Data,
        scanId: String,
        fileExtension: String,
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) -> String? {
        guard let rootURL = rootURL ?? appGroupRootURL(fileManager: fileManager) else {
            ShareImportLog.logger.error("ShareImportReceiptStore.writeLocalImage: missing app group root for scanId=\(scanId, privacy: .public)")
            return nil
        }
        let safeExtension = ShareImportImagePreparer.sanitizedFileName(fileExtension).isEmpty
            ? "img"
            : ShareImportImagePreparer.sanitizedFileName(fileExtension)
        let filename = ShareImportImagePreparer.sanitizedFileName("\(scanId)_local.\(safeExtension)")
        let imageDirectory = imageDirectoryURL(rootURL: rootURL)
        let imageURL = imageDirectory.appendingPathComponent(filename)

        do {
            try fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
            try data.write(to: imageURL, options: [.atomic])
            ShareImportLog.logger.debug("ShareImportReceiptStore.writeLocalImage: wrote scanId=\(scanId, privacy: .public) filename=\(filename, privacy: .public) bytes=\(data.count, privacy: .public)")
            return filename
        } catch {
            ShareImportLog.logger.error("ShareImportReceiptStore.writeLocalImage: failed scanId=\(scanId, privacy: .public) path=\(imageURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func load(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) -> ShareImportReceiptSnapshot {
        guard let rootURL = rootURL ?? appGroupRootURL(fileManager: fileManager) else {
            ShareImportLog.logger.error("ShareImportReceiptStore.load: missing app group root")
            return .empty
        }

        let url = receiptsURL(rootURL: rootURL)
        guard fileManager.fileExists(atPath: url.path) else {
            ShareImportLog.logger.debug("ShareImportReceiptStore.load: no receipt file at \(url.path, privacy: .public)")
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(ShareImportReceiptSnapshot.self, from: data)
            ShareImportLog.logger.debug("ShareImportReceiptStore.load: loaded receipts=\(snapshot.receipts.count, privacy: .public) bytes=\(data.count, privacy: .public)")
            return snapshot
        } catch {
            ShareImportLog.logger.error("ShareImportReceiptStore.load: failed url=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    static func write(
        _ snapshot: ShareImportReceiptSnapshot,
        fileManager: FileManager = .default,
        rootURL: URL
    ) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: receiptsURL(rootURL: rootURL), options: [.atomic])
        ShareImportLog.logger.debug("ShareImportReceiptStore.write: wrote receipts=\(snapshot.receipts.count, privacy: .public) bytes=\(data.count, privacy: .public)")
    }

    @discardableResult
    static func upsert(
        _ receipt: ShareImportReceipt,
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) -> Bool {
        guard let rootURL = rootURL ?? appGroupRootURL(fileManager: fileManager) else {
            ShareImportLog.logger.error("ShareImportReceiptStore.upsert: missing app group root for scanId=\(receipt.scanId, privacy: .public)")
            return false
        }
        var snapshot = load(fileManager: fileManager, rootURL: rootURL)
        snapshot.receipts.removeAll { $0.scanId == receipt.scanId }
        snapshot.receipts.append(receipt)
        do {
            try write(snapshot, fileManager: fileManager, rootURL: rootURL)
            ShareImportLog.logger.debug("ShareImportReceiptStore.upsert: queued receipt scanId=\(receipt.scanId, privacy: .public) hasImage=\((receipt.localImageFilename != nil), privacy: .public)")
            return true
        } catch {
            ShareImportLog.logger.error("ShareImportReceiptStore.upsert: failed scanId=\(receipt.scanId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func containsQueuedReceipt(
        scanId: String,
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) -> Bool {
        let snapshot = load(fileManager: fileManager, rootURL: rootURL)
        let found = snapshot.receipts.contains { receipt in
            receipt.scanId == scanId && receipt.status == .queued
        }
        ShareImportLog.logger.debug(
            "ShareImportReceiptStore.containsQueuedReceipt: scanId=\(scanId, privacy: .public) found=\(found, privacy: .public) receipts=\(snapshot.receipts.count, privacy: .public)"
        )
        return found
    }

    static func remove(
        scanIds: Set<String>,
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        guard !scanIds.isEmpty else { return }
        guard let rootURL = rootURL ?? appGroupRootURL(fileManager: fileManager) else {
            ShareImportLog.logger.error("ShareImportReceiptStore.remove: missing app group root scanIds=\(scanIds.joined(separator: ","), privacy: .public)")
            return
        }
        var snapshot = load(fileManager: fileManager, rootURL: rootURL)
        let removedReceipts = snapshot.receipts.filter { scanIds.contains($0.scanId) }
        snapshot.receipts.removeAll { scanIds.contains($0.scanId) }
        do {
            try write(snapshot, fileManager: fileManager, rootURL: rootURL)
            ShareImportLog.logger.debug("ShareImportReceiptStore.remove: removed receipts=\(removedReceipts.count, privacy: .public) scanIds=\(scanIds.joined(separator: ","), privacy: .public)")
        } catch {
            ShareImportLog.logger.error("ShareImportReceiptStore.remove: failed scanIds=\(scanIds.joined(separator: ","), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }

        for receipt in removedReceipts {
            guard let imageURL = localImageURL(for: receipt, rootURL: rootURL) else { continue }
            do {
                try fileManager.removeItem(at: imageURL)
                ShareImportLog.logger.debug("ShareImportReceiptStore.remove: deleted local image scanId=\(receipt.scanId, privacy: .public) path=\(imageURL.path, privacy: .public)")
            } catch {
                ShareImportLog.logger.error("ShareImportReceiptStore.remove: failed deleting local image scanId=\(receipt.scanId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
