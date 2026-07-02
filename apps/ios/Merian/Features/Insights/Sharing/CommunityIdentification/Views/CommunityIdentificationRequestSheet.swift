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
    @State private var note = ""
    @State private var locationSharing: ExplorePostLocationSharing = .obscured
    @State private var hasLoadedExistingRequest = false
    @State private var isLoadingExistingRequest = false
    @State private var loadErrorMessage: String?

    var body: some View {
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
                    TextEditor(text: $note)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("What should identifiers know?")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section("Location") {
                    Picker("Location Sharing", selection: $locationSharing) {
                        ForEach(ExplorePostLocationSharing.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                if isLoadingExistingRequest {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if let loadErrorMessage {
                    Section {
                        Text(loadErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(isLoadingExistingRequest || isSubmitting)
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
                                isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground,
                                foregroundColor: .primary
                            )
                    }
                    .accessibilityLabel("Close")
                    .imageOverlayToolbarButtonChrome(isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        onSubmit(trimmedNote, locationSharing)
                    }
                    .tint(.blue)
                    .disabled(isSubmitting || isLoadingExistingRequest)
                }
            }
            .task(id: existingRequestId) {
                await loadExistingRequestIfNeeded()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isEditingExistingRequest: Bool {
        existingRequestId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var navigationTitle: String {
        isEditingExistingRequest ? "Edit request" : "Ask the community"
    }

    private var actionTitle: String {
        if isSubmitting {
            return isEditingExistingRequest ? "Saving..." : "Sending..."
        }
        return isEditingExistingRequest ? "Save" : "Send"
    }

    private var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadExistingRequestIfNeeded() async {
        guard let existingRequestId,
              existingRequestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            note = initialNote ?? ""
            locationSharing = initialLocationSharing ?? .obscured
            hasLoadedExistingRequest = false
            loadErrorMessage = nil
            return
        }
        guard !hasLoadedExistingRequest else { return }

        if let initialNote {
            note = initialNote
        }
        if let initialLocationSharing {
            locationSharing = initialLocationSharing
        }
        guard shouldLoadExistingRequestDetail else {
            hasLoadedExistingRequest = true
            loadErrorMessage = nil
            return
        }

        isLoadingExistingRequest = true
        defer { isLoadingExistingRequest = false }

        do {
            let detail = try await MerianNetworkClient.shared.getCommunityIdentificationDetail(requestId: existingRequestId)
            guard !Task.isCancelled else { return }
            note = detail.note ?? ""
            locationSharing = detail.locationSharing ?? initialLocationSharing ?? .obscured
            hasLoadedExistingRequest = true
            loadErrorMessage = nil
        } catch {
            let message = ExploreErrorFormatter.message(for: error)
            loadErrorMessage = message
            onLoadFailed(message)
        }
    }
}
