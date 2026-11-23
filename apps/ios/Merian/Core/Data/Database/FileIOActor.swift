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
    private struct PendingProducerCleanup {
        let revision: UUID
        let operation: @Sendable () async throws -> Void
    }
    private var pendingProducerCleanup: [ObjectIdentifier: PendingProducerCleanup] = [:]

    /// Failed disposable-output cleanup stays strongly owned across caller exit.
    /// Only already-drained producers may enter this retry registry.
    func settleProducerCleanup(owner: any AnyObject & Sendable,
                               operation: @escaping @Sendable () async throws -> Void) async -> Bool {
        let id = ObjectIdentifier(owner)
        let revision = UUID()
        pendingProducerCleanup[id] = .init(revision: revision, operation: operation)
        do {
            try await operation()
            if pendingProducerCleanup[id]?.revision == revision { pendingProducerCleanup[id] = nil }
            return true
        } catch { return false }
    }

    func retryProducerCleanup() async -> Bool {
        for (id, pending) in Array(pendingProducerCleanup) {
            do {
                try await pending.operation()
                if pendingProducerCleanup[id]?.revision == pending.revision { pendingProducerCleanup[id] = nil }
            } catch { continue }
        }
        return pendingProducerCleanup.isEmpty
    }

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

    /// Captures only a verified flat disposable file. This receipt never grants
    /// access to retained originals or any private media-store namespace.
    func readRetainedOriginal(_ receipt: LegacyMediaFileRetirement, maximumBytes: Int) -> Data? {
        receipt.read(maximumBytes: maximumBytes)
    }

    func retirementForDisposableFile(at path: String) -> LegacyMediaFileRetirement? {
        withFile(at: path, bareRoots: [documents]) { directory, name, descriptor in
            LegacyMediaFileRetirement(directory: directory, name: name, descriptor: descriptor)
        }
    }

    /// Cleanup ignores task cancellation; account drain must join its result.
    func retireDisposableFiles(_ receipts: [LegacyMediaFileRetirement]) -> Bool {
        var complete = true
        for receipt in receipts where !receipt.remove(synchronize: copyIO.synchronize) { complete = false }
        return complete
    }

    public func persistAudioFile(tempPath: String) -> String? {
        persistMediaFile(tempPath: tempPath, suffix: "audio", preferredExtension: "wav")
    }

    /// One verified historical WAV becomes an ordinary workspace-owned staging
    /// file. This does not adopt the saved original or create a queue operation.
    func stageHistoryAudio(_ bytes: Data) -> String? {
        guard ObservationAudioContainer.isValid(bytes) else { return nil }
        return stageHistoryMedia(bytes, suffix: "wav")
    }

    func stageHistoryVideo(_ bytes: Data) -> String? {
        guard !bytes.isEmpty, bytes.count <= ScanMediaPayloadPolicy.maxSavedVideoBytes else { return nil }
        return stageHistoryMedia(bytes, suffix: "mp4")
    }

    private func stageHistoryMedia(_ bytes: Data, suffix: String) -> String? {
        guard !Task.isCancelled, let directory = LegacyMediaDirectory(documents) else { return nil }
        let name = "\(UUID().uuidString.lowercased())_history-staging.\(suffix)"
        let fd = openat(directory.fd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var complete = false
        defer { if !complete { _ = directory.remove(name, matching: fd) } }
        let written = bytes.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                guard !Task.isCancelled else { return false }
                let remaining = UnsafeRawBufferPointer(rebasing: buffer[offset...])
                let count = copyIO.write(fd, remaining)
                if count < 0 && errno == EINTR { continue }
                guard count > 0, count <= remaining.count else { return false }
                offset += count
            }
            return true
        }
        guard written, copyIO.synchronize(fd) == 0, copyIO.synchronize(directory.fd) == 0,
              !Task.isCancelled, directory.matches(name, descriptor: fd) else { return nil }
        complete = true
        return name
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
            guard let initial = copyBytes(from: sourceFD, to: output),
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

    /// Only the existing reanalysis FileStore supplies this held, empty output
    /// descriptor after its durable identity commit. It owns all cleanup and
    /// directory synchronization; this actor owns the existing bounded copy.
    func copyVideoInput(filename: String, ownedOutput: Int32) -> Bool {
        guard !filename.isEmpty, !filename.contains("/"), !filename.contains("\0"), !Task.isCancelled else { return false }
        return copyVideoInput(path: filename, expected: nil, ownedOutput: ownedOutput)
    }

    /// A process-local descriptor identity for an explicitly workspace-owned
    /// file. This grants no authority over the scan's mutable legacy attachments.
    struct StagedVideoInput: Equatable, Sendable {
        let path: String
        fileprivate let identity: VideoSnapshot.Identity
        fileprivate let rootDevice: dev_t
        fileprivate let rootInode: ino_t
        var binding: String {
            "\(rootDevice):\(rootInode):\(identity.device):\(identity.inode):\(identity.size):" +
                "\(identity.modifiedSeconds):\(identity.modifiedNanos):\(identity.changedSeconds):\(identity.changedNanos)"
        }
    }

    func stagedVideoInput(path: String) -> StagedVideoInput? {
        guard !Task.isCancelled else { return nil }
        return withFile(at: path, bareRoots: [documents]) { directory, _, fd in
            var info = stat(), root = stat()
            guard fstat(fd, &info) == 0, fstat(directory.fd, &root) == 0,
                  info.st_size > 0, info.st_size <= off_t(ScanMediaPayloadPolicy.maxSavedVideoBytes) else { return nil }
            return StagedVideoInput(path: path, identity: .init(info), rootDevice: root.st_dev, rootInode: root.st_ino)
        }
    }

    func copyVideoInput(_ input: StagedVideoInput, ownedOutput: Int32) -> Bool {
        copyVideoInput(path: input.path, expected: input, ownedOutput: ownedOutput)
    }

    private func copyVideoInput(path: String, expected: StagedVideoInput?, ownedOutput: Int32) -> Bool {
        guard !Task.isCancelled else { return false }
        var destination = stat()
        guard fstat(ownedOutput, &destination) == 0, destination.st_mode & S_IFMT == S_IFREG,
              destination.st_nlink == 1, destination.st_size == 0,
              lseek(ownedOutput, 0, SEEK_CUR) == 0 else { return false }
        return withFile(at: path, bareRoots: [documents]) { source, name, sourceFD in
            if let expected {
                var info = stat(), root = stat()
                guard fstat(sourceFD, &info) == 0, fstat(source.fd, &root) == 0,
                      root.st_dev == expected.rootDevice, root.st_ino == expected.rootInode,
                      VideoSnapshot.Identity(info) == expected.identity else { return false }
            }
            guard let initial = copyBytes(from: sourceFD, to: ownedOutput,
                    maximumBytes: off_t(ScanMediaPayloadPolicy.maxSavedVideoBytes), cancellable: true),
                  copyIO.synchronize(ownedOutput) == 0, !Task.isCancelled,
                  source.matches(name, descriptor: sourceFD, snapshot: initial) else { return false }
            var final = stat()
            guard fstat(ownedOutput, &final) == 0, final.st_mode & S_IFMT == S_IFREG,
                  final.st_nlink == 1, final.st_dev == destination.st_dev, final.st_ino == destination.st_ino,
                  final.st_birthtimespec.tv_sec == destination.st_birthtimespec.tv_sec,
                  final.st_birthtimespec.tv_nsec == destination.st_birthtimespec.tv_nsec,
                  final.st_size == initial.st_size else { return false }
            return true
        } ?? false
    }

    /// Caller must separately establish observation/account/media authority. This
    /// copies one explicitly chosen flat Documents attachment without adopting or deleting it.
    /// The returned token is process-local input ownership, never historical media evidence.
    func snapshotVideoFile(filename: String) -> VideoSnapshot? {
        guard !filename.isEmpty, !filename.contains("/"), !Task.isCancelled else { return nil }
        return snapshotMediaFile(path: filename, suffix: "mp4", maximumBytes: ScanMediaPayloadPolicy.maxSavedVideoBytes)
    }

    /// Capture's preparer returns an owned absolute playback URL. This entry
    /// accepts only flat Documents/temporary files through the same descriptor
    /// checks, without widening History's basename-only attachment interface.
    func snapshotCapturePlayback(path: String) -> VideoSnapshot? {
        guard path.hasPrefix("/") else { return nil }
        return snapshotMediaFile(path: path, suffix: "mp4", maximumBytes: ScanMediaPayloadPolicy.maxSavedVideoBytes)
    }

    /// Freeze an explicitly staged audio file before AVFoundation opens a URL.
    /// The same descriptor and flat-root checks apply to Documents and temporary inputs.
    func snapshotAudioFile(path: String) -> VideoSnapshot? {
        snapshotMediaFile(path: path, suffix: "wav", maximumBytes: ScanMediaPayloadPolicy.maxInferenceAudioBytes)
    }

    private func snapshotMediaFile(path: String, suffix: String, maximumBytes: Int) -> VideoSnapshot? {
        guard !Task.isCancelled else { return nil }
        return withFile(at: path, bareRoots: [documents]) { source, name, sourceFD in
            guard let destination = LegacyMediaDirectory(temporaryDirectory) else { return nil }
            let copiedName = "\(UUID().uuidString.lowercased())_reanalysis-input.\(suffix)"
            let output = openat(destination.fd, copiedName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard output >= 0 else { return nil }
            defer { Darwin.close(output) }
            var complete = false
            defer { if !complete { _ = destination.remove(copiedName, matching: output) } }
            guard let initial = copyBytes(from: sourceFD, to: output,
                    maximumBytes: off_t(maximumBytes), cancellable: true),
                  copyIO.synchronize(output) == 0, copyIO.synchronize(destination.fd) == 0,
                  !Task.isCancelled, source.matches(name, descriptor: sourceFD, snapshot: initial),
                  destination.matches(copiedName, descriptor: output) else { return nil }
            var copied = stat(), root = stat()
            guard fstat(output, &copied) == 0, fstat(destination.fd, &root) == 0 else { return nil }
            complete = true
            return VideoSnapshot(url: temporaryDirectory.appendingPathComponent(copiedName),
                identity: .init(copied), rootDevice: root.st_dev, rootInode: root.st_ino)
        }
    }

    /// Check before and after consuming the owned URL. A replaced/changed copy
    /// cannot be delivered, and cleanup must not remove its replacement.
    func videoSnapshotIsCurrent(_ snapshot: VideoSnapshot) -> Bool {
        withVideoSnapshot(snapshot) { _, _, _ in true } ?? false
    }

    @discardableResult
    func discardVideoSnapshot(_ snapshot: VideoSnapshot) -> Bool {
        withVideoSnapshot(snapshot) { directory, name, fd in directory.remove(name, matching: fd) } ?? false
    }

    /// Reads only this owner's immutable disposable snapshot. Rechecks its
    /// descriptor and named identity after the bounded read; no path authority
    /// is inferred from the caller's URL.
    func readVideoSnapshot(_ snapshot: VideoSnapshot, maximumBytes: Int) -> Data? {
        guard maximumBytes > 0, maximumBytes <= ScanMediaPayloadPolicy.maxSavedVideoBytes else { return nil }
        return withVideoSnapshot(snapshot) { directory, name, fd in
            guard !Task.isCancelled, snapshot.identity.size > 0,
                  snapshot.identity.size <= maximumBytes else { return nil }
            var bytes = Data(count: Int(snapshot.identity.size)), offset = 0
            let complete = bytes.withUnsafeMutableBytes { buffer -> Bool in
                while offset < buffer.count {
                    guard !Task.isCancelled else { return false }
                    let count = pread(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, off_t(offset))
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { return false }
                    offset += count
                }
                return true
            }
            var final = stat()
            guard complete, !Task.isCancelled, fstat(fd, &final) == 0,
                  VideoSnapshot.Identity(final) == snapshot.identity,
                  directory.matches(name, descriptor: fd, snapshot: final) else { return nil }
            return bytes
        }
    }

    private func withVideoSnapshot<T>(_ snapshot: VideoSnapshot,
                                      body: (LegacyMediaDirectory, String, Int32) -> T?) -> T? {
        guard snapshot.url.deletingLastPathComponent().path == temporaryDirectory.path else { return nil }
        return withFile(at: snapshot.url.path, bareRoots: [temporaryDirectory]) { directory, name, fd in
            var info = stat(), root = stat()
            guard fstat(fd, &info) == 0, fstat(directory.fd, &root) == 0,
                  root.st_dev == snapshot.rootDevice, root.st_ino == snapshot.rootInode,
                  VideoSnapshot.Identity(info) == snapshot.identity else { return nil }
            return body(directory, name, fd)
        }
    }

    struct VideoSnapshot: Sendable {
        let url: URL
        fileprivate let identity: Identity
        fileprivate let rootDevice: dev_t
        fileprivate let rootInode: ino_t

        // Descriptor identity remains scoped to the file-I/O snapshot owner.
        // swiftlint:disable:next nesting
        fileprivate struct Identity: Equatable, Sendable {
            let device: dev_t, inode: ino_t, size: off_t
            let modifiedSeconds: time_t, changedSeconds: time_t
            let modifiedNanos: Int, changedNanos: Int
            init(_ value: stat) {
                device = value.st_dev; inode = value.st_ino; size = value.st_size
                modifiedSeconds = value.st_mtimespec.tv_sec; changedSeconds = value.st_ctimespec.tv_sec
                modifiedNanos = value.st_mtimespec.tv_nsec; changedNanos = value.st_ctimespec.tv_nsec
            }
        }
    }

    private func copyBytes(from sourceFD: Int32, to output: Int32,
                           maximumBytes: off_t? = nil, cancellable: Bool = false) -> stat? {
        var initial = stat()
        guard fstat(sourceFD, &initial) == 0, initial.st_size >= 0,
              maximumBytes.map({ initial.st_size > 0 && initial.st_size <= $0 }) ?? true else { return nil }
        var remaining = initial.st_size
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while remaining > 0 {
            guard !cancellable || !Task.isCancelled else { return nil }
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
              VideoSnapshot.Identity(initial) == VideoSnapshot.Identity(final) else { return nil }
        return initial
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
