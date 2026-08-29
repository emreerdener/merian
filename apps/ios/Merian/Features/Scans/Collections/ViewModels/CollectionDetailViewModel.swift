import Combine
import Observation
import SwiftData

@MainActor
@Observable
final class CollectionDetailViewModel {
    private(set) var memberScans: [LocalScanRecord] = []

    @ObservationIgnored let events: AnyPublisher<AppEvent, Never>
    @ObservationIgnored let mutationService: CollectionMutationService

    init(dependencies: CollectionsDependencies? = nil) {
        let resolvedDependencies = dependencies ?? .live
        events = resolvedDependencies.events
        mutationService = CollectionMutationService(
            dependencies: resolvedDependencies
        )
    }

    func refresh(
        scans: [LocalScanRecord],
        collectionID: String
    ) {
        memberScans = CollectionMembershipSnapshot(scans: scans)
            .memberScans(for: collectionID, from: scans)
    }

    func refreshIdentity(
        scans: [LocalScanRecord],
        collectionID: String
    ) -> [String] {
        CollectionMembershipSnapshot.refreshIdentity(
            for: collectionID,
            from: scans
        )
    }

    @discardableResult
    func remove(
        _ scan: LocalScanRecord,
        from collection: ScanCollection,
        scans: [LocalScanRecord],
        in modelContext: ModelContext
    ) -> CollectionMutationService.MembershipOutcome {
        let outcome = mutationService.remove(
            scan,
            from: collection,
            in: modelContext
        )
        if outcome.didCommit {
            refresh(scans: scans, collectionID: collection.id)
        }
        return outcome
    }
}
