import SwiftData
import UIKit

struct ConfidenceReviewDependencies {
    let candidate: CandidateReviewDependencies
    let loadRefinementSnapshot: @MainActor (
        _ scanId: String,
        _ modelContainer: ModelContainer
    ) async -> IdentificationReviewRefinementSnapshot?
    let requestRefinementRoute: @MainActor (
        _ scanId: String,
        _ initialDescription: String?
    ) -> Void
    let openSettings: @MainActor () -> Void

    init(
        candidate: CandidateReviewDependencies,
        loadRefinementSnapshot: @escaping @MainActor (
            _ scanId: String,
            _ modelContainer: ModelContainer
        ) async -> IdentificationReviewRefinementSnapshot? = { _, _ in nil },
        requestRefinementRoute: @escaping @MainActor (
            _ scanId: String,
            _ initialDescription: String?
        ) -> Void = { _, _ in },
        openSettings: @escaping @MainActor () -> Void = {}
    ) {
        self.candidate = candidate
        self.loadRefinementSnapshot = loadRefinementSnapshot
        self.requestRefinementRoute = requestRefinementRoute
        self.openSettings = openSettings
    }

    static let live = Self(
        candidate: .live,
        loadRefinementSnapshot: { scanId, modelContainer in
            let databaseActor = IdentificationReviewDatabaseActor(
                modelContainer: modelContainer
            )
            return await databaseActor.refinementSnapshot(scanId: scanId)
        },
        requestRefinementRoute: { scanId, initialDescription in
            AppDIContainer.shared.appRouteCoordinator.request(
                .refinement(
                    scanId: scanId,
                    initialDescription: initialDescription,
                    entryPoint: .standard
                ),
                source: .internalUserAction
            )
        },
        openSettings: {
            guard let url = URL(
                string: UIApplication.openSettingsURLString
            ) else { return }
            UIApplication.shared.open(url)
        }
    )
}
