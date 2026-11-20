import CryptoKit
import Foundation
import os
import Testing
@testable import Merian

/// Exercises the production descriptor reader; synthetic bytes deliberately
/// bypass image decoding because this boundary verifies bytes, not image format.
@Suite("Original hash loop bounds and interruption", .serialized)
struct PhotoOriginalHashLoopTests {
    struct Fixture {
        let root: URL
        let files: PhotoPreparationLockedFiles
        let url: URL
        let file: PhotoPreparationFile

        init(chunks: Int = 3) throws {
            root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            files = try PhotoPreparationLockedFiles(root: root)
            let asset = UUID(), token = [UUID(), UUID(), asset].map { $0.uuidString.lowercased() }.joined(separator: "/")
            url = root.appendingPathComponent("PhotoPreparation").appendingPathComponent(token)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw PhotoPreparationFailure.unavailable }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            let chunk = Data(repeating: 0x5a, count: 64 * 1024)
            var hash = SHA256()
            for _ in 0..<chunks { try handle.write(contentsOf: chunk); hash.update(data: chunk) }
            try handle.synchronize()
            file = .init(assetID: asset, generation: UUID(), token: token, byteCount: Int64(chunks * chunk.count),
                sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), contentType: "image/jpeg")
        }
        func close() { files.close(); try? FileManager.default.removeItem(at: root) }
    }

    @Test func maximumOriginalUsesBoundedChunksAndRepeats() throws {
        let h = try Fixture(chunks: 512); defer { h.close() }
        #expect(h.file.byteCount == PhotoPreparationPolicy.original)
        let observed = OSAllocatedUnfairLock(initialState: (total: Int64(0), calls: 0))
        h.files.sharedReadFault = { total in
            observed.withLock { state in
                #expect(total - state.total > 0 && total - state.total <= 64 * 1024)
                state.total = total; state.calls += 1
            }
        }
        let first = try h.files.verifiedIdentity(h.file)
        #expect(observed.withLock { $0.total == h.file.byteCount && $0.calls == 512 })
        observed.withLock { $0 = (0, 0) }
        #expect(try h.files.verifiedIdentity(h.file) == first)
        #expect(observed.withLock { $0.total == h.file.byteCount && $0.calls == 512 })
    }

    @Test(arguments: ["truncated", "appended", "modified", "replaced", "missing", "symlink"])
    func mutationInsideReadFailsClosed(_ fault: String) throws {
        let h = try Fixture(); defer { h.close() }
        let url = h.url
        h.files.sharedReadFault = { total in
            guard total == 64 * 1024 else { return }
            if ["replaced", "missing", "symlink"].contains(fault) {
                let retained = url.appendingPathExtension("retained-fixture")
                try FileManager.default.moveItem(at: url, to: retained)
                if fault == "replaced" { try FileManager.default.copyItem(at: retained, to: url) }
                if fault == "symlink" { try FileManager.default.createSymbolicLink(at: url, withDestinationURL: retained) }
            } else {
                let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
                if fault == "truncated" { try handle.truncate(atOffset: 1) }
                else {
                    if fault == "appended" { try handle.seekToEnd() }
                    // Modify an already-hashed byte: final metadata must catch it.
                    try handle.write(contentsOf: Data([0])); try handle.synchronize()
                }
            }
        }
        #expect(throws: PhotoPreparationFailure.self) { _ = try h.files.verifiedIdentity(h.file) }
    }

    @Test(arguments: [Int64(64 * 1024), Int64(3 * 64 * 1024)])
    func cancellationInsideReadStopsBeforeSuccess(_ boundary: Int64) async throws {
        let h = try Fixture(); defer { h.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        h.files.sharedReadFault = { total in
            calls.withLock { $0 += 1 }
            if total == boundary { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let files = h.files, file = h.file
        let task = Task.detached { try files.verifiedIdentity(file) }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(calls.withLock { $0 } == Int(boundary / (64 * 1024)))
        h.files.sharedReadFault = nil
        // The cancelled task has joined; the same locked owner remains usable.
        #expect(try !h.files.verifiedIdentity(h.file).isEmpty)
    }

    @Test func cancellationBeforeReadConsumesNoChunks() async throws {
        let h = try Fixture(); defer { h.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        h.files.sharedReadFault = { _ in calls.withLock { $0 += 1 } }
        let files = h.files, file = h.file
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try files.verifiedIdentity(file)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(calls.withLock { $0 } == 0)
    }
}
