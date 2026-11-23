import Darwin
import Foundation

/// Descriptive scratch storage, never deletion authority. The caller must audit
/// both source-to-file and file-to-source ownership under its held fences.
/// External merge sorting keeps memory bounded independently of library size.
@MainActor
final class SharedMediaNativeErasureManifestSpool {
    typealias Manifest = SharedMediaNativeErasureManifest
    private static let slotBytes = 2048
    private let ownerID: UUID
    private let checkpoint: () throws -> Void
    private let scratchDirectory: URL
    private var file: Scratch
    private var buffered: [Manifest.Entry] = []
    private var count: Int64 = 0
    private var sealed = false
    private var failed = false

    init(ownerID: UUID, checkpoint: @escaping () throws -> Void) throws {
        self.ownerID = ownerID; self.checkpoint = checkpoint
        scratchDirectory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        try checkpoint(); try Task.checkCancellation()
        file = try Scratch(directory: scratchDirectory)
    }

    func append(_ entry: Manifest.Entry) throws {
        do {
            try requireOpen(); try entry.validate(ownerID: ownerID)
            buffered.append(entry)
            if buffered.count == Manifest.pageSize { try flush() }
        } catch { failed = true; throw error }
    }

    /// A failed/cancelled build cannot be resumed or used as a partial manifest.
    /// A cold operation rebuilds from its independently revalidated source graph.
    func seal() async throws {
        do {
            try requireOpen(); try flush()
            guard count >= 1 else { throw SharedMediaStorageFailure.invalid }
            var width = Int64(Manifest.pageSize)
            while width < count {
                try check()
                let output = try Scratch(directory: scratchDirectory)
                try output.requireSpace(for: count)
                var start: Int64 = 0
                while start < count {
                    let middle = min(count, try SharedMediaStoragePolicy.add(start, width))
                    let end = min(count, try SharedMediaStoragePolicy.add(middle, width))
                    try await merge(from: start, middle: middle, end: end, into: output)
                    start = end
                }
                file = output
                // Avoid overflow when the last merge has covered the stream.
                width = width > count / 2 ? count : width * 2
            }
            try check(); sealed = true
        } catch { failed = true; throw error }
    }

    /// Repeatable canonical pages let the owner compute the header before
    /// persisting intent, then append precisely the same chain to the journal.
    func visitPages(profile: SharedMediaNativeAppProfile, operationID: UUID,
                    _ body: (Data) throws -> Void) async throws -> Manifest.Chain {
        guard sealed, !failed, profile.ownerID == ownerID else { throw SharedMediaStorageFailure.closed }
        var chain = Manifest.Chain(operationID: operationID, profile: profile)
        let profileHash = try SharedMediaAcquisitionEncoding.digest(profile.binding)
        var index: Int64 = 0
        while index < count {
            try check()
            var entries: [Manifest.Entry] = []
            while index < count, entries.count < Manifest.pageSize {
                entries.append(try file.read(index, ownerID: ownerID)); index += 1
            }
            let page = try Manifest.Page(version: 1, operationID: operationID, profileSHA256: profileHash,
                ordinal: chain.pageCount, previousSHA256: chain.digest, entries: entries).encoded(profile: profile)
            _ = try chain.consume(page)
            try body(page); await Task.yield(); try check()
        }
        return chain
    }

    private func check() throws { try Task.checkCancellation(); try checkpoint() }
    private func requireOpen() throws {
        guard !sealed, !failed else { throw SharedMediaStorageFailure.closed }
        try check()
    }
    private func flush() throws {
        guard !buffered.isEmpty else { return }
        try check(); buffered.sort { $0.key < $1.key }
        let next = try SharedMediaStoragePolicy.add(count, Int64(buffered.count))
        try file.requireSpace(for: Int64(buffered.count))
        var previous: String?
        for entry in buffered {
            guard previous.map({ $0 < entry.key }) ?? true else { throw SharedMediaStorageFailure.conflict }
            try file.write(entry, at: count); count += 1; previous = entry.key
        }
        guard count == next else { throw SharedMediaStorageFailure.conflict }
        buffered.removeAll(keepingCapacity: true)
    }
    private func merge(from start: Int64, middle: Int64, end: Int64, into output: Scratch) async throws {
        var left = start, right = middle, destination = start
        var first = left < middle ? try file.read(left, ownerID: ownerID) : nil
        var second = right < end ? try file.read(right, ownerID: ownerID) : nil
        var previous: String?
        while let entry = first ?? second {
            if (destination - start) % Int64(Manifest.pageSize) == 0 { await Task.yield() }
            try check()
            let chooseFirst = first != nil && (second == nil || first!.key < second!.key)
            let selected = chooseFirst ? first! : second ?? entry
            guard previous.map({ $0 < selected.key }) ?? true else { throw SharedMediaStorageFailure.conflict }
            try output.write(selected, at: destination); destination += 1; previous = selected.key
            if chooseFirst {
                left += 1; first = left < middle ? try file.read(left, ownerID: ownerID) : nil
            } else {
                right += 1; second = right < end ? try file.read(right, ownerID: ownerID) : nil
            }
        }
        guard destination == end else { throw SharedMediaStorageFailure.conflict }
    }

    /// The random scratch name is unlinked before any content is written. Its
    /// only lifetime is this descriptor, including errors and cancellation.
    @MainActor private final class Scratch {
        let descriptor: Int32
        init(directory: URL) throws {
            let parent = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard parent >= 0 else { throw SharedMediaStorageFailure.unavailable }
            defer { Darwin.close(parent) }
            var held = stat(), named = stat()
            guard fstat(parent, &held) == 0, lstat(directory.path, &named) == 0,
                  held.st_mode & S_IFMT == S_IFDIR, named.st_mode & S_IFMT == S_IFDIR,
                  held.st_dev == named.st_dev, held.st_ino == named.st_ino, held.st_uid == getuid() else {
                throw SharedMediaStorageFailure.conflict
            }
            let name = "native-erasure-" + UUID().uuidString.lowercased()
            let opened = openat(parent, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
            guard opened >= 0 else { throw SharedMediaStorageFailure.unavailable }
            guard unlinkat(parent, name, 0) == 0 else {
                Darwin.close(opened); throw SharedMediaStorageFailure.unavailable
            }
            var value = stat()
            guard fstat(opened, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
                  value.st_nlink == 0, value.st_uid == getuid(), value.st_size == 0 else {
                Darwin.close(opened); throw SharedMediaStorageFailure.conflict
            }
            descriptor = opened
        }
        deinit { Darwin.close(descriptor) }

        func requireSpace(for slots: Int64) throws {
            let required = try Self.offset(slots)
            var filesystem = statfs()
            guard fstatfs(descriptor, &filesystem) == 0,
                  let blocks = Int64(exactly: filesystem.f_bavail), filesystem.f_bsize > 0 else {
                throw SharedMediaStorageFailure.unavailable
            }
            let (available, overflow) = blocks.multipliedReportingOverflow(by: Int64(filesystem.f_bsize))
            guard !overflow, available >= (try SharedMediaStoragePolicy.add(required, PhotoPreparationPolicy.minimumFree)) else {
                throw SharedMediaStorageFailure.capacity
            }
        }
        func write(_ entry: Manifest.Entry, at index: Int64) throws {
            let encoded = try SharedMediaAcquisitionEncoding.encode(entry, maximum: Self.payloadBytes)
            var bytes = Data(repeating: 0, count: SharedMediaNativeErasureManifestSpool.slotBytes)
            let length = UInt32(encoded.count)
            for part in 0..<4 { bytes[part] = UInt8(truncatingIfNeeded: length >> (part * 8)) }
            bytes.replaceSubrange(4..<(4 + encoded.count), with: encoded)
            let position = try Self.offset(index)
            try bytes.withUnsafeBytes { source in
                var completed = 0
                while completed < source.count {
                    let result = pwrite(descriptor, source.baseAddress!.advanced(by: completed), source.count - completed,
                        position + Int64(completed))
                    if result < 0 && errno == EINTR { continue }
                    guard result > 0 else { throw SharedMediaStorageFailure.unavailable }
                    completed += result
                }
            }
        }
        func read(_ index: Int64, ownerID: UUID) throws -> Manifest.Entry {
            var bytes = Data(repeating: 0, count: SharedMediaNativeErasureManifestSpool.slotBytes)
            let position = try Self.offset(index)
            try bytes.withUnsafeMutableBytes { target in
                var completed = 0
                while completed < target.count {
                    let result = pread(descriptor, target.baseAddress!.advanced(by: completed), target.count - completed,
                        position + Int64(completed))
                    if result < 0 && errno == EINTR { continue }
                    guard result > 0 else { throw SharedMediaStorageFailure.conflict }
                    completed += result
                }
            }
            let length = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[$1]) << ($1 * 8) }
            guard length > 0, Int(length) <= Self.payloadBytes else { throw SharedMediaStorageFailure.conflict }
            let end = 4 + Int(length), payload = bytes.subdata(in: 4..<end)
            guard bytes[end...].allSatisfy({ $0 == 0 }) else { throw SharedMediaStorageFailure.conflict }
            let entry: Manifest.Entry = try SharedMediaAcquisitionEncoding.decode(payload, maximum: Self.payloadBytes)
            try entry.validate(ownerID: ownerID)
            guard try SharedMediaAcquisitionEncoding.encode(entry, maximum: Self.payloadBytes) == payload else {
                throw SharedMediaStorageFailure.conflict
            }
            return entry
        }
        private static var payloadBytes: Int { SharedMediaNativeErasureManifestSpool.slotBytes - 4 }
        private static func offset(_ index: Int64) throws -> Int64 {
            let (result, overflow) = index.multipliedReportingOverflow(by: Int64(SharedMediaNativeErasureManifestSpool.slotBytes))
            guard index >= 0, !overflow, result <= Int64.max - Int64(SharedMediaNativeErasureManifestSpool.slotBytes) else {
                throw SharedMediaStorageFailure.capacity
            }
            return result
        }
    }
}
