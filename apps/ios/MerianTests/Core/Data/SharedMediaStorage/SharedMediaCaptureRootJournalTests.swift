import Foundation
@testable import Merian
import Testing

@MainActor
struct SharedMediaCaptureRootJournalTests {
    typealias Journal = SharedMediaCaptureRootJournal
    private struct Fixture {
        let profile: SharedMediaNativeAppProfile
        let intent: Journal.Intent
        let root: Journal.Directory
        let namespace: Journal.Directory
        let final: Journal.Final
        init() throws {
            profile = .init(ownerID: UUID(), inventoryID: UUID(), generation: UUID(), storeIdentity: UUID().uuidString,
                physicalBinding: String(repeating: "a", count: 64), receiptDigest: String(repeating: "b", count: 64),
                physicalBindingFormat: .physicalRootsV1)
            intent = try .init(profile: profile, parentIdentity: "1:10", operationID: UUID())
            root = try .init(intent: intent, kind: .root, parentIdentity: "1:10", identity: "1:11")
            namespace = try .init(intent: intent, kind: .namespace, parentIdentity: "1:11", identity: "1:12")
            final = try .init(intent: intent, root: root, namespace: namespace)
        }
    }

    @Test func interruptionPrefixesRetainTheSameOperationAndBaseProfile() throws {
        let f = try Fixture(), originalBinding = try f.profile.binding
        for stage in 0...3 {
            let prefix = try Journal.Prefix(profile: f.profile, parentIdentity: "1:10", intent: Journal.encode(f.intent),
                root: stage >= 1 ? Journal.encode(f.root) : nil, namespace: stage >= 2 ? Journal.encode(f.namespace) : nil,
                final: stage >= 3 ? Journal.encode(f.final) : nil)
            #expect(prefix.intent == f.intent)
            #expect(prefix.root == (stage >= 1 ? f.root : nil))
            #expect(prefix.namespace == (stage >= 2 ? f.namespace : nil))
            #expect(prefix.final == (stage >= 3 ? f.final : nil))
            #expect(try f.profile.binding == originalBinding)
        }
        let marker = try f.final.binding(intent: f.intent, root: f.root, namespace: f.namespace)
        #expect(marker.count <= 512 && marker != originalBinding)
    }

    @Test(arguments: ["owner", "parent", "root", "namespace", "operation", "missingRoot", "missingNamespace"])
    func completedJournalCannotMoveBetweenStoresOrAdoptMissingCreation(_ change: String) throws {
        let f = try Fixture(), other = try Fixture()
        let movedRoot = try Journal.Directory(intent: f.intent, kind: .root, parentIdentity: "1:10", identity: "1:13")
        let movedChild = try Journal.Directory(intent: f.intent, kind: .namespace, parentIdentity: "1:11", identity: "1:14")
        #expect(throws: (any Error).self) {
            _ = try Journal.Prefix(profile: change == "owner" ? other.profile : f.profile,
                parentIdentity: change == "parent" ? "1:15" : "1:10",
                intent: Journal.encode(change == "operation" ? other.intent : f.intent),
                root: change == "missingRoot" ? nil : Journal.encode(change == "root" ? movedRoot : f.root),
                namespace: change == "missingNamespace" ? nil : Journal.encode(change == "namespace" ? movedChild : f.namespace),
                final: Journal.encode(f.final))
        }
    }

    @Test(arguments: ["version", "unknown", "rootKind", "parentAlias", "namespaceAlias", "trailing", "oversized"])
    func malformedJournalNeverBecomesACompletedPrefix(_ change: String) throws {
        let f = try Fixture()
        var intent = try Journal.encode(f.intent), root = try Journal.encode(f.root), child = try Journal.encode(f.namespace)
        func edit(_ bytes: Data, key: String, value: Any) throws -> Data {
            var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            object[key] = value
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        switch change {
        case "version": intent = try edit(intent, key: "version", value: 2)
        case "unknown": intent = try edit(intent, key: "path", value: "unregistered")
        case "rootKind": root = try edit(root, key: "kind", value: "namespace")
        case "parentAlias": root = try edit(root, key: "identity", value: "1:10")
        case "namespaceAlias": child = try edit(child, key: "identity", value: "1:10")
        case "trailing": intent.append(32)
        case "oversized": intent = Data(repeating: 32, count: Journal.maximumRecordBytes + 1)
        default: Issue.record("Unknown mutation")
        }
        #expect(throws: (any Error).self) {
            _ = try Journal.Prefix(profile: f.profile, parentIdentity: "1:10", intent: intent,
                root: root, namespace: child, final: Journal.encode(f.final))
        }
    }
}
