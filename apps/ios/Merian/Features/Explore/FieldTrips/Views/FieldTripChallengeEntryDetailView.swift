import SwiftUI

struct FieldTripChallengeEntryDetailView: View {
    let entryId: String

    @State private var viewModel: FieldTripPublishedContentViewModel

    init(entryId: String) {
        self.entryId = entryId
        _viewModel = State(
            initialValue: FieldTripPublishedContentViewModel(
                endpoint: .eventEntry(entryId: entryId)
            )
        )
    }

    var body: some View {
        FieldTripPublishedContentDetail(viewModel: viewModel)
            .navigationTitle("Challenge Entry")
            .navigationBarTitleDisplayMode(.inline)
    }
}
