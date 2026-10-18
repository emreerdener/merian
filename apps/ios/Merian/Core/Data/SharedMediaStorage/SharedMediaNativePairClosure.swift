import CryptoKit
import Foundation
import SwiftData

/// One canonical pair closure plus a sibling digest marker. This value carries
/// evidence only; the fenced owner separately mints the unlink capability.
struct SharedMediaNativePairClosure: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable { case bound, unboundPartial, unboundAbsent }
    struct Entry: Codable, Equatable, Sendable {
        let work: SharedMediaNativePairFileState.Work
        let mode: Mode
        let identity: SharedMediaInboxDestinationRetirementIdentity
    }
    struct Previous: Codable, Equatable, Sendable {
        let inventoryRevision: Int64, packageRevision: Int64, membershipRevision: Int64
        let membership: Data
        let phase: String
        let publishedRevision: Int64?
        let allocatedBytes: Int64
    }
    let version: Int
    let retirementID: UUID
    let pairID: UUID
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let packageID: UUID
    let draftGeneration: UUID
    let writerEpoch: UUID
    let beforeHash: String
    let intentHash: String
    let envelopeHash: String
    let afterMembershipHash: String
    let afterMembershipRevision: Int64
    let previous: Previous
    let entries: [Entry]

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func encoded() throws -> String {
        let data = try SharedMediaNativeDraftEnvelope.bytes(self)
        guard data.count <= PhotoPreparationPolicy.metadata, let value = String(data: data, encoding: .utf8),
              version == 1, entries.count == 2, Set(entries.map { $0.work.id }).count == 2,
              ["writing", "ready"].contains(previous.phase),
              [beforeHash, intentHash, envelopeHash, afterMembershipHash].allSatisfy({ $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) } }) else {
            throw SharedMediaStorageFailure.conflict
        }
        for entry in entries { try validate(entry) }
        return value
    }
    static func decode(_ raw: String) throws -> Self {
        guard raw.utf8.count <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        let value = try JSONDecoder().decode(Self.self, from: Data(raw.utf8))
        guard try value.encoded() == raw else { throw SharedMediaStorageFailure.conflict }; return value
    }
    func siblingMarker() throws -> String { "nativePairClosureV1:" + retirementID.uuidString.lowercased() + ":" + Self.digest(Data(try encoded().utf8)) }

    private func validate(_ entry: Entry) throws {
        let work = entry.work
        guard work.writerEpoch == writerEpoch, work.retirementID == nil, work.retirementPartial == nil,
              work.retirementFinal == nil, work.retirementParent == nil, work.retirementNamespace == nil, work.closure == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        _ = try entry.identity.encoded()
        switch entry.mode {
        case .bound:
            guard let device = work.device, let inode = work.inode, ["writing", "completed"].contains(work.phase),
                  work.writerState == (work.phase == "completed" ? "closed" : "open"),
                  (work.phase == "completed") == (work.finalIdentity != nil) else { throw SharedMediaStorageFailure.conflict }
            for raw in [entry.identity.partial, entry.identity.final] where raw != "absent" {
                let parts = raw.split(separator: ":")
                guard parts.count == 7, Int64(parts[0]) == device, Int64(parts[1]) == inode else { throw SharedMediaStorageFailure.conflict }
            }
            guard entry.identity.partial == "absent" || entry.identity.final == "absent" else { throw SharedMediaStorageFailure.conflict }
            if let final = work.finalIdentity, entry.identity.final != "absent" {
                guard entry.identity.partial == "absent", entry.identity.final == final else { throw SharedMediaStorageFailure.conflict }
            }
        case .unboundPartial, .unboundAbsent:
            guard work.phase == "reserved", work.writerState == "open", work.device == nil, work.inode == nil,
                  work.finalIdentity == nil, entry.identity.final == "absent" else { throw SharedMediaStorageFailure.conflict }
            if entry.mode == .unboundAbsent {
                guard entry.identity.partial == "absent" else { throw SharedMediaStorageFailure.conflict }
            } else {
                let parts = entry.identity.partial.split(separator: ":")
                guard parts.count == 7, parts[2] == "0" else { throw SharedMediaStorageFailure.conflict }
            }
        }
    }

    /// A conservative structural byte bound under the existing metadata limit.
    /// It includes full-width counters, both saved work tuples, both 512-byte
    /// descriptor payloads, and maximal membership for these exact two works.
    static func maximumEncodingBytes(_ state: SharedMediaNativePairFileState) throws -> Int64 {
        let intent = try state.intent(), wide = String(repeating: "x", count: 512)
        let membership = try maximumMembership(state)
        // Deliberately overfull shape, encoded only through the generic sizing
        // encoder; never validate, decode or persist this synthetic value.
        let entries = state.work.map { item in
            Entry(work: .init(id: item.id, writerEpoch: item.writerEpoch, phase: "completed", writerState: "closed",
                device: .max, inode: .min, finalIdentity: wide, retirementID: nil, retirementPartial: nil,
                retirementFinal: nil, retirementParent: nil, retirementNamespace: nil, closure: nil), mode: .unboundPartial,
                identity: .init(partial: wide, final: wide, parent: wide, namespace: wide))
        }
        let value = Self(version: 1, retirementID: UUID(), pairID: intent.pairID, inventoryID: state.plan.inventoryID,
            inventoryGeneration: state.plan.inventoryGeneration, packageID: state.plan.packageID,
            draftGeneration: state.plan.draftGeneration, writerEpoch: state.plan.writerEpoch,
            beforeHash: String(repeating: "a", count: 64), intentHash: String(repeating: "a", count: 64), envelopeHash: String(repeating: "a", count: 64),
            afterMembershipHash: String(repeating: "a", count: 64), afterMembershipRevision: .max,
            previous: .init(inventoryRevision: .max, packageRevision: .max, membershipRevision: .max, membership: membership,
                phase: "writing", publishedRevision: .max, allocatedBytes: .max), entries: entries)
        // Include the fixed-size sibling reference, not a second closure.
        return Int64(try SharedMediaNativeDraftEnvelope.bytes(value).count + "nativePairClosureV1:".utf8.count + 36 + 1 + 64)
    }

    static func retirementMembership(_ state: SharedMediaNativePairFileState) throws -> Data {
        let intent = try state.intent()
        var groups = Dictionary(uniqueKeysWithValues: try SharedMediaMembership.decode(state.plan.membership).groups.map { ($0.kind, Set($0.ids)) })
        for input in [intent.ai, intent.display] {
            for kind in [SharedMediaMembership.Kind.work, .lease] { groups[kind, default: []].insert(input.leaseID) }
        }
        return try SharedMediaMembership(groups: groups.map { .init(kind: $0.key, ids: $0.value.sorted { $0.uuidString < $1.uuidString }) }.sorted { $0.kind.rawValue < $1.kind.rawValue }).encoded()
    }

    private static func maximumMembership(_ state: SharedMediaNativePairFileState) throws -> Data {
        let intent = try state.intent()
        var groups = Dictionary(uniqueKeysWithValues: try SharedMediaMembership.decode(state.plan.membership).groups.map { ($0.kind, Set($0.ids)) })
        for input in [intent.ai, intent.display] {
            for kind in [SharedMediaMembership.Kind.asset, .allocation] { groups[kind, default: []].insert(input.assetID) }
            for kind in [SharedMediaMembership.Kind.reference, .edge] { groups[kind, default: []].insert(input.referenceID) }
            for kind in [SharedMediaMembership.Kind.work, .lease] { groups[kind, default: []].insert(input.leaseID) }
        }
        return try SharedMediaMembership(groups: groups.map { .init(kind: $0.key, ids: $0.value.sorted { $0.uuidString < $1.uuidString }) }.sorted { $0.kind.rawValue < $1.kind.rawValue }).encoded()
    }

    static func maximumStateBytes(_ state: SharedMediaNativePairFileState) throws -> Int64 {
        let marker = "nativePairClosureV1:" + UUID().uuidString.lowercased() + ":" + String(repeating: "a", count: 64)
        let maxClosure = try maximumEncodingBytes(state) - Int64(marker.utf8.count), descriptor = String(repeating: "x", count: 512)
        let intent = try state.intent()
        // Quotes conservatively account for the nested JSON escaping of proof
        // strings. This projected liability is held even while the pair is ready.
        let proof = String(repeating: "\"", count: Int(maxClosure))
        let plan = SharedMediaNativePairPlan(intent: state.plan.intent, writerEpoch: state.plan.writerEpoch,
            inventoryID: state.plan.inventoryID, inventoryGeneration: state.plan.inventoryGeneration,
            inventoryRevision: .max, packageID: state.plan.packageID, draftGeneration: state.plan.draftGeneration,
            packageRevision: .max, envelope: state.plan.envelope, membershipRevision: .max, membership: try maximumMembership(state))
        let works = state.work.map { work in
            SharedMediaNativePairFileState.Work(id: work.id, writerEpoch: work.writerEpoch, phase: "completed", writerState: "closed",
                device: .max, inode: .min, finalIdentity: descriptor, retirementID: UUID(), retirementPartial: descriptor,
                retirementFinal: descriptor, retirementParent: descriptor, retirementNamespace: descriptor,
                closure: work.id == intent.ai.id ? proof : marker)
        }
        let bound = SharedMediaNativePairFileState(plan: plan, phase: "retiring", publishedRevision: .max, allocatedBytes: .max, work: works)
        return Int64(try SharedMediaNativeDraftEnvelope.bytes(bound).count)
    }

    @MainActor
    func require(work: SharedMediaDerivativeWorkRecord, pair: SharedMediaDerivativePairRecord,
                 package: PhotoPreparationRecord, inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        let packageID = package.id
        let member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard let entry = entries.first(where: { $0.work.id == work.id }),
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData), let blob = envelope.intents.first,
              Set(entries.map { $0.work.id }) == Set([pair.aiWorkID, pair.displayWorkID]),
              pairID == pair.id, inventoryID == inventory.id, inventoryGeneration == inventory.generation,
              inventory.revision == (try SharedMediaStoragePolicy.add(previous.inventoryRevision, 1)),
              self.packageID == package.id, draftGeneration == package.draftGeneration,
              package.revision == (try SharedMediaStoragePolicy.add(previous.packageRevision, 1)), writerEpoch == work.writerEpoch,
              member.revision == afterMembershipRevision, Self.digest(member.membersData) == afterMembershipHash,
              member.revision == (try SharedMediaStoragePolicy.add(previous.membershipRevision, member.membersData == previous.membership ? 0 : 1)),
              intentHash == Self.digest(blob.bytes), envelopeHash == Self.digest(package.supportingContextData),
              work.retirementID == retirementID, work.partialDevice == entry.work.device, work.partialInode == entry.work.inode,
              work.finalIdentity == entry.work.finalIdentity, package.allocatedByteCount == previous.allocatedBytes,
              work.retirementPartialIdentity == entry.identity.partial, work.retirementFinalIdentity == entry.identity.final,
              work.retirementParentIdentity == entry.identity.parent, work.retirementNamespaceIdentity == entry.identity.namespace else {
            throw SharedMediaStorageFailure.conflict
        }
        let oldPlan = SharedMediaNativePairPlan(intent: blob, writerEpoch: writerEpoch, inventoryID: inventoryID,
            inventoryGeneration: inventoryGeneration, inventoryRevision: previous.inventoryRevision, packageID: packageID,
            draftGeneration: draftGeneration, packageRevision: previous.packageRevision, envelope: package.supportingContextData,
            membershipRevision: previous.membershipRevision, membership: previous.membership)
        let old = SharedMediaNativePairFileState(plan: oldPlan, phase: previous.phase, publishedRevision: previous.publishedRevision,
            allocatedBytes: previous.allocatedBytes, work: entries.map(\.work))
        guard try Self.retirementMembership(old) == member.membersData,
              Self.digest(try SharedMediaNativeDraftEnvelope.bytes(old)) == beforeHash,
              try encoded().utf8.count <= Self.maximumEncodingBytes(old) else { throw SharedMediaStorageFailure.conflict }
    }
}
