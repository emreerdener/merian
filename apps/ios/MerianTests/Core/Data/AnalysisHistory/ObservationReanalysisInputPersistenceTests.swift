import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Bounded reanalysis input persistence", .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisInputPersistenceTests {
    private typealias Receipt = ObservationReanalysisInputReceipt
    private typealias Ledger = ObservationReanalysisInputLedger
    private typealias Persistence = ObservationReanalysisInputPersistence
    private enum Fault: Error { case saved }

    private func identity(_ inode: UInt64) -> Receipt.Identity {
        .init(device: 1, inode: inode, birthSeconds: 100, birthNanoseconds: 0)
    }
    private func ledger() throws -> Ledger {
        try Ledger(namespaceGeneration: UUID(), documents: identity(10), namespace: identity(11),
            directories: (12...15).map { identity(UInt64($0)) })
    }
    private func request(_ ledger: Ledger, slot: Int, child: UUID = UUID(), digest: String = String(repeating: "a", count: 64)) throws -> Receipt {
        try Receipt(ownerID: UUID(), parentID: UUID(), childID: child, planDigest: digest,
            documents: ledger.documents, namespace: ledger.namespace, namespaceGeneration: ledger.namespaceGeneration,
            slot: slot, useGeneration: UUID(), directory: ledger.slots[slot].directory)
    }
    private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
    /// Metadata-layer stand-in for already verified absent-file erasure. These
    /// tests do not claim filesystem, account-admission or copy qualification.
    private func complete(_ receipt: Receipt, in container: ModelContainer) throws -> Receipt {
        let retiring = try receipt.retiring(), completed = try retiring.completed()
        _ = try Persistence.advance(from: receipt, to: retiring, container: container, validate: {})
        return try Persistence.advance(from: retiring, to: completed, container: container, validate: {})
    }

    @Test func fourActiveReservationsRejectFifthAndExactReplayDoesNotChargeAgain() throws {
        let store = try container(), baseline = try ledger()
        try Persistence.initialize(baseline, container: store, validate: { _ in })
        var active: [Receipt] = []
        for slot in 0..<4 {
            let receipt = try request(baseline, slot: slot)
            active.append(try Persistence.reserve(receipt, container: store, validate: { _ in }))
        }
        #expect(try Persistence.reserve(active[0], container: store, validate: { _ in }) == active[0])
        #expect(throws: (any Error).self) {
            _ = try Persistence.reserve(request(baseline, slot: 0), container: store, validate: { _ in })
        }
        let snapshot = try Persistence.inspect(container: store)
        #expect(snapshot.receipts == active.map(Optional.some))
        #expect(snapshot.ledger.slots.allSatisfy { $0.state == .active })
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 5)
    }

    @Test func staleCompletionCannotReleaseReusedSlotOrResurrectOldChild() throws {
        let store = try container(), baseline = try ledger()
        try Persistence.initialize(baseline, container: store, validate: { _ in })
        let original = try request(baseline, slot: 0)
        _ = try Persistence.reserve(original, container: store, validate: { _ in })
        let completed = try complete(original, in: store)
        let successor = try request(baseline, slot: 0)
        _ = try Persistence.reserve(successor, container: store, validate: { _ in })
        #expect(try Persistence.advance(from: original.retiring(), to: completed, container: store, validate: {}) == completed)
        #expect(try Persistence.reserve(original, container: store, validate: { _ in }) == completed)
        #expect(try Persistence.read(child: original.childID, container: store) == completed)
        let snapshot = try Persistence.inspect(container: store)
        #expect(snapshot.receipts[0] == successor)
        #expect(snapshot.ledger.slots[0].state == .active)
        #expect(snapshot.ledger.slots[0].useGeneration == successor.useGeneration)
        #expect(throws: (any Error).self) {
            _ = try Persistence.advance(from: completed, to: original, container: store, validate: {})
        }
    }

    @Test(arguments: ["missing", "status", "metadata", "ownerKind", "generation", "releasedWithoutCompletion"])
    func activeGraphDamageCannotManufactureFreeCapacity(fault: String) throws {
        let store = try container(), baseline = try ledger()
        try Persistence.initialize(baseline, container: store, validate: { _ in })
        let original = try request(baseline, slot: 0)
        _ = try Persistence.reserve(original, container: store, validate: { _ in })
        let context = ModelContext(store)
        let row = try #require(try context.fetchOfflineJob(id: original.jobID))
        switch fault {
        case "missing": context.delete(row)
        case "status": row.status = .complete
        case "metadata": row.metadataJSON = "not-json"
        case "ownerKind": row.kind = .future
        case "generation":
            var object = try #require(JSONSerialization.jsonObject(with: Data(try original.encoded().utf8)) as? [String: Any])
            object["useGeneration"] = UUID().uuidString
            row.metadataJSON = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        default:
            let control = try #require(try context.fetchOfflineJob(id: Ledger.jobID))
            let controlText = try #require(control.metadataJSON)
            var object = try #require(JSONSerialization.jsonObject(with: Data(controlText.utf8)) as? [String: Any])
            var slots = try #require(object["slots"] as? [[String: Any]])
            slots[0]["state"] = "released"; object["slots"] = slots
            control.metadataJSON = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        }
        try context.save()
        #expect(throws: (any Error).self) { _ = try Persistence.inspect(container: store) }
        #expect(throws: (any Error).self) {
            _ = try Persistence.reserve(request(baseline, slot: 1), container: store, validate: { _ in })
        }
    }

    @Test func completedHistoryIsNotTheActiveAdmissionIndex() throws {
        let store = try container(), baseline = try ledger()
        try Persistence.initialize(baseline, container: store, validate: { _ in })
        var oldest: Receipt?
        for _ in 0..<24 {
            let receipt = try request(baseline, slot: 0)
            _ = try Persistence.reserve(receipt, container: store, validate: { _ in })
            let completed = try complete(receipt, in: store)
            if oldest == nil { oldest = completed }
        }
        let historical = try #require(oldest), context = ModelContext(store)
        let row = try #require(try context.fetchOfflineJob(id: historical.jobID))
        row.metadataJSON = "damaged obsolete replay record"
        try context.save()
        let successor = try request(baseline, slot: 0)
        _ = try Persistence.reserve(successor, container: store, validate: { _ in })
        #expect(try Persistence.inspect(container: store).receipts[0] == successor)
        #expect(throws: (any Error).self) { _ = try Persistence.read(child: historical.childID, container: store) }
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 26)
    }

    @Test func existingOwnershipPreventsFreshInitialization() throws {
        let store = try container(), baseline = try ledger(), context = ModelContext(store)
        context.insert(OfflineJobRecord(id: Receipt.prefix + UUID().uuidString.lowercased(), kind: .future,
            status: .complete, metadataJSON: "unrecognized ownership"))
        try context.save()
        #expect(throws: (any Error).self) {
            try Persistence.initialize(baseline, container: store, validate: { _ in })
        }
        #expect(try ModelContext(store).fetchOfflineJob(id: Ledger.jobID) == nil)
    }

    @Test func inputMetadataCannotAuthorizeWholeChildErasure() throws {
        let store = try container(), baseline = try ledger()
        try Persistence.initialize(baseline, container: store, validate: { _ in })
        let original = try request(baseline, slot: 0)
        _ = try Persistence.reserve(original, container: store, validate: { _ in })
        let context = ModelContext(store)
        for id in [Ledger.jobID, original.jobID] {
            let row = try #require(try context.fetchOfflineJob(id: id))
            #expect(throws: (any Error).self) { _ = try ObservationReanalysisErasureReceipt.restore(row) }
        }
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test func uncertainReservationAndReleaseReconcileAcrossDiskReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("inputs.store"), baseline = try ledger(), original = try request(baseline, slot: 0)
        try autoreleasepool {
            let store = try container(url: url)
            try Persistence.initialize(baseline, container: store, validate: { _ in })
            #expect(throws: Fault.self) {
                _ = try Persistence.reserve(original, container: store, validate: { _ in }, save: { try $0.save(); throw Fault.saved })
            }
        }
        let retiring = try original.retiring(), completed = try retiring.completed()
        try autoreleasepool {
            let store = try container(url: url)
            #expect(try Persistence.reserve(original, container: store, validate: { _ in }) == original)
            #expect(try Persistence.inspect(container: store).receipts[0] == original)
            _ = try Persistence.advance(from: original, to: retiring, container: store, validate: {})
            #expect(throws: Fault.self) {
                _ = try Persistence.advance(from: retiring, to: completed, container: store, validate: {}, save: { try $0.save(); throw Fault.saved })
            }
        }
        try autoreleasepool {
            let store = try container(url: url)
            #expect(try Persistence.advance(from: retiring, to: completed, container: store, validate: {}) == completed)
            #expect(try Persistence.inspect(container: store).ledger.slots[0].state == .released)
            let successor = try request(baseline, slot: 0)
            _ = try Persistence.reserve(successor, container: store, validate: { _ in })
            #expect(try Persistence.advance(from: retiring, to: completed, container: store, validate: {}) == completed)
            #expect(try Persistence.inspect(container: store).receipts[0] == successor)
        }
    }

    @Test func bootstrapSaveUncertaintyAndIdentityMismatchRemainClosed() throws {
        let store = try container(), baseline = try ledger()
        #expect(throws: Fault.self) {
            try Persistence.initialize(baseline, container: store, validate: { _ in }, save: { try $0.save(); throw Fault.saved })
        }
        try Persistence.initialize(baseline, container: store, validate: { _ in })
        #expect(try Persistence.inspect(container: store).ledger == baseline)
        #expect(throws: (any Error).self) {
            try Persistence.initialize(ledger(), container: store, validate: { _ in })
        }
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test(arguments: [false, true])
    func failedSaveOrFinalValidationRollsBackReservationAndRelease(finalValidation: Bool) throws {
        let store = try container(), baseline = try ledger(), original = try request(baseline, slot: 0)
        try Persistence.initialize(baseline, container: store, validate: { _ in })
        var checks = 0, saves = 0
        #expect(throws: Fault.self) {
            _ = try Persistence.reserve(original, container: store, validate: { _ in
                checks += 1
                if finalValidation && checks == 2 { throw Fault.saved }
            }, save: { _ in saves += 1; throw Fault.saved })
        }
        #expect(checks == 2)
        #expect(saves == (finalValidation ? 0 : 1))
        #expect(try Persistence.inspect(container: store).ledger == baseline)
        #expect(try Persistence.read(child: original.childID, container: store) == nil)
        _ = try Persistence.reserve(original, container: store, validate: { _ in })
        let retiring = try original.retiring(), completed = try retiring.completed()
        _ = try Persistence.advance(from: original, to: retiring, container: store, validate: {})
        checks = 0; saves = 0
        #expect(throws: Fault.self) {
            _ = try Persistence.advance(from: retiring, to: completed, container: store, validate: {
                checks += 1
                if finalValidation && checks == 2 { throw Fault.saved }
            }, save: { _ in saves += 1; throw Fault.saved })
        }
        #expect(checks == 2)
        #expect(saves == (finalValidation ? 0 : 1))
        let state = try Persistence.inspect(container: store)
        #expect(state.receipts[0] == retiring)
        #expect(state.ledger.slots[0].state == .active)
    }

    @Test(arguments: ["ownerID", "parentID", "planDigest", "slot", "useGeneration", "namespaceGeneration"])
    func changedSameChildReplayDoesNotMutateAuthority(field: String) throws {
        let store = try container(), baseline = try ledger(), original = try request(baseline, slot: 0)
        try Persistence.initialize(baseline, container: store, validate: { _ in })
        _ = try Persistence.reserve(original, container: store, validate: { _ in })
        var value = try #require(JSONSerialization.jsonObject(with: Data(try original.encoded().utf8)) as? [String: Any])
        if field == "slot" { value[field] = 1 }
        else if field == "planDigest" { value[field] = String(repeating: "b", count: 64) }
        else { value[field] = UUID().uuidString }
        let changed = try Receipt.decode(String(decoding: JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self))
        #expect(throws: (any Error).self) {
            _ = try Persistence.reserve(changed, container: store, validate: { _ in })
        }
        #expect(try Persistence.read(child: original.childID, container: store) == original)
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 2)
    }

    @Test(arguments: ["missingControl", "corruptControl", "initialWithChild", "missingCompletion", "corruptCompletion"])
    func brokenControlOrReleasedProofCannotAuthorizeAdmission(fault: String) throws {
        let store = try container(), baseline = try ledger(), original = try request(baseline, slot: 0)
        try Persistence.initialize(baseline, container: store, validate: { _ in })
        if fault.hasSuffix("Completion") {
            _ = try Persistence.reserve(original, container: store, validate: { _ in })
            _ = try complete(original, in: store)
        }
        let context = ModelContext(store)
        let control = try #require(try context.fetchOfflineJob(id: Ledger.jobID))
        switch fault {
        case "missingControl": context.delete(control)
        case "corruptControl": control.metadataJSON = "invalid"
        case "initialWithChild":
            let text = try #require(control.metadataJSON)
            var value = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            var slots = try #require(value["slots"] as? [[String: Any]])
            slots[0]["childID"] = original.childID.uuidString; value["slots"] = slots
            control.metadataJSON = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
        default:
            let row = try #require(try context.fetchOfflineJob(id: original.jobID))
            if fault == "missingCompletion" { context.delete(row) }
            else { row.metadataJSON = "invalid completion" }
        }
        try context.save()
        #expect(throws: (any Error).self) { _ = try Persistence.inspect(container: store) }
        #expect(throws: (any Error).self) {
            _ = try Persistence.reserve(request(baseline, slot: 1), container: store, validate: { _ in })
        }
    }
}
