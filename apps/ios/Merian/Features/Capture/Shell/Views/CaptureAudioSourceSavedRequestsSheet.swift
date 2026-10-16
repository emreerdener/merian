import SwiftUI

struct CaptureAudioSourceSavedRequestsSheet: View {
    @Bindable var model: CaptureAudioSourceSavedRequestsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if model.isClosed {
                    Text("Saved requests are no longer available for this observation.")
                } else {
                    Section {
                        ForEach(Array(model.rows.enumerated()), id: \.element.identity.analysisID) { entry in
                            let row = entry.element
                            Button { model.select(row) } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: model.selected == row.identity ? "checkmark.circle.fill" : "circle")
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Saved audio source \(entry.offset + 1)").font(.headline)
                                        Text(Self.status(row.phase)).font(.subheadline)
                                    }
                                }
                            }
                            .disabled(model.isBusy)
                            .accessibilityAddTraits(model.selected == row.identity ? .isSelected : [])
                            .accessibilityIdentifier("SavedAudioSourceRow_\(row.identity.analysisID.uuidString.lowercased())")
                        }
                        if model.rows.isEmpty && !model.isBusy {
                            Text(model.message == nil ? "No saved audio requests are available on this page." : "This page could not be checked.")
                        }
                        if model.omittedCount > 0 {
                            Text("Some saved requests could not be shown. This does not mean they were removed.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Choose a saved request. Your current identification stays in place. Continuing checks this exact saved source request. It never replaces an uncertain analysis.")
                    }
                    Button(actionTitle) { model.continueSelected() }
                        .disabled(model.selected == nil || model.isBusy)
                        .accessibilityIdentifier("SavedAudioSourceContinue")
                    if model.next != nil {
                        Button("More requests") { model.start(more: true) }
                            .disabled(model.isBusy).accessibilityIdentifier("SavedAudioSourceMore")
                    }
                    if let message = model.message {
                        Text(message).accessibilityIdentifier("SavedAudioSourceMessage")
                    }
                    if model.isBusy { ProgressView().accessibilityLabel("Checking saved audio sources") }
                }
            }
            .navigationTitle("Saved audio sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", systemImage: "arrow.clockwise") { model.start() }
                        .disabled(model.isBusy || model.isClosed).accessibilityIdentifier("SavedAudioSourceRefresh")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { model.close(); dismiss() }.accessibilityIdentifier("SavedAudioSourceDone")
                }
            }
        }
        .accessibilityIdentifier("SavedAudioSourceSheet")
        .presentationDetents([.large])
        .task { model.start() }
        .onChange(of: model.isCurrent, initial: true) { _, current in if !current { model.close() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.validate() } }
        .onDisappear { model.close() }
    }

    private var actionTitle: String {
        model.selected == nil ? "Choose a request" : "Check saved source"
    }

    static func status(_ phase: ObservationAudioSourceSavedStatus.Phase) -> String {
        switch phase {
        case .staged: "Source request saved"
        case .checking: "Source check needs recovery"
        case .unknown: "Source outcome needs checking"
        case .reserved: "Source reserved; ready to continue"
        case .held: "Source request is held"
        case .unavailable: "Source is unavailable"
        case .conflict: "Saved source conflicts with current state"
        }
    }
}
