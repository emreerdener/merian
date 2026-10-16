import CoreTransferable
import Darwin
import Foundation
import UniformTypeIdentifiers

/// Exact delivered representation, read before the provider callback releases it.
/// The caller must already own a durable acquisition reservation.
struct PhotoOriginalPickerTransfer: Transferable, Sendable {
    let bytes: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let fd = Darwin.open(received.file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { throw PhotoPreparationFailure.missingMedia }
            defer { Darwin.close(fd) }
            return PhotoOriginalPickerTransfer(bytes: try PhotoPreparationLockedFiles.boundedRead(
                fd: fd, maximumBytes: PhotoPreparationPolicy.original
            ))
        }
    }

    static func readInbox(_ url: URL) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw PhotoPreparationFailure.missingMedia }
        defer { Darwin.close(fd) }
        return try PhotoPreparationLockedFiles.boundedRead(fd: fd, maximumBytes: PhotoPreparationPolicy.original)
    }
    static func validateInboxSize(_ url: URL) throws -> Int64 {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw PhotoPreparationFailure.missingMedia }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_size > 0, info.st_size <= PhotoPreparationPolicy.original else {
            throw PhotoPreparationFailure.sizeLimit
        }
        return info.st_size
    }

    static func confirmRetained(_ url: URL) throws {
        _ = try validateInboxSize(url)
        let parent = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw PhotoPreparationFailure.cleanupPending }
        defer { Darwin.close(parent) }
        let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        let manifest = openat(parent, "pending-image-imports.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        defer { if fd >= 0 { Darwin.close(fd) }; if manifest >= 0 { Darwin.close(manifest) } }
        var info = stat()
        guard fd >= 0, manifest >= 0, fstat(manifest, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              fsync(fd) == 0, fsync(manifest) == 0, fsync(parent) == 0 else { throw PhotoPreparationFailure.cleanupPending }
    }

    static func confirmReleased(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        let fd = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw PhotoPreparationFailure.cleanupPending }
        defer { Darwin.close(fd) }
        var held = stat(), named = stat(), file = stat()
        guard fstat(fd, &held) == 0, lstat(parent.path, &named) == 0,
              held.st_dev == named.st_dev, held.st_ino == named.st_ino,
              fstatat(fd, url.lastPathComponent, &file, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT, fsync(fd) == 0 else { throw PhotoPreparationFailure.cleanupPending }
    }

}
