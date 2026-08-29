import SwiftData

@MainActor
struct NonBiologicalScanService {
    private let dependencies: NonBiologicalDependencies

    init(dependencies: NonBiologicalDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func purgeExpired(in modelContainer: ModelContainer) async {
        await dependencies.purgeExpired(modelContainer)
    }

    func deleteAll(
        _ snapshots: [NonBiologicalScanErasureSnapshot],
        in modelContainer: ModelContainer
    ) async throws {
        let deletedPaths = try await dependencies.deleteRecords(
            snapshots,
            modelContainer
        )
        await dependencies.deleteFiles(deletedPaths)
    }
}
