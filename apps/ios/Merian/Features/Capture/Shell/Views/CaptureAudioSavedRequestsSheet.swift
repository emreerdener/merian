import SwiftUI

struct CaptureAudioSavedRequestsSheet: View {
    @Bindable var model: CaptureAudioSavedRequestsModel
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
                                        Text("Saved audio request \(entry.offset + 1)").font(.headline)
                                        Text(Self.status(row.phase)).font(.subheadline)
                                    }
                                }
                            }
                            .disabled(model.isBusy)
                            .accessibilityAddTraits(model.selected == row.identity ? .isSelected : [])
                            .accessibilityIdentifier("SavedAudioRow_\(row.identity.analysisID.uuidString.lowercased())")
                        }
                        if model.rows.isEmpty && !model.isBusy {
                            Text(model.message == nil ? "No saved audio requests are available on this page." : "This page could not be checked.")
                        }
                        if model.omittedCount > 0 {
                            Text("Some saved requests could not be shown. This does not mean they were removed.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Choose a saved request. Your current identification stays in place. When a saved request has already been sent, continuing only checks its original result.")
                    }
                    Button(actionTitle) { model.continueSelected() }
                        .disabled(model.selected == nil || model.isBusy)
                        .accessibilityIdentifier("SavedAudioContinue")
                    if model.next != nil {
                        Button("More requests") { model.start(more: true) }
                            .disabled(model.isBusy).accessibilityIdentifier("SavedAudioMore")
                    }
                    if let message = model.message {
                        Text(message).accessibilityIdentifier("SavedAudioMessage")
                    }
                    if model.isBusy { ProgressView().accessibilityLabel("Checking saved audio requests") }
                }
            }
            .navigationTitle("Saved audio requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", systemImage: "arrow.clockwise") { model.start() }
                        .disabled(model.isBusy || model.isClosed).accessibilityIdentifier("SavedAudioRefresh")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { model.close(); dismiss() }.accessibilityIdentifier("SavedAudioDone")
                }
            }
        }
        .accessibilityIdentifier("SavedAudioSheet")
        .presentationDetents([.large])
        .task { model.start() }
        .onChange(of: model.isCurrent, initial: true) { _, current in if !current { model.close() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.validate() } }
        .onDisappear { model.close() }
    }

    private var actionTitle: String {
        guard let row = model.rows.first(where: { $0.identity == model.selected }) else { return "Choose a request" }
        switch row.phase {
        case .runningConsumed, .heldConsumed: return "Check saved result"
        default: return "Continue saved request"
        }
    }

    static func status(_ phase: ObservationAudioSavedStatus.Phase) -> String {
        switch phase {
        case .filesPending: "Audio preparation pending"
        case .admissionPending: "Ready to continue"
        case .boundIdle: "Waiting to continue"
        case .runningUnconsumed: "Preparation needs checking"
        case .heldUnconsumed: "Paused before analysis"
        case .runningConsumed: "Original result can be checked"
        case .heldConsumed: "Original result needs checking"
        }
    }
}
