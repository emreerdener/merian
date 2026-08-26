import SwiftUI

struct CommunityDisagreementResolverContext: Identifiable {
    let id = UUID()
    let taxon: CommunityTaxonSearchResult
    let currentName: String
    let relationship: CommunityTaxonPathRelationship
}

struct CommunityDisagreementResolverSheet: View {
    let context: CommunityDisagreementResolverContext
    let isSubmitting: Bool
    let onSubmit: (CommunityIdentificationDisagreementMode, String?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reasoning = ""
    @State private var isGenusBestPossible = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)

                if context.relationship == .conflict {
                    reasonField
                }

                if context.taxon.rank == "genus" {
                    Toggle("This genus is as specific as it can get", isOn: $isGenusBestPossible)
                }

                Spacer()

                VStack(spacing: 10) {
                    Button {
                        onSubmit(primaryMode, submittedReasoning, isGenusBestPossible)
                        dismiss()
                    } label: {
                        Text(primaryTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSubmitting)

                    if context.relationship == .ancestor {
                        Button {
                            onSubmit(.explicitDisagreement, submittedReasoning, isGenusBestPossible)
                            dismiss()
                        } label: {
                            Text("I don't think it's \(context.currentName)")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isSubmitting)
                    }
                }
            }
            .padding(20)
            .navigationTitle("Confirm intent")
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
                    .imageOverlayToolbarButtonChrome(
                        isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Optional reason", text: $reasoning, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(4...7)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var title: String {
        switch context.relationship {
        case .ancestor:
            "You selected \(context.taxon.displayName)"
        case .conflict:
            "This disagrees with \(context.currentName)"
        case .exact, .descendant:
            "Confirm identification"
        }
    }

    private var message: String {
        switch context.relationship {
        case .ancestor:
            "The community is currently more specific. Choose whether you are only less certain, or actively disagree with the current ID."
        case .conflict:
            "Add a short reason if it helps others understand what you are seeing."
        case .exact, .descendant:
            "Submit this identification to the community timeline."
        }
    }

    private var primaryTitle: String {
        switch context.relationship {
        case .ancestor:
            "I'm only sure it's \(context.taxon.displayName)"
        case .conflict:
            "Submit as \(context.taxon.displayName)"
        case .exact, .descendant:
            "Submit"
        }
    }

    private var primaryMode: CommunityIdentificationDisagreementMode {
        context.relationship == .conflict ? .maverick : .implicitSupport
    }

    private var submittedReasoning: String? {
        let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
