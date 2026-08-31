import SwiftUI

struct CommunityIdentificationRequestSheet: View {
    let speciesName: String
    let scientificName: String
    let existingRequestId: String?
    let initialNote: String?
    let initialLocationSharing: ExplorePostLocationSharing?
    let shouldLoadExistingRequestDetail: Bool
    let isSubmitting: Bool
    let onLoadFailed: (String) -> Void
    let onSubmit: (String?, ExplorePostLocationSharing) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CommunityIdentificationRequestViewModel

    init(
        speciesName: String,
        scientificName: String,
        existingRequestId: String?,
        initialNote: String?,
        initialLocationSharing: ExplorePostLocationSharing?,
        shouldLoadExistingRequestDetail: Bool,
        isSubmitting: Bool,
        onLoadFailed: @escaping (String) -> Void,
        onSubmit: @escaping (
            String?,
            ExplorePostLocationSharing
        ) -> Void,
        dependencies: CommunityRequestDependencies? = nil
    ) {
        self.speciesName = speciesName
        self.scientificName = scientificName
        self.existingRequestId = existingRequestId
        self.initialNote = initialNote
        self.initialLocationSharing = initialLocationSharing
        self.shouldLoadExistingRequestDetail = shouldLoadExistingRequestDetail
        self.isSubmitting = isSubmitting
        self.onLoadFailed = onLoadFailed
        self.onSubmit = onSubmit
        _viewModel = State(
            initialValue: CommunityIdentificationRequestViewModel(
                initialNote: initialNote,
                initialLocationSharing: initialLocationSharing,
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(speciesName)
                            .font(.headline)
                        Text(scientificName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Request") {
                    TextEditor(text: $viewModel.note)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if viewModel.trimmedNote == nil {
                                Text("What should identifiers know?")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section("Location") {
                    Picker(
                        "Location Sharing",
                        selection: $viewModel.locationSharing
                    ) {
                        ForEach(ExplorePostLocationSharing.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                if viewModel.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if let loadErrorMessage = viewModel.loadErrorMessage {
                    Section {
                        Text(loadErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(viewModel.isLoading || isSubmitting)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .imageOverlayToolbarIconChrome(
                                isFallbackActive:
                                    ImageOverlayToolbarChrome
                                        .shouldUseContainedBackground,
                                foregroundColor: .primary
                            )
                    }
                    .accessibilityLabel("Close")
                    .imageOverlayToolbarButtonChrome(
                        isFallbackActive:
                            ImageOverlayToolbarChrome
                                .shouldUseContainedBackground
                    )
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSubmit(
                            viewModel.trimmedNote,
                            viewModel.locationSharing
                        )
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityHidden(true)
                        } else {
                            Text(actionTitle)
                        }
                    }
                    .tint(.blue)
                    .disabled(isSubmitting || viewModel.isLoading)
                    .accessibilityLabel(
                        isSubmitting ? submissionProgressLabel : actionTitle
                    )
                }
            }
            .task(id: existingRequestId) {
                if let message = await viewModel.loadExistingRequestIfNeeded(
                    requestID: existingRequestId,
                    initialNote: initialNote,
                    initialLocationSharing: initialLocationSharing,
                    shouldLoadDetail: shouldLoadExistingRequestDetail
                ) {
                    onLoadFailed(message)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isEditingExistingRequest: Bool {
        existingRequestId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
    }

    private var navigationTitle: String {
        isEditingExistingRequest ? "Edit request" : "Ask the community"
    }

    private var actionTitle: String {
        isEditingExistingRequest ? "Save" : "Send"
    }

    private var submissionProgressLabel: String {
        isEditingExistingRequest ? "Saving" : "Sending"
    }
}
