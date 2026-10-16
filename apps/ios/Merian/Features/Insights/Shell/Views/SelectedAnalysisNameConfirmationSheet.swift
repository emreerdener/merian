import SwiftUI

struct SelectedAnalysisNameConfirmationSheet: View {
    @Bindable var model: SelectedAnalysisNameConfirmation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Scientific species name", text: $model.scientificName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(!model.review.canSubmit)
                        .accessibilityIdentifier("SelectedReviewSpeciesName")
                    Button("Confirm this species name") { model.submit() }
                        .disabled(!model.canSubmit)
                        .accessibilityIdentifier("SelectedReviewConfirmName")
                } footer: {
                    Text("Confirm a species name for this identification. This does not change the selected identification or confirm other results in its history.")
                }
                if let message = model.review.message {
                    Text(message).accessibilityIdentifier("SelectedReviewNameStatus")
                }
            }
            .navigationTitle("Confirm species name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
