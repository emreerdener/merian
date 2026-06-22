import SwiftUI

struct CommunityIdentificationRequestSheet: View {
    let speciesName: String
    let scientificName: String
    let isSubmitting: Bool
    let onSubmit: (String?, ExplorePostLocationSharing) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var locationSharing: ExplorePostLocationSharing = .obscured

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

                Section {
                    Button {
                        onSubmit(trimmedNote, locationSharing)
                    } label: {
                        Text(isSubmitting ? "Sending..." : "Send")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isSubmitting ? Color.blue.opacity(0.35) : Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Ask the community")
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
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
