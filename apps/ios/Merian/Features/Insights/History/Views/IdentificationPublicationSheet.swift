import SwiftUI

struct IdentificationPublicationSheet: View {
    @Bindable var model: IdentificationPublicationModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            List { IdentificationPublicationSection(model: model) }
                .navigationTitle("Ask the community")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshStatus() } }
    }
}
