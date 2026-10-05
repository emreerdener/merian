import CryptoKit
import Darwin
import Foundation

/// Owns private child files through the synchronous durable queue commit.
/// Directory descriptors keep deletion/recreation from redirecting cleanup.
actor ObservationReanalysisFileStore {
    enum Failure: Error { case unavailable, conflict, busy, cleanupFailed }
    private struct CreatedFile { let name: String; let inode: ino_t; let descriptor: Int32 }
    private let documents: URL
    private var activeChildren = Set<UUID>()

    init(documents: URL) { self.documents = documents }

    /// The callback must atomically save the draft and must not throw after a successful save.
    /// Once it returns, cancellation cannot turn committed files into rollback candidates.
    func persist<T: Sendable>(draft: ObservationReanalysisDraft, photos: [Data],
                              commit: @MainActor @Sendable () throws -> T) async throws -> T {
        let child = draft.identity.analysisID
        guard activeChildren.insert(child).inserted else { throw Failure.busy }
        defer { activeChildren.remove(child) }
        let references = draft.evidence.compactMap { item -> ObservationEvidenceUpload.Reference? in
            if case let .image(photo) = item { return photo }; return nil
        }
        guard references.count == photos.count else { throw Failure.conflict }
        for (photo, reference) in zip(photos, references) { try verify(photo, reference: reference) }
        try Task.checkCancellation()
        let root = open(documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw Failure.unavailable }
        defer { close(root) }
        let queue = try directory("ReanalysisQueue", inside: root)
        defer { close(queue) }
        let directory = try directory(child.uuidString.lowercased(), inside: queue)
        defer { close(directory) }
        // A second store instance cannot adopt files before this instance commits or rolls back.
        guard flock(directory, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        defer { flock(directory, LOCK_UN) }
        var created: [CreatedFile] = []
        // Retaining each inode prevents reuse after unlink until rollback finishes.
        defer { for file in created { close(file.descriptor) } }
        do {
            for (index, reference) in references.enumerated() {
                try Task.checkCancellation()
                let suffix = reference.contentType == "image/png" ? "png" : "jpg"
                let name = reference.mediaID.uuidString.lowercased() + "." + suffix
                if let existing = try read(name, directory: directory, reference: reference) {
                    try verify(existing, reference: reference)
                } else {
                    created.append(try publish(photos[index], name: name, directory: directory))
                    guard let saved = try read(name, directory: directory, reference: reference) else { throw Failure.conflict }
                    try verify(saved, reference: reference)
                }
            }
            guard fsync(directory) == 0, fsync(queue) == 0, fsync(root) == 0 else { throw Failure.unavailable }
            try Task.checkCancellation()
            // Keep the filesystem lock and actor reservation across this one suspension.
            return try await commit()
        } catch {
            var cleaned = true
            for file in created.reversed() {
                var info = stat()
                if fstatat(directory, file.name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
                    if info.st_ino == file.inode, unlinkat(directory, file.name, 0) != 0 { cleaned = false }
                } else if errno != ENOENT { cleaned = false }
            }
            if !created.isEmpty, fsync(directory) != 0 { cleaned = false }
            guard cleaned else { throw Failure.cleanupFailed }
            throw error
        }
    }

    private func verify(_ data: Data, reference: ObservationEvidenceUpload.Reference) throws {
        guard data.count == reference.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == reference.sha256 else { throw Failure.conflict }
    }

    private func directory(_ name: String, inside parent: Int32) throws -> Int32 {
        guard mkdirat(parent, name, 0o700) == 0 || errno == EEXIST else { throw Failure.unavailable }
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.conflict }
        return descriptor
    }

    private func read(_ name: String, directory: Int32, reference: ObservationEvidenceUpload.Reference) throws -> Data? {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }; throw Failure.conflict
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size == reference.byteCount else { throw Failure.conflict }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var bytes = Data()
        while let chunk = try handle.read(upToCount: min(65_536, reference.byteCount - bytes.count + 1)), !chunk.isEmpty {
            guard chunk.count <= reference.byteCount - bytes.count else { throw Failure.conflict }
            bytes.append(chunk)
        }
        return bytes
    }

    private func publish(_ data: Data, name: String, directory: Int32) throws -> CreatedFile {
        let temporary = "." + UUID().uuidString.lowercased() + ".preparing"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure.unavailable }
        var published = false
        defer { if !published { close(descriptor) }; unlinkat(directory, temporary, 0) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        var info = stat()
        guard fsync(descriptor) == 0, fstat(descriptor, &info) == 0 else { throw Failure.unavailable }
        // Exclusive rename consumes the temporary name atomically; no extra private hard link survives a successful save.
        guard renameatx_np(directory, temporary, directory, name, UInt32(RENAME_EXCL)) == 0 else { throw Failure.conflict }
        published = true
        return CreatedFile(name: name, inode: info.st_ino, descriptor: descriptor)
    }
}
