import Darwin
import Foundation
@testable import Merian
import Testing

@Suite("Capture root filesystem journal", .serialized)
@MainActor
struct SharedMediaNativeCaptureRootFilesTests {
    private enum Interrupted: Error { case injected }
    private typealias Journal = SharedMediaCaptureRootJournal
    @MainActor
    private final class Store {
        let parent: URL
        let profile: SharedMediaNativeAppProfile
        init() throws {
            parent = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
                .appendingPathComponent("capture-root-test-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            profile = .init(ownerID: UUID(), inventoryID: UUID(), generation: UUID(), storeIdentity: UUID().uuidString,
                physicalBinding: String(repeating: "a", count: 64), receiptDigest: String(repeating: "b", count: 64),
                physicalBindingFormat: .physicalRootsV1)
        }
        deinit { try? FileManager.default.removeItem(at: parent) }
        func open(create: Bool, fault: ((SharedMediaCaptureRootBoundary) throws -> Void)? = nil) throws -> SharedMediaNativeCaptureRootFiles {
            try .qualification(parent: parent, profile: profile, createOrResume: create, fault: fault)
        }
        func controls() throws -> [String: Data] {
            var result: [String: Data] = [:]
            for name in Journal.names where name != Journal.rootName {
                let url = parent.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { result[name] = try Data(contentsOf: url) }
            }
            return result
        }
    }

    @Test func completedRootReopensWithoutChangingControlsOrBaseProfile() throws {
        let store = try Store(), binding = try store.profile.binding
        var first: SharedMediaNativeCaptureRootFiles? = try store.open(create: true)
        try first?.check()
        let controls = try store.controls()
        #expect(controls.count == 4)
        #expect(throws: (any Error).self) { _ = try store.open(create: false) }
        first = nil
        let second = try store.open(create: false)
        try second.check()
        #expect(try store.controls() == controls)
        #expect(try store.profile.binding == binding)
        let capsule = try second.take()
        #expect(throws: (any Error).self) { _ = try second.take() }
        let rootURL = store.parent.appendingPathComponent(Journal.rootName, isDirectory: true)
        let handles = try capsule.consume(at: rootURL)
        defer { Darwin.close(handles.root); Darwin.close(handles.child) }
        #expect(handles.root >= 0 && handles.child >= 0)
        #expect(throws: (any Error).self) { _ = try capsule.consume(at: rootURL) }
        try second.check()
    }

    @Test(arguments: SharedMediaCaptureRootBoundary.allCases)
    func interruptionRequiresCreationProofAndExplicitContinuation(_ boundary: SharedMediaCaptureRootBoundary) throws {
        let store = try Store()
        #expect(throws: Interrupted.self) {
            _ = try store.open(create: true, fault: { if $0 == boundary { throw Interrupted.injected } })
        }
        let before = try store.controls()
        let ambiguous = boundary == .afterRootDirectory || boundary == .afterNamespaceDirectory
        if boundary != .afterMarker {
            #expect(throws: (any Error).self) { _ = try store.open(create: false) }
            #expect(try store.controls() == before)
        }
        if ambiguous {
            #expect(throws: (any Error).self) { _ = try store.open(create: true) }
            #expect(try store.controls() == before)
        } else {
            var recovered: SharedMediaNativeCaptureRootFiles? = try store.open(create: true)
            try recovered?.check()
            #expect(try store.controls()[Journal.intentName] == before[Journal.intentName])
            recovered = nil
            try store.open(create: false).check()
        }
    }

    @Test(arguments: ["unregistered", "orphanDirectory", "orphanFinal", "symlink"])
    func neverAdoptsUnexpectedParentEntries(_ mutation: String) throws {
        let store = try Store()
        switch mutation {
        case "unregistered": try Data([1]).write(to: store.parent.appendingPathComponent("unknown"))
        case "orphanDirectory":
            try FileManager.default.createDirectory(at: store.parent.appendingPathComponent(Journal.rootName), withIntermediateDirectories: false)
        case "orphanFinal": try Data([1]).write(to: store.parent.appendingPathComponent(Journal.finalName))
        case "symlink":
            try FileManager.default.createSymbolicLink(at: store.parent.appendingPathComponent(Journal.intentName), withDestinationURL: store.parent)
        default: Issue.record("Unknown mutation")
        }
        let before = try FileManager.default.contentsOfDirectory(atPath: store.parent.path)
        #expect(throws: (any Error).self) { _ = try store.open(create: true) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.parent.path) == before)
    }

    @Test func replacementAndControlMutationInvalidateAnOpenOwner() throws {
        let store = try Store(), owner = try store.open(create: true)
        let file = store.parent.appendingPathComponent(Journal.finalName)
        let original = try Data(contentsOf: file)
        try Data([1]).write(to: file)
        #expect(throws: (any Error).self) { try owner.check() }
        try original.write(to: file)
        let root = store.parent.appendingPathComponent(Journal.rootName)
        let moved = store.parent.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: root, to: moved)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { _ = try owner.take() }
    }

    @Test func ownerChangeCannotContinueAnExistingPrefix() throws {
        let store = try Store(), other = try Store()
        #expect(throws: Interrupted.self) {
            _ = try store.open(create: true, fault: { if $0 == .afterIntent { throw Interrupted.injected } })
        }
        let before = try store.controls()
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeCaptureRootFiles.qualification(parent: store.parent, profile: other.profile, createOrResume: true)
        }
        #expect(try store.controls() == before)
    }

    @Test func oversizedControlIsRejectedBeforeJournalDecoding() throws {
        let store = try Store()
        let file = store.parent.appendingPathComponent(Journal.intentName)
        let bytes = Data(repeating: 32, count: Journal.maximumRecordBytes + 1)
        try bytes.write(to: file)
        #expect(throws: (any Error).self) { _ = try store.open(create: true) }
        #expect(try Data(contentsOf: file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: store.parent.appendingPathComponent(Journal.rootName).path))
    }

    @Test(arguments: ["root", "namespace", "marker"])
    func handoffRevalidatesHeldAndNamedDirectories(_ mutation: String) throws {
        let store = try Store(), owner = try store.open(create: true)
        let capsule = try owner.take()
        let root = store.parent.appendingPathComponent(Journal.rootName, isDirectory: true)
        if mutation == "marker" {
            let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            #expect(fd >= 0)
            defer { Darwin.close(fd) }
            #expect(fremovexattr(fd, Journal.marker, 0) == 0)
        } else {
            let target = mutation == "root" ? root : root.appendingPathComponent(Journal.childName)
            try FileManager.default.moveItem(at: target, to: store.parent.appendingPathComponent("moved"))
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        }
        #expect(throws: (any Error).self) { _ = try capsule.consume(at: root) }
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try capsule.consume(at: root) }
    }
}
