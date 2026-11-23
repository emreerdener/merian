import Foundation

/// Bounded, canonical retirement evidence. These values describe exact leaves;
/// they never grant filesystem or database access. The cleanup-only owner must
/// independently hold the accepted outer scope, store fence and root locks.
enum SharedMediaNativeErasureManifest {
    static let pageSize = 128
    static let maximumPageBytes = 128 * 1024

    enum Namespace: String, Codable, Sendable {
        case authority, photo, inbox, capture, control
    }
    enum Kind: String, Codable, Sendable { case absent, file, directory }

    struct Entry: Codable, Equatable, Sendable {
        let namespace: Namespace
        let token: String
        let kind: Kind
        let identity: String?

        var key: String { namespace.rawValue + "/" + token }

        func validate(ownerID: UUID) throws {
            guard !token.isEmpty, token.utf8.count <= 256 else { throw SharedMediaStorageFailure.invalid }
            let components = token.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            switch namespace {
            case .authority:
                guard token == ".", kind != .file else { throw SharedMediaStorageFailure.invalid }
            case .control:
                let names = Set([SharedMediaNativeBootstrapCodec.intentName, SharedMediaNativeBootstrapCodec.finalName]
                    + SharedMediaNativeBootstrapCodec.progressNames)
                    .union(SharedMediaCaptureRootJournal.names.subtracting([SharedMediaCaptureRootJournal.rootName]))
                guard names.contains(token), kind != .directory else { throw SharedMediaStorageFailure.invalid }
            case .photo:
                if token == "." || token == "PhotoPreparation" {
                    guard kind != .file else { throw SharedMediaStorageFailure.invalid }
                } else {
                    guard (2...4).contains(components.count), components[0] == "PhotoPreparation",
                          components[1] == ownerID.uuidString.lowercased(),
                          components.dropFirst().dropLast().allSatisfy(canonicalUUID) else { throw SharedMediaStorageFailure.invalid }
                    let last = components.last!
                    if components.count < 4 {
                        guard canonicalUUID(last), kind != .file else { throw SharedMediaStorageFailure.invalid }
                    } else {
                        guard canonicalUUID(last.hasSuffix(".partial") ? String(last.dropLast(8)) : last),
                              kind != .directory else { throw SharedMediaStorageFailure.invalid }
                    }
                }
            case .inbox, .capture:
                let child = namespace == .inbox ? "InboxSources" : SharedMediaCaptureRootJournal.childName
                if token == "." || token == child {
                    guard kind != .file else { throw SharedMediaStorageFailure.invalid }
                } else {
                    guard components.count == 2, components[0] == child, kind != .directory else { throw SharedMediaStorageFailure.invalid }
                    let last = components[1]
                    guard canonicalUUID(last.hasSuffix(".partial") ? String(last.dropLast(8)) : last) else { throw SharedMediaStorageFailure.invalid }
                }
            }
            switch kind {
            case .absent:
                guard identity == nil else { throw SharedMediaStorageFailure.invalid }
            case .directory:
                guard let identity, SharedMediaNativeBootstrapCodec.identity(identity) else { throw SharedMediaStorageFailure.invalid }
            case .file:
                guard let identity, Self.fileIdentity(identity) else { throw SharedMediaStorageFailure.invalid }
            }
        }

        private func canonicalUUID(_ text: String) -> Bool {
            UUID(uuidString: text)?.uuidString.lowercased() == text
        }

        /// Same seven-field descriptor used by native photo/inbox/Capture
        /// originals: device, inode, bytes, mtime seconds/nanos, ctime seconds/nanos.
        private static func fileIdentity(_ text: String) -> Bool {
            (try? SharedMediaNativeFileIdentity(text)) != nil
        }
    }

    struct Page: Codable, Equatable, Sendable {
        let version: Int
        let operationID: UUID
        let profileSHA256: String
        let ordinal: Int64
        let previousSHA256: String?
        let entries: [Entry]

        func encoded(profile: SharedMediaNativeAppProfile) throws -> Data {
            try validate(profile: profile)
            return try SharedMediaAcquisitionEncoding.encode(self, maximum: maximumPageBytes)
        }

        static func decode(_ bytes: Data, profile: SharedMediaNativeAppProfile) throws -> Self {
            let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: maximumPageBytes)
            try value.validate(profile: profile)
            guard try value.encoded(profile: profile) == bytes else { throw SharedMediaStorageFailure.conflict }
            return value
        }

        private func validate(profile: SharedMediaNativeAppProfile) throws {
            guard version == 1, ordinal >= 0, !entries.isEmpty, entries.count <= pageSize,
                  ![profile.ownerID, profile.inventoryID, profile.generation].contains(operationID),
                  profileSHA256 == (try SharedMediaAcquisitionEncoding.digest(profile.binding)),
                  ordinal == 0 ? previousSHA256 == nil : previousSHA256.map(SharedMediaAcquisitionEncoding.isHash) == true else {
                throw SharedMediaStorageFailure.invalid
            }
            for entry in entries { try entry.validate(ownerID: profile.ownerID) }
            let keys = entries.map(\.key)
            guard keys == keys.sorted(), Set(keys).count == keys.count else { throw SharedMediaStorageFailure.conflict }
        }
    }

    /// A streaming verifier retains one page, a digest and the last key. Total
    /// library size cannot force an unbounded in-memory pathname list.
    struct Chain {
        let operationID: UUID
        let profile: SharedMediaNativeAppProfile
        private(set) var pageCount: Int64 = 0
        private(set) var entryCount: Int64 = 0
        private(set) var digest: String?
        private var lastKey: String?

        init(operationID: UUID, profile: SharedMediaNativeAppProfile) {
            self.operationID = operationID; self.profile = profile
        }

        mutating func consume(_ bytes: Data) throws -> [Entry] {
            let page = try Page.decode(bytes, profile: profile)
            guard page.operationID == operationID, page.ordinal == pageCount,
                  page.previousSHA256 == digest,
                  lastKey.map({ $0 < page.entries[0].key }) ?? true else { throw SharedMediaStorageFailure.conflict }
            let nextPage = try SharedMediaStoragePolicy.add(pageCount, 1)
            let nextCount = try SharedMediaStoragePolicy.add(entryCount, Int64(page.entries.count))
            pageCount = nextPage; entryCount = nextCount
            digest = SharedMediaAcquisitionEncoding.digest(bytes); lastKey = page.entries.last?.key
            return page.entries
        }

        func requireComplete(pages: Int64, entries: Int64, lastSHA256: String) throws {
            guard pages > 0, entries > 0, pageCount == pages, entryCount == entries,
                  digest == lastSHA256 else { throw SharedMediaStorageFailure.conflict }
        }
    }
}
