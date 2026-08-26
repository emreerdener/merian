import SwiftUI

struct FieldTripPublicationDetailView: View {
    let publicationId: String

    @State private var viewModel: FieldTripPublishedContentViewModel

    init(publicationId: String) {
        self.publicationId = publicationId
        _viewModel = State(
            initialValue: FieldTripPublishedContentViewModel(
                endpoint: .outingPublication(publicationId: publicationId)
            )
        )
    }

    var body: some View {
        FieldTripPublishedContentDetail(viewModel: viewModel)
            .navigationTitle("Field trip")
            .navigationBarTitleDisplayMode(.inline)
    }
}
