import Observation
import SwiftData

@MainActor
@Observable
final class NonBiologicalScansViewModel {
    private(set) var scans: [LocalScanRecord]
    private(set) var isClearingAll = false
    var toastMessage: ToastPayload?

    @ObservationIgnored private let dependencies: NonBiologicalDependencies
    @ObservationIgnored private let service: NonBiologicalScanService

    init(
        scans: [LocalScanRecord] = [],
        dependencies: NonBiologicalDependencies? = nil
    ) {
        let resolvedDependencies = dependencies ?? .live
        self.dependencies = resolvedDependencies
        service = NonBiologicalScanService(
            dependencies: resolvedDependencies
        )
        self.scans = Self.filteredScans(scans)
    }

    var clearAllConfirmationTitle: String {
        NonBiologicalScansPresentation.deleteAllConfirmationTitle(
            count: scans.count
        )
    }

    func refresh(scans: [LocalScanRecord]) {
        self.scans = Self.filteredScans(scans)
    }

    func refreshIdentity(
        scans: [LocalScanRecord]
    ) -> NonBiologicalScansRefreshIdentity {
        NonBiologicalScansRefreshIdentity(scans: scans)
    }

    func purgeExpired(in modelContainer: ModelContainer) async {
        await service.purgeExpired(in: modelContainer)
    }

    @discardableResult
    func clearAll(in modelContainer: ModelContainer) async -> Bool {
        guard !isClearingAll, !scans.isEmpty else { return false }

        isClearingAll = true
        let snapshots = scans.map(NonBiologicalScanErasureSnapshot.init)
        defer { isClearingAll = false }

        do {
            try await service.deleteAll(snapshots, in: modelContainer)
            dependencies.sendLibraryChanged()
            dependencies.triggerSuccessFeedback()
            toastMessage = .success(
                NonBiologicalScansPresentation.clearSuccess
            )
            dependencies.enqueueDeletionSync()
            return true
        } catch {
            dependencies.triggerErrorFeedback()
            toastMessage = .error(
                NonBiologicalScansPresentation.clearFailure
            )
            MerianLog.data.error(
                "NonBiologicalScansViewModel: bulk deletion failed: \(error, privacy: .private)"
            )
            return false
        }
    }

    func requestReanalysis(scanID: String) {
        dependencies.requestRoute(
            NonBiologicalCorrectionReanalysis.refinementRoute(
                scanId: scanID
            )
        )
        dependencies.triggerSelectionFeedback()
        toastMessage = .information(
            NonBiologicalScansPresentation.reanalysisStarted
        )
    }

    func didDeleteSingleScan() {
        toastMessage = .success(
            NonBiologicalScansPresentation.singleDeleteSuccess
        )
    }

    private static func filteredScans(
        _ scans: [LocalScanRecord]
    ) -> [LocalScanRecord] {
        scans.filter { !$0.isBiological }
    }
}
