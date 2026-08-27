import SwiftUI

struct ExploreReportUserSheet: View {
    let profile: ExploreAuthorProfile
    let onReported: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreReportUserViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $viewModel.reason) {
                        ForEach(ExploreUserReportReason.allCases) { reportReason in
                            Text(reportReason.rawValue).tag(reportReason)
                        }
                    }
                } header: {
                    Text("Why are you reporting this profile?")
                }

                Section {
                    TextField(
                        "Add optional context",
                        text: Binding(
                            get: { viewModel.details },
                            set: { viewModel.updateDetails($0) }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(4...8)

                    Text("\(viewModel.details.count)/\(ExploreReportUserViewModel.detailsLimit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } header: {
                    Text("Details")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Report error: \(errorMessage)")
                    }
                }

                Section {
                    Text(
                        "Reporting does not automatically block this person. " +
                            "Naturebook moderators will review the report."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report \(profile.publicAuthorDisplayName)")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(viewModel.isSubmitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(viewModel.isSubmitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        guard await viewModel.submit(reportedUserId: profile.authorUserId) else { return }
        onReported()
        dismiss()
    }
}
