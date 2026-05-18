import Foundation

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
}

struct ShareImportReceiptSnapshot: Codable, Equatable, Sendable {
    var receipts: [ShareImportReceipt]

    static let empty = ShareImportReceiptSnapshot(receipts: [])
}

enum ShareImportReceiptStore {
    static func appGroupRootURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: ShareImportSharedConstants.appGroupIdentifier)
    }

    static func receiptsURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(ShareImportSharedConstants.receiptsFilename)
    }

    static func load(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) -> ShareImportReceiptSnapshot {
        guard let rootURL = rootURL ?? appGroupRootURL(fileManager: fileManager),
              let data = try? Data(contentsOf: receiptsURL(rootURL: rootURL)),
              let snapshot = try? JSONDecoder().decode(ShareImportReceiptSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func write(
        _ snapshot: ShareImportReceiptSnapshot,
        fileManager: FileManager = .default,
        rootURL: URL
    ) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: receiptsURL(rootURL: rootURL), options: [.atomic])
    }

    static func upsert(
        _ receipt: ShareImportReceipt,
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        guard let rootURL = rootURL ?? appGroupRootURL(fileManager: fileManager) else { return }
        var snapshot = load(fileManager: fileManager, rootURL: rootURL)
        snapshot.receipts.removeAll { $0.scanId == receipt.scanId }
        snapshot.receipts.append(receipt)
        try? write(snapshot, fileManager: fileManager, rootURL: rootURL)
    }

    static func remove(
        scanIds: Set<String>,
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        guard !scanIds.isEmpty,
              let rootURL = rootURL ?? appGroupRootURL(fileManager: fileManager) else { return }
        var snapshot = load(fileManager: fileManager, rootURL: rootURL)
        snapshot.receipts.removeAll { scanIds.contains($0.scanId) }
        try? write(snapshot, fileManager: fileManager, rootURL: rootURL)
    }
}
