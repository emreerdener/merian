import CryptoKit
import Darwin
import Foundation

/// Original-byte I/O over a descriptor scope minted by the locked file owner.
/// This leaf cannot open a root, extend the scope, or mint retirement proofs.
struct PhotoPreparationOriginalFiles {
    private let access: SharedMediaInboxDestinationAccess
    init(access: SharedMediaInboxDestinationAccess) { self.access = access }
    #if DEBUG
    var writeFault: (@Sendable (Int) throws -> Void)?
    #endif

    func write(_ data: Data, intent: PhotoPreparationIntent, contentType: String) throws -> PhotoPreparationFile {
        try access.perform { directoryFD, namespaceFD in
            guard directoryFD >= 0 else { throw PhotoPreparationFailure.missingMedia }
            let name = access.name
            let partial = name + ".partial"
            let fd = openat(directoryFD, partial, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw PhotoPreparationFailure.cleanupPending }
            defer { Darwin.close(fd) }
            // The file is private and is never registered with the legacy FileIO owner.
            var hash = SHA256()
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    try Task.checkCancellation()
                    let length = min(64 * 1024, bytes.count - offset)
                    guard let address = bytes.baseAddress?.advanced(by: offset) else { throw PhotoPreparationFailure.invalidMedia }
                    var written = 0
                    while written < length {
                        let amount = Darwin.write(fd, address.advanced(by: written), length - written)
                        if amount < 0 && errno == EINTR { continue }
                        guard amount > 0 else { throw PhotoPreparationFailure.storageLimit }
                        written += amount
                    }
                    hash.update(bufferPointer: UnsafeRawBufferPointer(start: address, count: length))
                    offset += length
                    #if DEBUG
                    try writeFault?(offset)
                    #endif
                }
            }
            guard fsync(fd) == 0 else { throw PhotoPreparationFailure.storageLimit }
            // Exclusive rename cannot replace an existing committed file.
            guard renameatx_np(directoryFD, partial, directoryFD, name, UInt32(RENAME_EXCL)) == 0,
                  fsync(directoryFD) == 0, fsync(namespaceFD) == 0 else { throw PhotoPreparationFailure.cleanupPending }
            return PhotoPreparationFile(assetID: intent.assetID, generation: intent.assetGeneration,
                token: intent.fileToken, byteCount: Int64(data.count),
                sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), contentType: contentType)
        }
    }

    func verifiedIdentity(_ file: PhotoPreparationFile) throws -> String {
        try access.perform { directoryFD, _ in
            guard directoryFD >= 0 else { throw PhotoPreparationFailure.missingMedia }
            let name = access.name
            let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { throw PhotoPreparationFailure.missingMedia }
            defer { Darwin.close(fd) }
            var before = stat(), after = stat(), named = stat()
            guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
                  before.st_nlink == 1, before.st_size == file.byteCount else { throw PhotoPreparationFailure.inconsistentOwnership }
            var hash = SHA256(), total: Int64 = 0
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                try Task.checkCancellation()
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count >= 0 else { throw PhotoPreparationFailure.unavailable }
                if count == 0 { break }
                total = try PhotoPreparationPolicy.add([total, Int64(count)])
                guard total <= file.byteCount else { throw PhotoPreparationFailure.inconsistentOwnership }
                buffer.withUnsafeBytes { hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<count])) }
            }
            guard fstat(fd, &after) == 0,
                  fstatat(directoryFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  before.st_dev == after.st_dev, before.st_ino == after.st_ino,
                  before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                  before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
                  before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
                  after.st_nlink == 1,
                  named.st_ino == after.st_ino, named.st_dev == after.st_dev,
                  total == file.byteCount,
                  hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
            return "\(after.st_dev):\(after.st_ino):\(after.st_size):\(after.st_mtimespec.tv_sec):\(after.st_mtimespec.tv_nsec):\(after.st_ctimespec.tv_sec):\(after.st_ctimespec.tv_nsec)"
        }
    }

    func read(_ file: PhotoPreparationFile) throws -> Data {
        try access.perform { directoryFD, _ in
            guard directoryFD >= 0 else { throw PhotoPreparationFailure.missingMedia }
            let name = access.name
            let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { throw PhotoPreparationFailure.missingMedia }
            defer { Darwin.close(fd) }
            let data = try PhotoPreparationLockedFiles.boundedRead(fd: fd, maximumBytes: file.byteCount)
            guard data.count == file.byteCount,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
            return data
        }
    }
}
