import Combine
import Observation
import SwiftData

@MainActor
@Observable
final class SelectMultipleScansViewModel {
    private(set) var membership = CollectionMembershipSnapshot.empty

    @ObservationIgnored let events: AnyPublisher<AppEvent, Never>
    @ObservationIgnored private let mutationService: CollectionMutationService

    init(dependencies: CollectionsDependencies? = nil) {
        let resolvedDependencies = dependencies ?? .live
        events = resolvedDependencies.events
        mutationService = CollectionMutationService(
            dependencies: resolvedDependencies
        )
    }

    func refresh(scans: [LocalScanRecord]) {
        membership = CollectionMembershipSnapshot(scans: scans)
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

    func contains(
        scanID: String,
        collectionID: String
    ) -> Bool {
        membership.contains(scanID: scanID, in: collectionID)
    }

    @discardableResult
    func toggle(
        _ scan: LocalScanRecord,
        in collection: ScanCollection,
        scans: [LocalScanRecord],
        modelContext: ModelContext
    ) -> CollectionMutationService.MembershipOutcome {
        let outcome = mutationService.toggle(
            scan,
            in: collection,
            in: modelContext
        )
        if outcome.didCommit {
            refresh(scans: scans)
        }
        return outcome
    }
}
