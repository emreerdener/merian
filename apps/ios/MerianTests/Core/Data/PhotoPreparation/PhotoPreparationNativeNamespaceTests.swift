import Darwin
import Foundation
import Testing
@testable import Merian

@MainActor
@Suite("Native photo namespace traversal")
struct PhotoPreparationNativeNamespaceTests {
    @Test func streamsBeyondLegacyCapAndRepeatsWithoutRetainingTokens() async throws {
        let h = try Fixture(); defer { h.close() }
        for _ in 0..<300 { try h.add() }
        for _ in 0..<2 {
            var count = 0
            try await h.visit { @MainActor leaf in count += 1; #expect(leaf.byteCount == 1); #expect(leaf.descriptor.split(separator: ":").count == 7) }
            #expect(count == 300)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: h.parent.path)
        let tokens = Set(names.map { h.prefix + $0 })
        #expect(throws: PhotoPreparationFailure.self) {
            try PhotoPreparationDirectoryInspection().checkInventory(namespaceFD: h.fd, knownTokens: tokens)
        }
    }

    @Test func emptyCanonicalAncestorsRemainUntouched() async throws {
        let h = try Fixture(); defer { h.close() }
        try await h.visit { _ in Issue.record("Unexpected leaf") }
        #expect(FileManager.default.fileExists(atPath: h.parent.path))
    }

    @Test(arguments: ["ancestor", "leaf", "uppercase", "depth", "symlink", "hardlink", "fifo", "both", "siblingLink", "zeroFinal", "oversize"])
    func rejectsUnownedShapes(_ change: String) async throws {
        let h = try Fixture(); defer { h.close() }
        let file = try h.add()
        switch change {
        case "ancestor": try FileManager.default.createDirectory(at: h.root.appendingPathComponent("unknown"), withIntermediateDirectories: false)
        case "leaf": try Data([1]).write(to: h.parent.appendingPathComponent("unknown"))
        case "uppercase": try Data([1]).write(to: h.parent.appendingPathComponent("AAAAAAAA-AAAA-4AAA-AAAA-AAAAAAAAAAAA"))
        case "depth": try FileManager.default.createDirectory(at: h.parent.appendingPathComponent(UUID().uuidString.lowercased()), withIntermediateDirectories: false)
        case "symlink": try FileManager.default.createSymbolicLink(at: h.parent.appendingPathComponent(UUID().uuidString.lowercased()), withDestinationURL: file)
        case "hardlink": try FileManager.default.linkItem(at: file, to: h.parent.appendingPathComponent(UUID().uuidString.lowercased()))
        case "fifo": #expect(mkfifo(h.parent.appendingPathComponent(UUID().uuidString.lowercased()).path, 0o600) == 0)
        case "both": try Data().write(to: URL(fileURLWithPath: file.path + ".partial"))
        case "siblingLink": try FileManager.default.createSymbolicLink(atPath: file.path + ".partial", withDestinationPath: file.path)
        case "zeroFinal": try h.overwrite(file, bytes: [])
        default:
            let fd = open(file.path, O_WRONLY); defer { Darwin.close(fd) }
            #expect(fd >= 0 && ftruncate(fd, PhotoPreparationPolicy.original + 1) == 0)
        }
        await #expect(throws: PhotoPreparationFailure.self) { try await h.visit { _ in } }
    }

    @Test func zeroPartialIsOnlyAStructuralObservation() async throws {
        let h = try Fixture(); defer { h.close() }
        let file = h.parent.appendingPathComponent(UUID().uuidString.lowercased() + ".partial")
        try Data().write(to: file)
        var count = 0
        try await h.visit { @MainActor leaf in count += 1; #expect(leaf.byteCount == 0 && leaf.token.hasSuffix(".partial")) }
        #expect(count == 1) // No receipt phase or writer closure is established.
    }

    @Test(arguments: ["contents", "replacement", "ancestor", "sibling", "directoryAddition"])
    func rejectsMutationDuringObserver(_ change: String) async throws {
        let h = try Fixture(); defer { h.close() }
        let file = try h.add()
        await #expect(throws: PhotoPreparationFailure.self) {
            try await h.visit { _ in
                switch change {
                case "contents": try h.overwrite(file, bytes: [2, 3])
                case "replacement":
                    try FileManager.default.removeItem(at: file); try Data([1]).write(to: file)
                case "ancestor":
                    let moved = h.parent.appendingPathExtension("moved")
                    try FileManager.default.moveItem(at: h.parent, to: moved)
                    try FileManager.default.createDirectory(at: h.parent, withIntermediateDirectories: false)
                case "sibling": try Data().write(to: URL(fileURLWithPath: file.path + ".partial"))
                default: try FileManager.default.createDirectory(at: h.root.appendingPathComponent(UUID().uuidString.lowercased()), withIntermediateDirectories: false)
                }
            }
        }
    }

    @Test func priorLeafMutationIsNotClaimedAsAnAtomicSnapshot() async throws {
        let h = try Fixture(); defer { h.close() }
        try h.add(); try h.add()
        var first: URL?, count = 0
        try await h.visit { @MainActor leaf in
            count += 1
            if let first { try h.overwrite(first, bytes: [2]) }
            else { first = h.root.appendingPathComponent(leaf.token) }
        }
        #expect(count == 2)
        // An uncooperative writer changed an already-observed inode. The whole
        // owner must hold its writer fence and revalidate exact bytes before use.
        #expect(try Data(contentsOf: #require(first)) == Data([2]))
    }

    @Test func enumerationAndObserverErrorsInvalidateTraversal() async throws {
        let h = try Fixture(); defer { h.close() }
        try h.add()
        await #expect(throws: PhotoPreparationFailure.self) {
            try await PhotoPreparationDirectoryInspection(failing: .inventory).visitNative(namespaceFD: h.fd, revalidate: {}) { _ in }
        }
        await #expect(throws: PhotoPreparationFailure.self) {
            try await h.visit { _ in throw PhotoPreparationFailure.unavailable }
        }
        await #expect(throws: PhotoPreparationFailure.self) {
            try await PhotoPreparationDirectoryInspection().visitNative(namespaceFD: h.fd, revalidate: { throw PhotoPreparationFailure.unavailable }) { _ in }
        }
    }

    @Test(arguments: [false, true]) func cancellationRejectsEmptyOrObservedWalk(_ inObserver: Bool) async throws {
        let h = try Fixture(); defer { h.close() }
        if inObserver { try h.add() }
        let task = Task {
            if !inObserver { withUnsafeCurrentTask { $0?.cancel() } }
            try await h.visit { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(arguments: ["cancel", "replacement", "ancestor"])
    func suspendedObserverRetainsBackpressureAndRechecksAfterAwait(_ change: String) async throws {
        let h = try Fixture(); defer { h.close() }
        try h.add(); try h.add()
        let pause = ObserverPause()
        var visits = 0, completed = false
        let task = Task { @MainActor in
            defer { completed = true }
            try await h.visit { @MainActor leaf in
                visits += 1
                await pause.suspend(leaf)
            }
        }
        let leaf = await pause.waitForEntry()
        #expect(visits == 1 && !completed)
        switch change {
        case "cancel": task.cancel()
        case "replacement":
            let file = h.root.appendingPathComponent(leaf.token)
            try FileManager.default.removeItem(at: file)
            try Data([1]).write(to: file)
        default:
            try FileManager.default.moveItem(at: h.parent, to: h.parent.appendingPathExtension("moved"))
            try FileManager.default.createDirectory(at: h.parent, withIntermediateDirectories: false)
        }
        // Cancellation is a request, not observer termination. The caller still
        // owns its traversal until the suspended observer actually returns.
        await Task.yield()
        #expect(visits == 1 && !completed)
        pause.resume()
        if change == "cancel" {
            await #expect(throws: CancellationError.self) { try await task.value }
        } else {
            await #expect(throws: PhotoPreparationFailure.self) { try await task.value }
        }
        #expect(completed && visits == 1)
    }

    @MainActor private final class ObserverPause {
        private var leaf: PhotoPreparationNativeLeaf?
        private var entry: CheckedContinuation<PhotoPreparationNativeLeaf, Never>?
        private var release: CheckedContinuation<Void, Never>?
        func suspend(_ value: PhotoPreparationNativeLeaf) async {
            await withCheckedContinuation { continuation in
                release = continuation; leaf = value
                entry?.resume(returning: value); entry = nil
            }
        }
        func waitForEntry() async -> PhotoPreparationNativeLeaf {
            if let leaf { return leaf }
            return await withCheckedContinuation { entry = $0 }
        }
        func resume() { release?.resume(); release = nil }
    }

    private struct Fixture: Sendable {
        let root: URL
        let parent: URL
        let prefix: String
        let fd: Int32
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("native-namespace-" + UUID().uuidString)
            prefix = UUID().uuidString.lowercased() + "/" + UUID().uuidString.lowercased() + "/"
            parent = root.appendingPathComponent(prefix)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw PhotoPreparationFailure.unavailable }
        }
        @discardableResult func add() throws -> URL {
            let file = parent.appendingPathComponent(UUID().uuidString.lowercased())
            try Data([1]).write(to: file); return file
        }
        func visit(_ body: @Sendable (PhotoPreparationNativeLeaf) async throws -> Void) async throws {
            try await PhotoPreparationDirectoryInspection().visitNative(namespaceFD: fd, revalidate: {}, observe: body)
        }
        func overwrite(_ file: URL, bytes: [UInt8]) throws {
            let fileFD = open(file.path, O_WRONLY | O_TRUNC | O_NOFOLLOW)
            guard fileFD >= 0 else { throw PhotoPreparationFailure.unavailable }
            defer { Darwin.close(fileFD) }
            guard bytes.withUnsafeBytes({ Darwin.write(fileFD, $0.baseAddress, bytes.count) }) == bytes.count else {
                throw PhotoPreparationFailure.unavailable
            }
        }
        func close() { Darwin.close(fd); try? FileManager.default.removeItem(at: root) }
    }
}
