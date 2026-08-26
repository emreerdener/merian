import SwiftUI

struct FieldTripPublishForm<Output>: View {
    let navigationTitle: String
    let onCancel: () -> Void
    let onPublished: (Output) -> Void

    @Bindable var viewModel: FieldTripPublishViewModel<Output>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $viewModel.title)
                    TextField("Description", text: $viewModel.description, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let output = await viewModel.publish() {
                                onPublished(output)
                            }
                        }
                    } label: {
                        if viewModel.isPublishing {
                            ProgressView()
                        } else {
                            Text("Publish")
                        }
                    }
                    .disabled(viewModel.isPublishing || !viewModel.canPublish)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
