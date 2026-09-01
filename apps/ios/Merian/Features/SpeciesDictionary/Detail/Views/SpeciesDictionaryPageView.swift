import SwiftUI

struct SpeciesDictionaryPageView: View {
    let scientificName: String
    let speciesId: String?
    let entryPoint: SpeciesDictionaryEntryPoint

    @Environment(\.dismiss) private var dismiss
    @State private var exploreViewModel: ExploreFeedViewModel
    private let dependencies: SpeciesDictionaryDetailDependencies

    @MainActor
    init(
        scientificName: String,
        speciesId: String? = nil,
        entryPoint: SpeciesDictionaryEntryPoint = .unknown,
        dependencies: SpeciesDictionaryDetailDependencies? = nil
    ) {
        let dependencies = dependencies ?? .live
        let request = SpeciesDictionaryDetailRequest(
            speciesId: speciesId,
            scientificName: scientificName
        )
        self.scientificName = request.scientificName ?? ""
        self.speciesId = request.speciesId
        self.entryPoint = entryPoint
        self.dependencies = dependencies
        _exploreViewModel = State(
            initialValue: dependencies.makeExploreViewModel()
        )
    }

    var body: some View {
        NavigationStack {
            SpeciesDictionaryPageContentView(
                scientificName: scientificName,
                speciesId: speciesId,
                entryPoint: entryPoint,
                showsCloseButton: true,
                exploreViewModel: exploreViewModel,
                dependencies: dependencies,
                onClose: { dismiss() }
            )
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false,
                    exploreViewModel: exploreViewModel,
                    dependencies: dependencies
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }
}
