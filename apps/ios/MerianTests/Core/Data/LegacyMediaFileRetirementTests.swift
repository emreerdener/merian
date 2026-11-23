import Darwin
import Foundation
@testable import Merian
import Testing

struct LegacyMediaFileRetirementTests {
    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var documents: URL { root.appendingPathComponent("documents") }
        var temporary: URL { root.appendingPathComponent("temporary") }
        init() throws {
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
        func io() -> FileIOActor { FileIOActor(documents: documents, temporaryDirectory: temporary) }
    }

    @Test(arguments: [false, true])
    func exactFileRemovalAndMissingRetryAreIdempotent(temporary: Bool) async throws {
        let h = try Fixture(); defer { h.remove() }
        let path = (temporary ? h.temporary : h.documents).appendingPathComponent("copy.wav")
        try Data(repeating: 7, count: 32).write(to: path)
        let io = h.io(), receipt = try #require(await io.retirementForDisposableFile(at: path.path))
        #expect(await io.retireDisposableFiles([receipt]))
        #expect(!FileManager.default.fileExists(atPath: path.path))
        #expect(await io.retireDisposableFiles([receipt]))
    }

    @Test(arguments: ["replace", "mutate", "symlink", "root"])
    func changedFileOrRootIsPreserved(change: String) async throws {
        let h = try Fixture(); defer { h.remove() }
        let path = h.documents.appendingPathComponent("copy.wav"), bytes = Data(repeating: 7, count: 32)
        try bytes.write(to: path)
        let io = h.io(), receipt = try #require(await io.retirementForDisposableFile(at: path.path))
        switch change {
        case "replace": try bytes.write(to: path, options: .atomic)
        case "mutate":
            let handle = try FileHandle(forWritingTo: path)
            try handle.write(contentsOf: Data([8])); try handle.close()
        case "symlink":
            try FileManager.default.removeItem(at: path)
            let other = h.temporary.appendingPathComponent("other.wav")
            try bytes.write(to: other)
            try FileManager.default.createSymbolicLink(at: path, withDestinationURL: other)
        default:
            try FileManager.default.moveItem(at: h.documents, to: h.root.appendingPathComponent("old-documents"))
            try FileManager.default.createDirectory(at: h.documents, withIntermediateDirectories: false)
            try bytes.write(to: path)
        }
        let preserved = try Data(contentsOf: path)
        #expect(await io.retireDisposableFiles([receipt]) == false)
        #expect(try Data(contentsOf: path) == preserved)
    }

    @Test func failedSyncRetainsProofForAbsentRetry() async throws {
        let h = try Fixture(); defer { h.remove() }
        let path = h.documents.appendingPathComponent("copy.wav")
        try Data(repeating: 7, count: 32).write(to: path)
        let failing = FileIOActor(documents: h.documents, temporaryDirectory: h.temporary,
            copyIO: .init(write: FileIOActor.CopyIO.live.write, synchronize: { _ in -1 }))
        let receipt = try #require(await failing.retirementForDisposableFile(at: path.path))
        #expect(await failing.retireDisposableFiles([receipt]) == false)
        #expect(!FileManager.default.fileExists(atPath: path.path))
        #expect(await h.io().retireDisposableFiles([receipt]))
    }

    @Test func privateDescendantsNeverReceiveDisposableAuthority() async throws {
        let h = try Fixture(); defer { h.remove() }
        let nested = h.documents.appendingPathComponent("capture/CaptureArtifacts")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let path = nested.appendingPathComponent("original")
        try Data([1, 2, 3]).write(to: path)
        #expect(await h.io().retirementForDisposableFile(at: path.path) == nil)
        #expect(try Data(contentsOf: path) == Data([1, 2, 3]))
    }
}
