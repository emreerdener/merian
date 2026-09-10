import Foundation

final class LocalScanMediaRecoveryRegistry: @unchecked Sendable {
    static let shared = LocalScanMediaRecoveryRegistry()

    private enum Evidence {
        case timestamp
        case strong
    }

    private struct Registration {
        let fileName: String
        let evidence: Evidence
        let timestampGroupID: UInt64?
    }

    private let lock = NSLock()
    private let revisions = LocalScanMediaRecoveryRevisions()
    private var registrationsByRemoteURL: [String: Registration] = [:]
    private var remoteURLsByFileName: [String: Set<String>] = [:]
    private var remoteURLsByTimestampGroup: [UInt64: Set<String>] = [:]
    private var nextTimestampGroupID: UInt64 = 0

    func fileName(for remoteURL: URL, allowTimestampFallback: Bool = true) -> String? {
        guard let key = canonicalKey(for: remoteURL) else { return nil }
        return lock.withLock {
            guard let registration = registrationsByRemoteURL[key],
                  allowTimestampFallback || registration.evidence == .strong else {
                return nil
            }
            return registration.fileName
        }
    }

    func cacheRevision(for remoteURLs: [URL]) -> UInt64 {
        revisions.revision(for: remoteURLs.compactMap(canonicalKey(for:)))
    }

    func changes(for remoteURLs: [URL]) -> AsyncStream<Void> {
        revisions.changes(for: remoteURLs.compactMap(canonicalKey(for:)))
    }

    @discardableResult
    func registerStrongMapping(
        remoteURL: URL,
        fileName: String
    ) -> Bool {
        guard let key = canonicalKey(for: remoteURL) else { return false }
        return lock.withLock {
            if let existing = registrationsByRemoteURL[key] {
                guard existing.evidence == .timestamp else {
                    return false
                }
                removeRegistrationOrTimestampGroup(
                    forKey: key,
                    registration: existing
                )
            }

            let existingRemoteURLs = remoteURLsByFileName[fileName] ?? []
            let timestampGroupIDs = Set(existingRemoteURLs.compactMap {
                registrationsByRemoteURL[$0]?.timestampGroupID
            })
            for timestampGroupID in timestampGroupIDs {
                removeTimestampGroup(timestampGroupID)
            }

            insertRegistration(
                forKey: key,
                fileName: fileName,
                evidence: .strong,
                timestampGroupID: nil
            )
            return true
        }
    }

    func registerTimestampMappings(
        remoteURLs: [URL],
        fileNames: [String]
    ) -> Bool {
        guard !remoteURLs.isEmpty,
              remoteURLs.count == fileNames.count else {
            return false
        }

        let keys = remoteURLs.compactMap { canonicalKey(for: $0) }
        guard keys.count == remoteURLs.count,
              Set(keys).count == keys.count,
              Set(fileNames).count == fileNames.count else {
            return false
        }

        return lock.withLock {
            guard keys.allSatisfy({
                registrationsByRemoteURL[$0] == nil
            }), fileNames.allSatisfy({
                remoteURLsByFileName[$0]?.isEmpty ?? true
            }) else {
                return false
            }

            let timestampGroupID = makeTimestampGroupID()
            for (key, fileName) in zip(keys, fileNames) {
                insertRegistration(
                    forKey: key,
                    fileName: fileName,
                    evidence: .timestamp,
                    timestampGroupID: timestampGroupID
                )
            }
            return true
        }
    }

    var registeredFileNames: Set<String> {
        lock.withLock {
            Set(registrationsByRemoteURL.values.map(\.fileName))
        }
    }

    func reset() {
        lock.withLock {
            registrationsByRemoteURL.removeAll()
            remoteURLsByFileName.removeAll()
            remoteURLsByTimestampGroup.removeAll()
            nextTimestampGroupID = 0
            revisions.reset()
        }
    }

    private func removeRegistrationOrTimestampGroup(
        forKey key: String,
        registration: Registration
    ) {
        if let timestampGroupID = registration.timestampGroupID {
            removeTimestampGroup(timestampGroupID)
        } else {
            removeRegistration(forKey: key, registration: registration)
        }
    }

    private func removeTimestampGroup(_ timestampGroupID: UInt64) {
        let keys = remoteURLsByTimestampGroup[timestampGroupID] ?? []
        for key in keys {
            guard let registration = registrationsByRemoteURL[key] else {
                continue
            }
            removeRegistration(forKey: key, registration: registration)
        }
    }

    private func removeRegistration(
        forKey key: String,
        registration: Registration
    ) {
        registrationsByRemoteURL.removeValue(forKey: key)
        revisions.invalidate(key)
        remoteURLsByFileName[registration.fileName]?.remove(key)
        if remoteURLsByFileName[registration.fileName]?.isEmpty == true {
            remoteURLsByFileName.removeValue(forKey: registration.fileName)
        }
        if let timestampGroupID = registration.timestampGroupID {
            remoteURLsByTimestampGroup[timestampGroupID]?.remove(key)
            if remoteURLsByTimestampGroup[timestampGroupID]?.isEmpty == true {
                remoteURLsByTimestampGroup.removeValue(
                    forKey: timestampGroupID
                )
            }
        }
    }

    private func insertRegistration(
        forKey key: String,
        fileName: String,
        evidence: Evidence,
        timestampGroupID: UInt64?
    ) {
        registrationsByRemoteURL[key] = Registration(
            fileName: fileName,
            evidence: evidence,
            timestampGroupID: timestampGroupID
        )
        revisions.invalidate(key)
        remoteURLsByFileName[fileName, default: []].insert(key)
        if let timestampGroupID {
            remoteURLsByTimestampGroup[timestampGroupID, default: []]
                .insert(key)
        }
    }

    private func makeTimestampGroupID() -> UInt64 {
        nextTimestampGroupID &+= 1
        return nextTimestampGroupID
    }

    private func canonicalKey(for url: URL) -> String? {
        LocalScanMediaRecoveryResolver
            .canonicalRecoverySourceURL(for: url)?
            .absoluteString
    }
}
