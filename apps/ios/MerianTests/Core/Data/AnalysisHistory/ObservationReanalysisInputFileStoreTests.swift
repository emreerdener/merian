import Darwin
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Fixed-slot reanalysis input files", .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisInputFileStoreTests {
    typealias Receipt = ObservationReanalysisInputReceipt
    private typealias Persistence = ObservationReanalysisInputPersistence
    private typealias Store = ObservationReanalysisFileStore
    private enum Fault: Error { case saved }

    /// Real filesystem component fixture; empty validators intentionally stand
    /// in for separately required startup/account/source integration tests.
    @MainActor private final class Fixture {
        let root: URL
        let store: Store
        let container: ModelContainer
        let fileIO: FileIOActor
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            store = Store(documents: root)
            fileIO = FileIOActor(documents: root, temporaryDirectory: root)
            try Data(repeating: 17, count: 1024).write(to: root.appendingPathComponent("selected.mp4"))
            let schema = Schema(CurrentSchema.models)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        func initialize(failAfterSave: Bool = false) async throws {
            try await store.initializeInputs(readState: { try Persistence.inspectForFreshPreparation(container: self.container) },
                commit: {
                    try Persistence.initialize($0, container: self.container, validate: { _ in })
                    if failAfterSave { throw Fault.saved }
                }, validate: {})
        }
        func copy(child: UUID = UUID(), failAfter: Receipt.Phase? = nil, failBefore: Receipt.Phase? = nil,
                  copyBytes: (@Sendable (Int32) async -> Bool)? = nil) async throws -> Store.InputToken {
            try await store.createInput(.init(ownerID: UUID(), parentID: UUID(), childID: child,
                planDigest: String(repeating: "a", count: 64)),
                inspect: { try Persistence.inspect(container: self.container) },
                reserve: { try Persistence.reserve($0, container: self.container, validate: { _ in }) },
                advance: { before, next in
                    if next.phase == failBefore { throw Fault.saved }
                    let saved = try Persistence.advance(from: before, to: next, container: self.container, validate: {})
                    if next.phase == failAfter { throw Fault.saved }
                    return saved
                }, validate: {}, copy: copyBytes ?? { [fileIO] descriptor in
                    await fileIO.copyVideoInput(filename: "selected.mp4", ownedOutput: descriptor)
                })
        }
        func erase(_ token: Store.InputToken, failAfter: Receipt.Phase? = nil) async throws {
            try await store.eraseInput(child: token.receipt.childID, token: token,
                read: { try #require(try Persistence.read(child: token.receipt.childID, container: self.container)) },
                advance: { before, next in
                    let saved = try Persistence.advance(from: before, to: next, container: self.container, validate: {})
                    if next.phase == failAfter { throw Fault.saved }
                    return saved
                })
        }
        func coldErase(_ child: UUID) async throws {
            let reader = Store(documents: root)
            try await reader.eraseInput(child: child,
                read: { try #require(try Persistence.read(child: child, container: self.container)) },
                advance: { try Persistence.advance(from: $0, to: $1, container: self.container, validate: {}) })
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func runtimeLeaseReleaseKeepsOwnershipAndRequiresExactToken() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        let token = try await fixture.copy()
        let foreign = Store.InputToken(id: UUID(), receipt: token.receipt, url: token.url)
        #expect(await fixture.store.releaseInputLease(foreign) == false)
        await #expect(throws: (any Error).self) { try await fixture.coldErase(token.receipt.childID) }
        #expect(await fixture.store.releaseInputLease(token))
        #expect(try Persistence.read(child: token.receipt.childID, container: fixture.container) == token.receipt)
        #expect(try Data(contentsOf: token.url) == Data(repeating: 17, count: 1024))
        try await fixture.coldErase(token.receipt.childID)
        #expect(try Persistence.read(child: token.receipt.childID, container: fixture.container)?.phase == .complete)
    }

    @Test func fourCopiesHaveBoundedDirectoriesAndCompletedReplayCannotEraseSuccessor() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        var tokens: [Store.InputToken] = []
        for _ in 0..<4 { tokens.append(try await fixture.copy()) }
        await #expect(throws: (any Error).self) { _ = try await fixture.copy() }
        let namespace = fixture.root.appendingPathComponent("ReanalysisInputs")
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: namespace.path)) == Set(["0", "1", "2", "3"]))
        try await fixture.erase(tokens[0])
        let successor = try await fixture.copy()
        #expect(successor.receipt.slot == tokens[0].receipt.slot)
        #expect(successor.receipt.useGeneration != tokens[0].receipt.useGeneration)
        try await fixture.erase(tokens[0])
        #expect(try Data(contentsOf: successor.url) == Data(repeating: 17, count: 1024))
        #expect(try Persistence.inspect(container: fixture.container).receipts[successor.receipt.slot] == successor.receipt)
        try await fixture.erase(successor)
        for token in tokens.dropFirst() { try await fixture.erase(token) }
    }

    @Test func existingNamespaceWithoutBaselineNeverBootstrapsOrAdoptsFiles() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let namespace = fixture.root.appendingPathComponent("ReanalysisInputs")
        try FileManager.default.createDirectory(at: namespace, withIntermediateDirectories: false)
        let marker = namespace.appendingPathComponent("unowned")
        try Data([1]).write(to: marker)
        await #expect(throws: (any Error).self) { try await fixture.initialize() }
        #expect(try Data(contentsOf: marker) == Data([1]))
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func missingPhysicalNamespaceWithSurvivingLedgerNeverCreatesReplacement() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        let namespace = fixture.root.appendingPathComponent("ReanalysisInputs")
        try FileManager.default.moveItem(at: namespace, to: fixture.root.appendingPathComponent("retained-original"))
        await #expect(throws: (any Error).self) { try await fixture.initialize() }
        #expect(!FileManager.default.fileExists(atPath: namespace.path))
    }

    @Test func backlogCannotDisplaceLiveInputLease() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        let token = try await fixture.copy(), competitor = Store(documents: fixture.root)
        await #expect(throws: (any Error).self) {
            try await competitor.eraseInput(child: token.receipt.childID,
                read: { try #require(try Persistence.read(child: token.receipt.childID, container: fixture.container)) },
                advance: { try Persistence.advance(from: $0, to: $1, container: fixture.container, validate: {}) })
        }
        #expect(try Persistence.read(child: token.receipt.childID, container: fixture.container) == token.receipt)
        #expect(try Data(contentsOf: token.url).count == 1024)
        try await fixture.erase(token)
    }

    @Test func fullLibraryPurgeWaitsForLiveLeaseAndRemovesBothNamespaces() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        let token = try await fixture.copy(), purge = Store(documents: fixture.root)
        let queue = fixture.root.appendingPathComponent("ReanalysisQueue/orphan")
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        try Data([9]).write(to: queue.appendingPathComponent("retained"))
        await #expect(throws: (any Error).self) { try await purge.purgeNamespace() }
        #expect(FileManager.default.fileExists(atPath: token.url.path))
        try await fixture.erase(token)
        // Stand-in for the existing authorized outer journal's row-first purge;
        // this component test does not qualify Auth/destination publication.
        let context = ModelContext(fixture.container)
        try context.delete(model: OfflineJobRecord.self); try context.save()
        try await purge.purgeNamespace()
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("ReanalysisInputs").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("ReanalysisQueue").path))
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent("selected.mp4")).count == 1024)
        try await purge.purgeNamespace()
    }

    @Test func committedBootstrapUncertaintyReusesExactPhysicalBaseline() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        await #expect(throws: Fault.self) { try await fixture.initialize(failAfterSave: true) }
        let original = try Persistence.inspect(container: fixture.container).ledger
        try await fixture.initialize()
        #expect(try Persistence.inspect(container: fixture.container).ledger == original)
        let token = try await fixture.copy(); try await fixture.erase(token)
    }

    @Test(arguments: [Receipt.Phase.fileBound, .copied])
    func committedCopyPhaseUncertaintyRetainsColdCleanupAuthority(phase: Receipt.Phase) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        let child = UUID()
        await #expect(throws: Fault.self) { _ = try await fixture.copy(child: child, failAfter: phase) }
        let receipt = try #require(try Persistence.read(child: child, container: fixture.container))
        #expect(receipt.phase == phase)
        if phase == .copied {
            let reader = Store(documents: fixture.root)
            let recovered = try await reader.recoverInput(receipt,
                read: { try #require(try Persistence.read(child: child, container: fixture.container)) })
            #expect(try Data(contentsOf: recovered.url).count == 1024)
            try await reader.eraseInput(child: child, token: recovered,
                read: { try #require(try Persistence.read(child: child, container: fixture.container)) },
                advance: { try Persistence.advance(from: $0, to: $1, container: fixture.container, validate: {}) })
        } else { try await fixture.coldErase(child) }
        #expect(try Persistence.read(child: child, container: fixture.container)?.phase == .complete)
        #expect(try Persistence.inspect(container: fixture.container).ledger.slots[receipt.slot].state == .released)
    }

    @Test(arguments: [Receipt.Phase.erasing, .complete])
    func committedCleanupUncertaintyReconcilesBeforeReuse(phase: Receipt.Phase) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        let token = try await fixture.copy()
        await #expect(throws: Fault.self) { try await fixture.erase(token, failAfter: phase) }
        #expect(try Persistence.read(child: token.receipt.childID, container: fixture.container)?.phase == phase)
        try await fixture.erase(token)
        let successor = try await fixture.copy()
        try await fixture.erase(token)
        #expect(try Data(contentsOf: successor.url).count == 1024)
        try await fixture.erase(successor)
    }

    @Test func partialWriteFailureRetainsChargeUntilColdCleanup() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        let child = UUID()
        await #expect(throws: (any Error).self) {
            _ = try await fixture.copy(child: child, copyBytes: { descriptor in
                let bytes = Data(repeating: 3, count: 65_536)
                _ = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
                return false
            })
        }
        let receipt = try #require(try Persistence.read(child: child, container: fixture.container))
        #expect(receipt.phase == .fileBound)
        let path = fixture.root.appendingPathComponent("ReanalysisInputs/\(receipt.slot)/input.mp4")
        #expect(try Data(contentsOf: path).count == 65_536)
        #expect(try Persistence.inspect(container: fixture.container).ledger.slots[receipt.slot].state == .active)
        try await fixture.coldErase(child)
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test(arguments: ["mutation", "fileReplacement", "fileSymlink", "hardLink", "slotReplacement", "namespaceReplacement", "rootReplacement"])
    func substitutedOrMutatedInputRemainsHeld(fault: String) async throws {
        let fixture = try Fixture()
        var displacedRoot: URL?
        defer {
            fixture.remove()
            if let displacedRoot { try? FileManager.default.removeItem(at: displacedRoot) }
        }
        try await fixture.initialize()
        let token = try await fixture.copy()
        switch fault {
        case "mutation":
            let file = try FileHandle(forWritingTo: token.url); try file.write(contentsOf: Data([99])); try file.close()
        case "fileReplacement", "fileSymlink":
            try FileManager.default.moveItem(at: token.url, to: token.url.appendingPathExtension("original"))
            if fault == "fileSymlink" {
                try FileManager.default.createSymbolicLink(at: token.url, withDestinationURL: fixture.root.appendingPathComponent("selected.mp4"))
            } else { try Data([8]).write(to: token.url) }
        case "hardLink":
            try FileManager.default.linkItem(at: token.url, to: token.url.appendingPathExtension("link"))
        default:
            let original: URL = fault == "slotReplacement" ? token.url.deletingLastPathComponent()
                : fault == "namespaceReplacement" ? fixture.root.appendingPathComponent("ReanalysisInputs") : fixture.root
            let displaced = original.appendingPathExtension("retained")
            try FileManager.default.moveItem(at: original, to: displaced)
            if fault == "rootReplacement" { displacedRoot = displaced }
            try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        }
        await #expect(throws: (any Error).self) { try await fixture.erase(token) }
        #expect(try Persistence.read(child: token.receipt.childID, container: fixture.container)?.phase == .copied)
        #expect(try Persistence.inspect(container: fixture.container).ledger.slots[token.receipt.slot].state == .active)
    }

    @Test func maximumInputBytesStayWithinFourSlotCharge() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        let maximum = ScanMediaPayloadPolicy.maxSavedVideoBytes
        try Data(repeating: 11, count: maximum).write(to: fixture.root.appendingPathComponent("selected.mp4"))
        var tokens: [Store.InputToken] = []
        for _ in 0..<4 { tokens.append(try await fixture.copy()) }
        let actual = try tokens.reduce(Int64(0)) { total, token in
            let attributes = try FileManager.default.attributesOfItem(atPath: token.url.path)
            return total + ((attributes[.size] as? NSNumber)?.int64Value ?? -1)
        }
        #expect(actual == Int64(4 * maximum))
        for token in tokens { try await fixture.erase(token) }
        let namespace = fixture.root.appendingPathComponent("ReanalysisInputs")
        for index in 0..<4 {
            #expect(try FileManager.default.contentsOfDirectory(atPath: namespace.appendingPathComponent(String(index)).path).isEmpty)
        }
        print("REANALYSIS_INPUT_STORAGE activeBytes=\(actual) afterCleanupBytes=0 slotDirectories=4")
    }

    @Test func emptyFileBeforeIdentitySaveRemainsChargedAndCannotBeAdopted() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        let child = UUID()
        await #expect(throws: Fault.self) { _ = try await fixture.copy(child: child, failBefore: .fileBound) }
        let receipt = try #require(try Persistence.read(child: child, container: fixture.container))
        #expect(receipt.phase == .reserved)
        #expect(receipt.file == nil)
        let path = fixture.root.appendingPathComponent("ReanalysisInputs/\(receipt.slot)/input.mp4")
        #expect(try Data(contentsOf: path).isEmpty)
        await #expect(throws: (any Error).self) { try await fixture.coldErase(child) }
        #expect(try Persistence.inspect(container: fixture.container).ledger.slots[receipt.slot].state == .active)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    private actor Signal {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            opened = true
            let pending = waiters; waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    @Test(arguments: [false, true])
    func cleanupCannotWinDuringCopyAndCancellationWaitsForActualExit(cancel: Bool) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try await fixture.initialize()
        let child = UUID(), started = Signal(), resume = Signal()
        let task = Task { @MainActor in
            do {
                return try await fixture.copy(child: child, copyBytes: { descriptor in
                    let bytes = Data(repeating: 5, count: 1024)
                    let written = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
                    await started.open(); await resume.wait()
                    return written == bytes.count && !Task.isCancelled
                })
            } catch {
                await started.open()
                throw error
            }
        }
        defer { task.cancel(); Task { await resume.open() } }
        await started.wait()
        if cancel { task.cancel() }
        await #expect(throws: (any Error).self) { try await fixture.coldErase(child) }
        #expect(try Persistence.read(child: child, container: fixture.container)?.phase == .fileBound)
        await resume.open()
        switch await task.result {
        case let .success(token):
            #expect(!cancel)
            try await fixture.erase(token)
        case .failure:
            #expect(cancel)
            try await fixture.coldErase(child)
        }
        #expect(try Persistence.read(child: child, container: fixture.container)?.phase == .complete)
    }
}
