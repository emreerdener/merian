import Foundation

/// Frozen, bounded ordinary submission participants. The transaction still
/// owns current-state, file and exact write-set proofs. This value describes
/// the complete requested hold set and derives exact per-asset counter deltas.
struct SharedMediaOrdinaryHoldCohort: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case v1 = "ordinaryOriginalHoldCohortV1" }
    static let maximumHolds = 2
    let format: Format
    let requests: [SharedMediaOrdinaryHoldRequest]

    init(_ requests: [SharedMediaOrdinaryHoldRequest]) throws {
        format = .v1
        self.requests = requests.sorted { $0.id.uuidString < $1.id.uuidString }
        try validate()
    }

    func validate() throws {
        guard (1...Self.maximumHolds).contains(requests.count), let first = requests.first,
              Set(requests.map(\.id)).count == requests.count,
              Set(requests.map(\.source.referenceID)).count == requests.count,
              requests.map(\.id) == requests.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }) else {
            throw SharedMediaStorageFailure.conflict
        }
        let ids = Set(requests.map(\.id))
        for request in requests {
            try request.validate()
            let sourceCount = requests.filter { $0.source.assetID == request.source.assetID }.count
            guard request.profile == first.profile, request.writerEpoch == first.writerEpoch,
                  request.liveCount >= Int64(sourceCount),
                  request.inventoryRevision == first.inventoryRevision,
                  request.recipient.scanID == first.recipient.scanID,
                  request.recipient.submissionGeneration == first.recipient.submissionGeneration,
                  request.recipient.eventID == first.recipient.eventID,
                  request.recipient.observationSHA256 == first.recipient.observationSHA256,
                  ids.isDisjoint(with: [request.source.referenceID, request.source.packageID, request.source.assetID,
                    request.source.assetGeneration, request.source.draftGeneration, request.acquisition.operationID,
                    request.acquisition.referenceID, request.acquisition.packageID]) else { throw SharedMediaStorageFailure.conflict }
            for peer in requests where peer.id != request.id {
                if peer.source.assetID == request.source.assetID {
                    guard peer.source.assetGeneration == request.source.assetGeneration,
                          peer.acquisition == request.acquisition, peer.completion == request.completion,
                          peer.liveCount == request.liveCount, peer.countRevision == request.countRevision else {
                        throw SharedMediaStorageFailure.conflict
                    }
                }
                if peer.source.packageID == request.source.packageID {
                    guard peer.source.draftGeneration == request.source.draftGeneration,
                          peer.sourcePackageRevision == request.sourcePackageRevision,
                          peer.sourceMembershipRevision == request.sourceMembershipRevision else {
                        throw SharedMediaStorageFailure.conflict
                    }
                }
            }
        }
    }

    /// One inventory revision per atomic observation save, one counter revision
    /// per distinct asset, and one logical reference per distinct held source.
    func acceptances() throws -> [UUID: SharedMediaOrdinaryHoldAcceptance] {
        try validate()
        var result: [UUID: SharedMediaOrdinaryHoldAcceptance] = [:]
        for request in requests {
            let count = Int64(requests.filter { $0.source.assetID == request.source.assetID }.count)
            result[request.id] = try .init(request: request,
                inventoryRevision: SharedMediaStoragePolicy.add(request.inventoryRevision, 1),
                countRevision: SharedMediaStoragePolicy.add(request.countRevision, 1),
                liveCount: SharedMediaStoragePolicy.add(request.liveCount, count))
        }
        return result
    }

    func requireAcceptances(_ actual: [UUID: SharedMediaOrdinaryHoldAcceptance]) throws {
        guard try actual == acceptances() else { throw SharedMediaStorageFailure.conflict }
    }

    func encoded() throws -> Data {
        try validate()
        return try SharedMediaAcquisitionEncoding.encode(self,
            maximum: Self.maximumHolds * SharedMediaOrdinaryHoldEncoding.maximumEnvelopeBytes + 1_024)
    }

    static func decode(_ data: Data) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data,
            maximum: maximumHolds * SharedMediaOrdinaryHoldEncoding.maximumEnvelopeBytes + 1_024)
        guard try value.encoded() == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}
