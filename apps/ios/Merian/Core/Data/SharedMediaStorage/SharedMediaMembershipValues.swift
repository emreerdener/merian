import Foundation

/// IDs are lookup aids, never evidence that a missing row may be reconstructed.
struct SharedMediaMembership: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case asset, reference, work, allocation, edge, lease, source, handoff, pair, derivative
        var maximum: Int {
            switch self {
            case .asset, .work: return 96
            case .reference: return 128
            case .allocation, .lease: return 104
            case .edge: return 144
            case .source, .handoff: return 8
            case .pair: return 9
            case .derivative: return 18
            }
        }
    }
    struct Group: Codable, Equatable, Sendable {
        let kind: Kind
        let ids: [UUID]
    }
    let version: Int
    let groups: [Group]

    init(groups: [Group]) throws {
        version = 1
        self.groups = groups
        try validate()
    }

    func ids(_ kind: Kind) -> [UUID] { groups.first { $0.kind == kind }?.ids ?? [] }

    func validate() throws {
        guard version == 1, groups.count <= Kind.allCases.count,
              Set(groups.map(\.kind)).count == groups.count,
              groups.map({ $0.kind.rawValue }) == groups.map({ $0.kind.rawValue }).sorted() else {
            throw SharedMediaStorageFailure.conflict
        }
        for group in groups {
            guard !group.ids.isEmpty, group.ids.count <= group.kind.maximum,
                  Set(group.ids).count == group.ids.count,
                  group.ids.map({ $0.uuidString }) == group.ids.map({ $0.uuidString }).sorted() else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard try value.encoded() == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    /// Existing two-original limit bounds the power set to four states. A
    /// partial completion can encode more than both-current or both-complete
    /// membership, because empty groups disappear from canonical encoding.
    func maximumAcquisitionBytes(pending: [SharedMediaAcquisitionIntent]) throws -> Int64 {
        guard pending.count <= 2, Set(pending.map(\.operationID)).count == pending.count else {
            throw SharedMediaStorageFailure.conflict
        }
        var maximum: Int64 = 0
        for mask in 0..<(1 << pending.count) {
            var groups = Dictionary(uniqueKeysWithValues: self.groups.map { ($0.kind, Set($0.ids)) })
            for (index, request) in pending.enumerated() {
                guard groups[.work]?.contains(request.operationID) == true,
                      groups[.lease]?.contains(request.operationID) == true,
                      groups[.allocation]?.contains(request.assetID) == true else { throw SharedMediaStorageFailure.conflict }
                if mask & (1 << index) == 0 { continue }
                groups[.work]?.remove(request.operationID)
                guard groups[.asset, default: []].insert(request.assetID).inserted,
                      groups[.reference, default: []].insert(request.referenceID).inserted,
                      groups[.edge, default: []].insert(request.referenceID).inserted else { throw SharedMediaStorageFailure.conflict }
            }
            let value = try SharedMediaMembership(groups: groups.filter { !$0.value.isEmpty }.map { kind, ids in
                .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
            }.sorted { $0.kind.rawValue < $1.kind.rawValue })
            maximum = max(maximum, Int64(try value.encoded().count))
        }
        return maximum
    }

    /// All persisted package metadata shares the existing allowance.
    static func requireMetadataBudget(context: Data, membership: Data, cohort: Data = Data()) throws {
        let total = try PhotoPreparationPolicy.add([Int64(context.count), Int64(membership.count), Int64(cohort.count)])
        guard total <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
    }
}
