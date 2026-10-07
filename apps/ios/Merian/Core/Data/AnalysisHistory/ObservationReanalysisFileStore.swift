import CryptoKit
import Darwin
import Foundation

/// Owns private child files through the synchronous durable queue commit.
/// Directory descriptors keep deletion/recreation from redirecting cleanup.
actor ObservationReanalysisFileStore {
    enum Failure: Error { case unavailable, conflict, busy, cleanupFailed, incomplete }
    private struct FileReference: Sendable {
        let name: String
        let byteCount: Int
        let sha256: String
    }
    private struct CreatedFile { let name: String; let inode: ino_t; let descriptor: Int32 }
    private let documents: URL
    private var activeChildren = Set<UUID>()

    init(documents: URL) { self.documents = documents }

    /// The callback must atomically save the draft and must not throw after a successful save.
    /// Once it returns, cancellation cannot turn committed files into rollback candidates.
    func persist<T: Sendable>(draft: ObservationReanalysisDraft, photos: [Data],
                              validateBeforeWrite: @MainActor @Sendable () throws -> Void = {},
                              commit: @MainActor @Sendable () throws -> T) async throws -> T {
        let references = photoReferences(draft)
        return try await persist(child: draft.identity.analysisID, references: references, bytes: photos,
            validateBeforeWrite: validateBeforeWrite, commit: commit)
    }

    /// WAV bytes remain separate from photo manifests and image paths. Durable ownership
    /// already exists; retain verified files when promotion throws because its save may have committed.
    func persistAudio<T: Sendable>(preparation: ObservationAudioPreparation, bytes: Data,
                                   validateBeforeWrite: @MainActor @Sendable () throws -> Void,
                                   commit: @MainActor @Sendable () throws -> T) async throws -> T {
        guard ObservationAudioContainer.isValid(bytes) else { throw Failure.conflict }
        return try await persist(child: preparation.identity.analysisID, references: [audioReference(preparation)], bytes: [bytes],
            retainAfterCommitError: true, validateBeforeWrite: validateBeforeWrite, commit: commit)
    }

    private func persist<T: Sendable>(child: UUID, references: [FileReference], bytes: [Data],
                                      retainAfterCommitError: Bool = false,
                                      validateBeforeWrite: @MainActor @Sendable () throws -> Void,
                                      commit: @MainActor @Sendable () throws -> T) async throws -> T {
        guard activeChildren.insert(child).inserted else { throw Failure.busy }
        defer { activeChildren.remove(child) }
        guard references.count == bytes.count else { throw Failure.conflict }
        for (data, reference) in zip(bytes, references) { try verify(data, reference: reference) }
        try Task.checkCancellation()
        let root = open(documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw Failure.unavailable }
        defer { close(root) }
        // Full-library erasure must take the exclusive side of this stable root lock.
        guard flock(root, LOCK_SH | LOCK_NB) == 0 else { throw Failure.busy }
        defer { flock(root, LOCK_UN) }
        let queue = try directory("ReanalysisQueue", inside: root)
        defer { close(queue) }
        let directory = try directory(child.uuidString.lowercased(), inside: queue)
        defer { close(directory) }
        // A second store instance cannot adopt files before this instance commits or rolls back.
        guard flock(directory, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        defer { flock(directory, LOCK_UN) }
        var created: [CreatedFile] = []
        var commitStarted = false
        // Retaining each inode prevents reuse after unlink until rollback finishes.
        defer { for file in created { close(file.descriptor) } }
        do {
            // Recheck durable ownership only after the filesystem fence is held.
            try await validateBeforeWrite()
            try Task.checkCancellation()
            for (index, reference) in references.enumerated() {
                try Task.checkCancellation()
                let name = reference.name
                if let existing = try read(name, directory: directory, reference: reference) {
                    try verify(existing, reference: reference)
                } else {
                    created.append(try publish(bytes[index], name: name, directory: directory))
                    guard let saved = try read(name, directory: directory, reference: reference) else { throw Failure.conflict }
                    try verify(saved, reference: reference)
                }
            }
            guard fsync(directory) == 0, fsync(queue) == 0, fsync(root) == 0 else { throw Failure.unavailable }
            try Task.checkCancellation()
            guard try names(in: directory) == references.map(\.name).sorted(),
                  sameDirectory(queue, named: "ReanalysisQueue", inside: root),
                  sameDirectory(directory, named: child.uuidString.lowercased(), inside: queue) else { throw Failure.conflict }
            // Keep the filesystem lock and actor reservation across this one suspension.
            commitStarted = true
            return try await commit()
        } catch {
            // A durable pending/ready audio owner or its erasure receipt still owns these bytes.
            // Recovery decides the saved phase; an uncertain save cannot destroy evidence.
            if retainAfterCommitError, commitStarted { throw error }
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

    /// Adopts only the complete saved cohort. Never creates, repairs or removes evidence.
    func recover<T: Sendable>(draft: ObservationReanalysisDraft,
                              validateBeforeRead: @MainActor @Sendable () throws -> Void,
                              commit: @MainActor @Sendable () throws -> T) async throws -> T {
        try await withVerifiedPhotos(draft: draft, validateBeforeRead: validateBeforeRead) { _ in try commit() }
    }

    /// Returns the original ordered upload bytes, never paths or newly encoded successors.
    /// Callers supply fresh durable claim/account checks at both locked boundaries and
    /// must revalidate the account and claim again after awaiting this private result.
    func readPhotos(draft: ObservationReanalysisDraft,
                    validateBeforeRead: @MainActor @Sendable () throws -> Void,
                    validateBeforeReturn: @MainActor @Sendable () throws -> Void) async throws -> [ObservationEvidenceUpload.Photo] {
        let photos = try await withVerifiedPhotos(draft: draft, validateBeforeRead: validateBeforeRead) { photos in
            try Task.checkCancellation()
            try validateBeforeReturn()
            try Task.checkCancellation()
            return photos
        }
        try Task.checkCancellation()
        return photos
    }

    private func withVerifiedPhotos<T: Sendable>(draft: ObservationReanalysisDraft,
                                                 validateBeforeRead: @MainActor @Sendable () throws -> Void,
                                                 commit: @MainActor @Sendable ([ObservationEvidenceUpload.Photo]) throws -> T) async throws -> T {
        let references = draft.evidence.compactMap { item -> ObservationEvidenceUpload.Reference? in
            if case let .image(photo) = item { return photo }; return nil
        }
        return try await withVerifiedFiles(child: draft.identity.analysisID, references: photoReferences(draft),
            validateBeforeRead: validateBeforeRead, verifyContainer: { index, bytes in
                let reference = references[index]
                _ = try ObservationReanalysisPhotoPreparation.prepare(bytes: bytes, mediaID: reference.mediaID,
                    original: .init(mediaID: reference.mediaID, contentType: reference.contentType, byteCount: reference.byteCount, sha256: reference.sha256))
            }) { bytes in
                try commit(zip(references, bytes).map { .init(mediaID: $0.0.mediaID, contentType: $0.0.contentType, bytes: $0.1) })
            }
    }

    /// Recovery verifies the complete exact WAV cohort and commits while both locks remain held.
    func recoverAudio<T: Sendable>(preparation: ObservationAudioPreparation,
                                   validateBeforeRead: @MainActor @Sendable () throws -> Void,
                                   commit: @MainActor @Sendable () throws -> T) async throws -> T {
        try await withVerifiedFiles(child: preparation.identity.analysisID, references: [audioReference(preparation)],
            validateBeforeRead: validateBeforeRead, verifyContainer: { _, bytes in guard ObservationAudioContainer.isValid(bytes) else { throw Failure.conflict } }) { _ in
            try commit()
        }
    }

    private func withVerifiedFiles<T: Sendable>(child: UUID, references: [FileReference],
                                                validateBeforeRead: @MainActor @Sendable () throws -> Void,
                                                verifyContainer: @Sendable (Int, Data) throws -> Void,
                                                commit: @MainActor @Sendable ([Data]) throws -> T) async throws -> T {
        guard activeChildren.insert(child).inserted else { throw Failure.busy }
        defer { activeChildren.remove(child) }
        try Task.checkCancellation()
        let root = open(documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw Failure.unavailable }
        defer { close(root) }
        guard flock(root, LOCK_SH | LOCK_NB) == 0 else { throw Failure.busy }
        defer { flock(root, LOCK_UN) }
        let queue = try existingDirectory("ReanalysisQueue", inside: root)
        defer { close(queue) }
        let directory = try existingDirectory(child.uuidString.lowercased(), inside: queue)
        defer { close(directory) }
        guard flock(directory, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        defer { flock(directory, LOCK_UN) }
        try await validateBeforeRead()
        guard try names(in: directory) == references.map(\.name).sorted() else { throw Failure.incomplete }
        var retained: [Data] = []
        for (index, reference) in references.enumerated() {
            try Task.checkCancellation()
            guard let bytes = try read(reference.name, directory: directory, reference: reference, synchronize: true) else { throw Failure.incomplete }
            try verify(bytes, reference: reference)
            try verifyContainer(index, bytes)
            retained.append(bytes)
        }
        guard fsync(directory) == 0, fsync(queue) == 0, fsync(root) == 0 else { throw Failure.unavailable }
        try Task.checkCancellation()
        guard sameDirectory(queue, named: "ReanalysisQueue", inside: root),
              sameDirectory(directory, named: child.uuidString.lowercased(), inside: queue) else { throw Failure.conflict }
        return try await commit(retained)
    }

    /// Namespace authority comes from a committed receipt, never from caller-provided paths.
    /// Keep the empty directory as the stable child lock; full-library purge removes it later.
    func erase(child: UUID, authorize: @MainActor @Sendable () throws -> Bool,
               acknowledge: @MainActor @Sendable () throws -> Void) async throws {
        guard activeChildren.insert(child).inserted else { throw Failure.busy }
        defer { activeChildren.remove(child) }
        try Task.checkCancellation()
        let root = open(documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw Failure.unavailable }
        defer { close(root) }
        guard flock(root, LOCK_SH | LOCK_NB) == 0 else { throw Failure.busy }
        defer { flock(root, LOCK_UN) }
        let queue = try directory("ReanalysisQueue", inside: root)
        defer { close(queue) }
        let directory = try directory(child.uuidString.lowercased(), inside: queue)
        defer { close(directory) }
        guard flock(directory, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        defer { flock(directory, LOCK_UN) }
        guard try await authorize() else { return }
        for name in try names(in: directory) {
            try Task.checkCancellation()
            var info = stat()
            guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  [S_IFREG, S_IFLNK].contains(info.st_mode & S_IFMT) else { throw Failure.cleanupFailed }
            guard unlinkat(directory, name, 0) == 0 else { throw Failure.cleanupFailed }
        }
        guard fsync(directory) == 0, fsync(queue) == 0, fsync(root) == 0 else { throw Failure.cleanupFailed }
        try Task.checkCancellation()
        guard sameDirectory(queue, named: "ReanalysisQueue", inside: root),
              sameDirectory(directory, named: child.uuidString.lowercased(), inside: queue) else { throw Failure.cleanupFailed }
        try await acknowledge()
    }

    /// Full-library authority only. The Auth transition must already have drained account-bound writers.
    /// Unlike child cleanup, this removes orphaned namespaces too, without following any links.
    func purgeNamespace() throws {
        try Task.checkCancellation()
        guard activeChildren.isEmpty else { throw Failure.busy }
        let root = open(documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw Failure.unavailable }
        defer { close(root) }
        guard flock(root, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        defer { flock(root, LOCK_UN) }
        try removeEntry("ReanalysisQueue", inside: root, depth: 0)
        guard fsync(root) == 0 else { throw Failure.cleanupFailed }
    }

    private func removeEntry(_ name: String, inside parent: Int32, depth: Int) throws {
        try Task.checkCancellation()
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return }; throw Failure.cleanupFailed
        }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            guard unlinkat(parent, name, 0) == 0 else { throw Failure.cleanupFailed }
            return
        }
        guard depth < 16 else { throw Failure.cleanupFailed }
        let directory = try existingDirectory(name, inside: parent)
        defer { close(directory) }
        let copy = dup(directory)
        guard copy >= 0 else { throw Failure.unavailable }
        guard let stream = fdopendir(copy) else { close(copy); throw Failure.unavailable }
        defer { closedir(stream) }
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw Failure.cleanupFailed }
                break
            }
            let child = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if child != ".", child != ".." { try removeEntry(child, inside: directory, depth: depth + 1) }
        }
        guard fsync(directory) == 0, sameDirectory(directory, named: name, inside: parent),
              unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw Failure.cleanupFailed }
    }

    private func sameDirectory(_ descriptor: Int32, named name: String, inside parent: Int32) -> Bool {
        var held = stat(), current = stat()
        return fstat(descriptor, &held) == 0 && fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0
            && current.st_mode & S_IFMT == S_IFDIR && current.st_dev == held.st_dev && current.st_ino == held.st_ino
    }

    private func names(in directory: Int32) throws -> [String] {
        let copy = dup(directory)
        guard copy >= 0 else { throw Failure.unavailable }
        guard let stream = fdopendir(copy) else { close(copy); throw Failure.unavailable }
        defer { closedir(stream) }
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw Failure.cleanupFailed }
                return result.sorted()
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            guard name != ".", name != ".." else { continue }
            guard result.count < 256 else { throw Failure.cleanupFailed }
            result.append(name)
        }
    }

    private func photoReferences(_ draft: ObservationReanalysisDraft) -> [FileReference] {
        draft.evidence.compactMap { item in
            guard case let .image(photo) = item else { return nil }
            return FileReference(name: photo.mediaID.uuidString.lowercased() + (photo.contentType == "image/png" ? ".png" : ".jpg"),
                byteCount: photo.byteCount, sha256: photo.sha256)
        }
    }

    private func audioReference(_ preparation: ObservationAudioPreparation) -> FileReference {
        FileReference(name: preparation.audio.mediaID.uuidString.lowercased() + ".wav",
            byteCount: preparation.audio.byteCount, sha256: preparation.audio.sha256)
    }

    private func verify(_ data: Data, reference: FileReference) throws {
        guard data.count == reference.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == reference.sha256 else { throw Failure.conflict }
    }

    private func directory(_ name: String, inside parent: Int32) throws -> Int32 {
        guard mkdirat(parent, name, 0o700) == 0 || errno == EEXIST else { throw Failure.unavailable }
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.conflict }
        return descriptor
    }

    private func existingDirectory(_ name: String, inside parent: Int32) throws -> Int32 {
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw Failure.incomplete }
            if errno == ELOOP || errno == ENOTDIR { throw Failure.conflict }
            throw Failure.unavailable
        }
        return descriptor
    }

    private func read(_ name: String, directory: Int32, reference: FileReference,
                      synchronize: Bool = false) throws -> Data? {
        let descriptor = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
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
        if synchronize && fsync(descriptor) != 0 { throw Failure.unavailable }
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
