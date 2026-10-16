import Darwin
import Foundation
import os

/// Strictly isolated actor designed entirely to handle intense NVMe physical storage.
/// Bypasses the Main Actor AND the BackgroundDatabaseActor so that heavy 12 MP image reads
/// and massive file deletions never throttle the SQLite or UI threads.
public actor FileIOActor {
    
    public static let shared = FileIOActor(documents: .documentsDirectory,
        temporaryDirectory: FileManager.default.temporaryDirectory)

    struct CopyIO: Sendable {
        var write: @Sendable (Int32, UnsafeRawBufferPointer) -> Int
        var synchronize: @Sendable (Int32) -> Int32

        static let live = Self(
            write: { Darwin.write($0, $1.baseAddress, $1.count) },
            synchronize: { fsync($0) }
        )
    }

    private let copyIO: CopyIO
    private let documents: URL
    private let temporaryDirectory: URL

    init(documents: URL, temporaryDirectory: URL, copyIO: CopyIO = .live) {
        self.copyIO = copyIO
        self.documents = documents.resolvingSymlinksInPath().standardizedFileURL
        self.temporaryDirectory = temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
    }

    public func validPaths(from paths: [String]) -> [String] {
        paths.filter { path in
            if path.starts(with: "http") { return true }
            return withFile(at: path, bareRoots: [documents]) { _, _, _ in true } ?? false
        }
    }

    /// Writes multiple image buffers to the Document Directory concurrently.
    ///
    /// Launches each write in a `Task.detached` so all disk writes proceed in parallel on worker
    /// threads, bypassing `FileIOActor`'s serial executor. On a 3-frame scan this cuts wall-clock
    /// write time from `3 × write_time` to `max(write_times)`.
    ///
    /// - Returns: Filenames in the **same order as `imageDatas`**, omitting any that failed to write.
    public func writeTemporaryImages(imageDatas: [Data]) async -> [String] {
        guard !imageDatas.isEmpty else { return [] }
        let docs = documents

        // Launch all writes concurrently before awaiting any result.
        // Each task targets a unique UUID filename — no file contention.
        let tasks: [Task<(index: Int, filename: String?), Never>] = imageDatas.enumerated().map { (i, data) in
            let filename = i == 0
                ? "\(UUID().uuidString)_scan.webp"
                : "\(UUID().uuidString)_additional_\(i).webp"
            return Task.detached(priority: .userInitiated) {
                do {
                    try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
                    return (index: i, filename: filename)
                } catch {
                    MerianLog.data.error("FileIOActor: Failed writing buffer \(i, privacy: .public): \(error, privacy: .private)")
                    return (index: i, filename: nil)
                }
            }
        }

        // Collect results and restore original insertion order.
        var indexed: [(index: Int, filename: String)] = []
        for task in tasks {
            let result = await task.value
            if let filename = result.filename {
                indexed.append((index: result.index, filename: filename))
            }
        }
        return indexed.sorted { $0.index < $1.index }.map(\.filename)
    }
    
    /// Generic cleanup has no authority over private media-store namespaces.
    public func deleteImages(at filenames: [String]) {
        deleteFiles(at: filenames)
    }

    /// Bare names retain the historical Documents + temporary cleanup behavior.
    /// Absolute paths name exactly one flat file. Never recursively remove a directory.
    public func deleteFiles(at paths: [String]) {
        for path in paths {
            for root in path.hasPrefix("/") ? [documents] : [documents, temporaryDirectory] {
                _ = withFile(at: path, bareRoots: [root]) { directory, name, fd in
                    directory.remove(name, matching: fd)
                }
            }
        }
    }

    public func persistAudioFile(tempPath: String) -> String? {
        persistMediaFile(tempPath: tempPath, suffix: "audio", preferredExtension: "wav")
    }

    public func persistVideoFile(tempPath: String) -> String? {
        persistMediaFile(tempPath: tempPath, suffix: "video", preferredExtension: "mp4")
    }

    private func persistMediaFile(tempPath: String, suffix: String, preferredExtension: String) -> String? {
        withFile(at: tempPath, bareRoots: [documents, temporaryDirectory]) { source, name, sourceFD in
            if source.url.path == documents.path { return name }
            guard let destination = LegacyMediaDirectory(documents) else { return nil }
            let ext = URL(fileURLWithPath: name).pathExtension
            let filename = "\(UUID().uuidString)_\(suffix).\(ext.isEmpty ? preferredExtension : ext)"
            let output = openat(destination.fd, filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard output >= 0 else { return nil }
            defer { Darwin.close(output) }
            var complete = false
            defer {
                if !complete { _ = destination.remove(filename, matching: output) }
            }
            var initial = stat()
            guard fstat(sourceFD, &initial) == 0, initial.st_size >= 0 else { return nil }
            var remaining = initial.st_size
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while remaining > 0 {
                let count = buffer.withUnsafeMutableBytes {
                    Darwin.read(sourceFD, $0.baseAddress, min($0.count, Int(min(remaining, 64 * 1024))))
                }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return nil }
                var offset = 0
                while offset < count {
                    let written = buffer.withUnsafeBytes {
                        copyIO.write(output, UnsafeRawBufferPointer(rebasing: $0[offset..<count]))
                    }
                    if written < 0, errno == EINTR { continue }
                    guard written > 0 else { return nil }
                    offset += written
                }
                remaining -= off_t(count)
            }
            var final = stat()
            guard fstat(sourceFD, &final) == 0,
                  initial.st_size == final.st_size,
                  initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec,
                  initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec,
                  initial.st_ctimespec.tv_sec == final.st_ctimespec.tv_sec,
                  initial.st_ctimespec.tv_nsec == final.st_ctimespec.tv_nsec,
                  source.matches(name, descriptor: sourceFD),
                  destination.matches(filename, descriptor: output),
                  copyIO.synchronize(output) == 0, copyIO.synchronize(destination.fd) == 0 else { return nil }
            complete = true
            // Refusal before unlink retains the source. A later directory-sync
            // failure has uncertain deletion durability; the flushed destination
            // remains recoverable. This is not a reference-release receipt.
            _ = source.remove(name, matching: sourceFD, snapshot: initial, synchronize: copyIO.synchronize)
            return filename
        }
    }

    /// Preserve the historical Documents-only lookup for bare audio names.
    public func deleteAudioFiles(at filenames: [String]) {
        for path in filenames {
            _ = withFile(at: path, bareRoots: [documents]) { directory, name, fd in
                directory.remove(name, matching: fd)
            }
        }
    }

    private func withFile<T>(at path: String, bareRoots: [URL],
                             body: (LegacyMediaDirectory, String, Int32) -> T?) -> T? {
        guard !path.isEmpty, !path.contains("\0"),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        let roots: [URL]
        let name: String
        if path.hasPrefix("/") {
            let url = URL(fileURLWithPath: path)
            name = url.lastPathComponent
            // Resolve only the trusted system root alias (e.g. /var -> /private/var).
            // Never resolve caller-controlled symlinks to decide file authority.
            let parent = url.deletingLastPathComponent().standardizedFileURL
            roots = [documents, temporaryDirectory].filter {
                parent.path == $0.path || parent.path == $0.path.replacingOccurrences(of: "/private/var/", with: "/var/", options: .anchored)
            }
        } else {
            guard !path.contains("/") else { return nil }
            name = path
            roots = bareRoots
        }
        for root in roots {
            guard let directory = LegacyMediaDirectory(root) else { return nil }
            var info = stat()
            if fstatat(directory.fd, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
                if errno == ENOENT { continue }
                return nil
            }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { return nil }
            let fd = openat(directory.fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { return nil }
            defer { Darwin.close(fd) }
            guard directory.matches(name, descriptor: fd) else { return nil }
            return body(directory, name, fd)
        }
        return nil
    }
}

/// A synchronous, descriptor-scoped capability for one trusted flat legacy root.
/// It cannot name descendants and is never passed across an actor suspension.
private final class LegacyMediaDirectory {
    let url: URL
    private(set) var fd: Int32

    init?(_ url: URL) {
        self.url = url
        fd = Self.openDirectory(url)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else {
            Darwin.close(fd)
            fd = -1
            return nil
        }
    }

    deinit { if fd >= 0 { Darwin.close(fd) } }

    private static func openDirectory(_ url: URL) -> Int32 {
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard current >= 0 else { return -1 }
        for part in url.pathComponents.dropFirst() {
            let next = openat(current, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            Darwin.close(current)
            guard next >= 0 else { return -1 }
            current = next
        }
        return current
    }

    func matches(_ name: String, descriptor: Int32, snapshot: stat? = nil) -> Bool {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return false }
        let current = Self.openDirectory(url)
        guard current >= 0 else { return false }
        defer { Darwin.close(current) }
        var heldRoot = stat(), namedRoot = stat(), held = stat(), named = stat()
        let identityMatches = fstat(fd, &heldRoot) == 0 && fstat(current, &namedRoot) == 0
            && heldRoot.st_dev == namedRoot.st_dev && heldRoot.st_ino == namedRoot.st_ino
            && fstat(descriptor, &held) == 0 && fstatat(fd, name, &named, AT_SYMLINK_NOFOLLOW) == 0
            && held.st_mode & S_IFMT == S_IFREG && named.st_mode & S_IFMT == S_IFREG
            && held.st_nlink == 1 && named.st_nlink == 1
            && held.st_dev == named.st_dev && held.st_ino == named.st_ino
        guard identityMatches else { return false }
        guard let snapshot else { return true }
        return held.st_size == snapshot.st_size
            && held.st_mtimespec.tv_sec == snapshot.st_mtimespec.tv_sec
            && held.st_mtimespec.tv_nsec == snapshot.st_mtimespec.tv_nsec
            && held.st_ctimespec.tv_sec == snapshot.st_ctimespec.tv_sec
            && held.st_ctimespec.tv_nsec == snapshot.st_ctimespec.tv_nsec
    }

    func remove(_ name: String, matching descriptor: Int32, snapshot: stat? = nil,
                synchronize: (Int32) -> Int32 = { fsync($0) }) -> Bool {
        guard matches(name, descriptor: descriptor, snapshot: snapshot), unlinkat(fd, name, 0) == 0 else { return false }
        return synchronize(fd) == 0
    }
}
