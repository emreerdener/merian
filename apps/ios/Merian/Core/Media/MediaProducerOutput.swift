import Darwin
import Foundation

/// Owns one path-only encoder invocation in an exclusively created private directory.
/// Only that encoder receives outputURL. Export APIs cannot expose their file descriptor
/// before completion: until the first pin, provenance relies on this exclusive-writer
/// namespace, not on a random filename proving inode identity. After pinning, replacement
/// never inherits authority. Callers must join the encoder before settlement or discard.
actor MediaProducerOutput {
    struct FileOperations: Sendable {
        var synchronize: @Sendable (Int32) -> Int32 = { fsync($0) }
        var unlink: @Sendable (Int32, String, Int32) -> Int32 = { unlinkat($0, $1, $2) }
    }
    nonisolated let outputURL: URL
    private let root: LegacyMediaDirectory
    private let directory: LegacyMediaDirectory
    private let directoryName: String
    private let name: String
    private var descriptor: Int32 = -1
    private var receipt: LegacyMediaFileRetirement?
    private var retired = false
    private var directoryRemoved = false
    private let io: FileOperations
    private struct Destination {
        let root: LegacyMediaDirectory
        let name: String
        let fd: Int32
    }
    private var destination: Destination?
    private var destinationReceipt: LegacyMediaFileRetirement?

    init(fileExtension: String, io: FileOperations = .init()) throws {
        guard ["wav", "mp4"].contains(fileExtension),
              let root = LegacyMediaDirectory(FileManager.default.temporaryDirectory.resolvingSymlinksInPath()) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let directoryName = "capture-producer-\(UUID().uuidString.lowercased())"
        guard mkdirat(root.fd, directoryName, 0o700) == 0 else { throw CocoaError(.fileWriteUnknown) }
        let directoryURL = root.url.appendingPathComponent(directoryName)
        guard let directory = LegacyMediaDirectory(directoryURL), root.isCurrent() else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.root = root; self.directory = directory; self.directoryName = directoryName
        self.io = io
        name = "output.\(fileExtension)"
        outputURL = directoryURL.appendingPathComponent(name)
    }

    /// Pin immediately after a writer creates its file, before it starts streaming.
    /// This stores inode identity; the final length/timestamps are frozen only at exit.
    func pinCreatedOutput() throws {
        guard !retired, root.isCurrent(), directory.isCurrent() else { throw CocoaError(.fileReadUnknown) }
        if descriptor < 0 {
            descriptor = openat(directory.fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard descriptor >= 0, directory.matches(name, descriptor: descriptor) else {
            throw CocoaError(.fileReadUnknown)
        }
    }

    /// Bounded exclusive copy. The destination receipt is acquired from the descriptor
    /// used to create/write it, never by adopting a later occupant of that path.
    func publish(to destination: URL, suffix: String, maximumBytes: Int) throws -> (URL, LegacyMediaFileRetirement) {
        try Task.checkCancellation()
        guard self.destination == nil, !retired else { throw CocoaError(.fileWriteUnknown) }
        try freezeAfterExit()
        guard let receipt, let target = LegacyMediaDirectory(destination.resolvingSymlinksInPath()),
              maximumBytes > 0 else { throw CocoaError(.fileWriteUnknown) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_size > 0, before.st_size <= maximumBytes,
              directory.matches(name, descriptor: descriptor, snapshot: before),
              !suffix.contains("/"), !suffix.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let leaf = "\(UUID().uuidString.lowercased())-\(suffix)"
        let output = openat(target.fd, leaf, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw CocoaError(.fileWriteUnknown) }
        self.destination = .init(root: target, name: leaf, fd: output)
        // Freeze partial output before this actor can suspend or its caller exits.
        // A failed first capture is held; cleanup must not acquire a later snapshot.
        defer {
            if self.destination != nil, self.destinationReceipt == nil {
                self.destinationReceipt = LegacyMediaFileRetirement(directory: target, name: leaf, descriptor: output)
            }
        }
        var offset: off_t = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while offset < before.st_size {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes {
                pread(descriptor, $0.baseAddress, min($0.count, Int(before.st_size - offset)), offset)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw CocoaError(.fileReadUnknown) }
            var written = 0
            while written < count {
                let bytes = buffer.withUnsafeBytes { Darwin.write(output, $0.baseAddress!.advanced(by: written), count - written) }
                if bytes < 0 && errno == EINTR { continue }
                guard bytes > 0 else { throw CocoaError(.fileWriteUnknown) }
                written += bytes
            }
            offset += off_t(count)
        }
        guard root.isCurrent(), directory.matches(name, descriptor: descriptor, snapshot: before),
              io.synchronize(output) == 0, io.synchronize(target.fd) == 0,
              let destinationReceipt = LegacyMediaFileRetirement(directory: target, name: leaf, descriptor: output) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.destinationReceipt = destinationReceipt
        try Task.checkCancellation()
        guard receipt.retire(), removeEmptyDirectory() else { throw CocoaError(.fileWriteUnknown) }
        retired = true
        Darwin.close(output)
        self.destination = nil
        return (target.url.appendingPathComponent(leaf), destinationReceipt)
    }

    func discardAfterExit() throws {
        guard !retired else { return }
        try discardDestination()
        if directoryRemoved {
            guard removeEmptyDirectory() else { throw CocoaError(.fileWriteUnknown) }
            retired = true
            return
        }
        guard root.isCurrent(), directory.isCurrent() else { throw CocoaError(.fileWriteUnknown) }
        var value = stat()
        if descriptor < 0 && fstatat(directory.fd, name, &value, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT {
            guard removeEmptyDirectory() else { throw CocoaError(.fileWriteUnknown) }
        } else {
            if receipt == nil { try freezeAfterExit() }
            guard receipt?.retire() == true, removeEmptyDirectory() else { throw CocoaError(.fileWriteUnknown) }
        }
        retired = true
    }

    private func freezeAfterExit() throws {
        if receipt != nil { return }
        try pinCreatedOutput()
        guard let value = LegacyMediaFileRetirement(directory: directory, name: name, descriptor: descriptor) else {
            throw CocoaError(.fileReadUnknown)
        }
        receipt = value
    }

    private func removeEmptyDirectory() -> Bool {
        guard root.isCurrent() else { return false }
        if directoryRemoved {
            var value = stat()
            guard fstatat(root.fd, directoryName, &value, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT,
                  io.synchronize(root.fd) == 0, root.isCurrent() else { return false }
            return fstatat(root.fd, directoryName, &value, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT
        }
        guard directory.isCurrent() else { return false }
        var held = stat(), named = stat()
        guard fstat(directory.fd, &held) == 0,
              fstatat(root.fd, directoryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_dev == named.st_dev, held.st_ino == named.st_ino else { return false }
        guard io.unlink(root.fd, directoryName, AT_REMOVEDIR) == 0 else { return false }
        directoryRemoved = true
        return removeEmptyDirectory()
    }

    private func discardDestination() throws {
        guard let destination else { return }
        guard let destinationReceipt,
              destinationReceipt.remove(synchronize: io.synchronize) else { throw CocoaError(.fileWriteUnknown) }
        Darwin.close(destination.fd)
        self.destination = nil
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
        if let destination { Darwin.close(destination.fd) }
    }
}
