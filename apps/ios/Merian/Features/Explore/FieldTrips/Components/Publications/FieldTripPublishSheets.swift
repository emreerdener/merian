import SwiftUI

struct FieldTripPublishSheet: View {
    let template: FieldTripTemplate
    let onPublished: (FieldTripPublicationDetail) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FieldTripPublishViewModel<FieldTripPublicationDetail>

    init(
        template: FieldTripTemplate,
        onPublished: @escaping (FieldTripPublicationDetail) -> Void
    ) {
        self.template = template
        self.onPublished = onPublished
        _viewModel = State(
            initialValue: FieldTripPublishViewModel(
                initialTitle: FieldTripTemplatePresentation.title(
                    template.title,
                    slug: template.slug
                ),
                endpoint: template.viewerProgress.map {
                    .outing(userFieldTripId: $0.userFieldTripId)
                } ?? .unavailable
            )
        )
    }

    var body: some View {
        FieldTripPublishForm(
            navigationTitle: "Publish outing",
            onCancel: { dismiss() },
            onPublished: onPublished,
            viewModel: viewModel
        )
    }
}

struct FieldTripChallengePublishSheet: View {
    let challenge: FieldTripChallenge
    let onPublished: (FieldTripChallengeEntryDetail) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FieldTripPublishViewModel<FieldTripChallengeEntryDetail>

    init(
        challenge: FieldTripChallenge,
        onPublished: @escaping (FieldTripChallengeEntryDetail) -> Void
    ) {
        self.challenge = challenge
        self.onPublished = onPublished
        _viewModel = State(
            initialValue: FieldTripPublishViewModel(
                initialTitle: challenge.title,
                endpoint: challenge.viewerParticipation.map {
                    .eventEntry(participationId: $0.participationId)
                } ?? .unavailable
            )
        )
    }

    var body: some View {
        FieldTripPublishForm(
            navigationTitle: "Publish Entry",
            onCancel: { dismiss() },
            onPublished: onPublished,
            viewModel: viewModel
        )
    }
}
