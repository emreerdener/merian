import Foundation

final class LocalScanMediaRecoveryRegistry: @unchecked Sendable {
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
        LocalScanMediaRecoveryResolver
            .canonicalRecoverySourceURL(for: url)?
            .absoluteString
    }
}
