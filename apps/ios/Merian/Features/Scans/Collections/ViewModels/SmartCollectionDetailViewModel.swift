import Combine
import Foundation
import Observation

@MainActor
@Observable
final class SmartCollectionDetailViewModel {
    private(set) var liveSnapshot: SmartCollectionSnapshot

    @ObservationIgnored let events: AnyPublisher<AppEvent, Never>
    @ObservationIgnored private let dependencies: CollectionsDependencies

    init(
        snapshot: SmartCollectionSnapshot,
        dependencies: CollectionsDependencies? = nil
    ) {
        let resolvedDependencies = dependencies ?? .live
        liveSnapshot = snapshot
        self.dependencies = resolvedDependencies
        events = resolvedDependencies.events
    }

    func refresh(
        snapshot: SmartCollectionSnapshot,
        scans: [LocalScanRecord],
        referenceDate: Date = Date()
    ) {
        liveSnapshot = SmartCollectionSuggester.refreshedSnapshot(
            for: snapshot,
            from: scans,
            sharedPostIDProvider: dependencies.sharedPostID,
            referenceDate: referenceDate
        )
    }

    func refreshIdentity(
        scans: [LocalScanRecord]
    ) -> CollectionScanRefreshIdentity {
        CollectionScanRefreshIdentity(scans: scans)
    }

    func hide(
        snapshot: SmartCollectionSnapshot,
        onHide: (SmartCollectionSnapshot) -> Void
    ) -> Bool {
        guard snapshot.isHideable else { return false }
        onHide(snapshot)
        dependencies.triggerLightFeedback()
        return true
    }
}
