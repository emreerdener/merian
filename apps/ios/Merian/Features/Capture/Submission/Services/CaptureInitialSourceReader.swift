import Darwin
import Foundation

/// Reads a producer-owned file before its custody is acknowledged. The caller
/// holds the recording/import producer and registers account work for the full
/// read-and-retain operation; a URL alone grants neither of those lifetimes.
actor CaptureInitialSourceReader {
    func read(_ url: URL, maximumBytes: Int64) throws -> Data {
        try Task.checkCancellation()
        guard maximumBytes > 0, maximumBytes <= PhotoPreparationPolicy.original else {
            throw SharedMediaStorageFailure.capacity
        }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
        defer { Darwin.close(fd) }
        var before = stat(), after = stat(), named = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1 else {
            throw SharedMediaStorageFailure.invalid
        }
        let bytes = try PhotoPreparationLockedFiles.boundedRead(fd: fd, maximumBytes: maximumBytes)
        try Task.checkCancellation()
        guard fstat(fd, &after) == 0, lstat(url.path, &named) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              after.st_dev == named.st_dev, after.st_ino == named.st_ino,
              after.st_size == named.st_size, after.st_nlink == 1 else {
            throw SharedMediaStorageFailure.stale
        }
        return bytes
    }
}
