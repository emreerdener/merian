import SwiftUI

struct IdentificationPublicationSection: View {
    @Bindable var model: IdentificationPublicationModel
    @State private var previewID: UUID?

    var body: some View {
        Section {
            if model.isBusy { ProgressView("Checking community request") }
            switch model.phase {
            case .idle:
                Button("Check sharing status") { model.startRecovery() }
            case .vacant:
                Button("Choose photos to share") { model.startPreparation() }
                    .accessibilityIdentifier("CommunityChoosePhotos")
            case .choosing:
                choices
            case .occupied:
                if let local = model.recovery?.local {
                    Text("Request on this device: \(label(local.phase))")
                }
                if case let .found(remote)? = model.recovery?.remote {
                    Text("Server request: \(label(remote.status))")
                    Text("This request may refer to another identification in this scan's history.").font(.caption)
                }
            case .submitted:
                if let status = model.status { Text(label(status.phase)) }
            case .checking, .preparing, .uncertain, .closed: EmptyView()
            }
            if model.canRetrySave {
                Button("Retry saving original choice") { model.retrySave() }
                    .accessibilityIdentifier("CommunityRetrySave")
            }
            if model.phase == .occupied || model.phase == .uncertain {
                Button("Check existing request") { model.startRecovery() }.disabled(model.isBusy)
            }
            if let message = model.message { Text(message).font(.callout) }
        } header: { Text("Ask the community") }
        footer: { Text("Only the photos you choose will be submitted for public community identification. Private notes are not included. Your selected identification stays unchanged.") }
        .task(id: previewID) {
            if let previewID {
                await model.previewPhoto(previewID)
                if !Task.isCancelled && self.previewID == previewID { self.previewID = nil }
            }
        }
        .onChange(of: model.isScopeCurrent, initial: true) { _, current in if !current { model.close() } }
        .onChange(of: model.deliveryGeneration) { _, _ in model.refreshStatus() }
    }
    @ViewBuilder private var choices: some View {
        Text("Select 1–6 photos in the order you want to share them.")
        ForEach(Array(model.candidates.enumerated()), id: \.element.mediaID) { index, candidate in
            HStack {
                Button { model.toggle(candidate.mediaID) } label: {
                    Label("Photo \(index + 1)", systemImage: model.selected.contains(candidate.mediaID) ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("CommunityPhoto_\(index)")
                Spacer()
                if let order = model.selected.firstIndex(of: candidate.mediaID) { Text("\(order + 1)").foregroundStyle(.secondary) }
                Button("Preview") { previewID = candidate.mediaID }.buttonStyle(.borderless)
                    .accessibilityLabel("Preview photo \(index + 1)")
            }
        }
        if let photo = model.photo {
            Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 240)
                .accessibilityLabel("Saved evidence photo")
        }
        Button("Share \(model.selected.count) \(model.selected.count == 1 ? "photo" : "photos") with the community") { model.submit() }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("CommunityConfirmPhotos")
    }
    private func label(_ phase: ObservationPublicationOperationStatus.Phase) -> String {
        switch phase {
        case .pending: "Waiting to send"
        case .reconciling: "Checking submitted request"
        case .needsAttention: "Needs attention; no automatic replacement"
        case .complete(let status): label(status)
        }
    }
    private func label(_ status: ObservationPublicationStatus) -> String {
        switch status {
        case .accepted: "Received for processing"
        case .processing: "Processing"
        case .photosApproved: "Photos approved; preparing community request"
        case .needsAction: "Needs attention"
        case .admitted: "Community request accepted"
        }
    }
}
