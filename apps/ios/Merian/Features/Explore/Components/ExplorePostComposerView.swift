import SwiftUI

enum ExplorePostComposerMode {
    case create
    case edit

    var title: String {
        switch self {
        case .create:
            return "Share discovery"
        case .edit:
            return "Edit post"
        }
    }

    var actionTitle: String {
        switch self {
        case .create:
            return "Share"
        case .edit:
            return "Save"
        }
    }
}

enum ExplorePostLocationSharing: String, CaseIterable, Identifiable {
    case obscured
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .obscured:
            return "Obscure"
        case .hidden:
            return "Hide"
        }
    }

    var systemImage: String {
        switch self {
        case .obscured:
            return "location.viewfinder"
        case .hidden:
            return "location.slash"
        }
    }

    var detail: String {
        switch self {
        case .obscured:
            return "Show a broad public location when one is available."
        case .hidden:
            return "Keep the post location off the feed and map."
        }
    }
}

struct ExplorePostComposerDraft {
    let fieldNotes: String?
    let fieldNotesArePublic: Bool
    let hashtags: [String]
    let locationSharing: ExplorePostLocationSharing

    var publicFieldNotes: String? {
        fieldNotesArePublic ? fieldNotes : nil
    }
}

struct ExplorePostComposerView: View {
    let mode: ExplorePostComposerMode
    let speciesName: String
    let scientificName: String
    let heroImageUrl: String?
    let publicLocationLabel: String?
    let initialFieldNotes: String?
    let initialFieldNotesArePublic: Bool
    let initialHashtags: [String]
    let hashtagSuggestionContext: ExploreHashtagSuggestionContext
    let isSaving: Bool
    let onSubmit: (ExplorePostComposerDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNotesFocused: Bool
    @State private var fieldNotesText: String
    @State private var fieldNotesArePublic: Bool
    @State private var hashtagsText: String
    @State private var locationSharing = ExplorePostLocationSharing.obscured
    @State private var loadedImage: UIImage?

    init(
        mode: ExplorePostComposerMode,
        speciesName: String,
        scientificName: String,
        heroImageUrl: String?,
        publicLocationLabel: String?,
        initialFieldNotes: String?,
        initialFieldNotesArePublic: Bool = true,
        initialHashtags: [String],
        hashtagSuggestionContext: ExploreHashtagSuggestionContext? = nil,
        isSaving: Bool,
        onSubmit: @escaping (ExplorePostComposerDraft) -> Void
    ) {
        self.mode = mode
        self.speciesName = speciesName
        self.scientificName = scientificName
        self.heroImageUrl = heroImageUrl
        self.publicLocationLabel = publicLocationLabel
        self.initialFieldNotes = initialFieldNotes
        self.initialFieldNotesArePublic = initialFieldNotesArePublic
        self.initialHashtags = initialHashtags
        self.hashtagSuggestionContext = hashtagSuggestionContext ?? ExploreHashtagSuggestionContext(
            speciesName: speciesName,
            scientificName: scientificName,
            publicLocationLabel: publicLocationLabel,
            fieldNotes: initialFieldNotes
        )
        self.isSaving = isSaving
        self.onSubmit = onSubmit
        _fieldNotesText = State(initialValue: initialFieldNotes ?? "")
        _fieldNotesArePublic = State(initialValue: initialFieldNotesArePublic)
        _hashtagsText = State(initialValue: initialHashtags.map { "#\($0)" }.joined(separator: " "))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    discoveryPreview
                    fieldNotesEditor
                    hashtagsEditor
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: submit) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Text(mode.actionTitle)
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .systemBlue))
                    )
                    .opacity(isSaving ? 0.7 : 1)
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isNotesFocused = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var discoveryPreview: some View {
        HStack(spacing: 12) {
            Group {
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(uiColor: .tertiarySystemFill)
                        .overlay {
                            Image(systemName: "leaf")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(speciesName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(scientificName)
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: heroImageUrl) {
            guard let heroImageUrl else { return }
            loadedImage = await LocalImageLoader.shared.loadImage(fromPath: heroImageUrl, fallbackUrl: nil, maxDimension: 124)
        }
    }

    private var fieldNotesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Field notes", systemImage: "square.and.pencil")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))

                TextEditor(text: $fieldNotesText)
                    .focused($isNotesFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 146)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .onChange(of: fieldNotesText) { _, text in
                        if text.count > 1000 {
                            fieldNotesText = String(text.prefix(1000))
                        }
                    }

                if fieldNotesText.isEmpty {
                    Text("Add what you noticed in the field...")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 13)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Text("\(fieldNotesText.count)/1000")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if mode == .edit {
                Toggle(isOn: $fieldNotesArePublic) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show on Explore")
                            .font(.subheadline.weight(.semibold))

                        Text(fieldNotesArePublic
                            ? "Field notes appear on this post."
                            : "Keep these field notes off this post.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var hashtagsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hashtags", systemImage: "number")
                .font(.headline)

            TextField("#citybioblitz #pollinators", text: $hashtagsText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            suggestedHashtagChips

            Text("Use up to five hashtags separated by spaces or commas.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var suggestedHashtagChips: some View {
        let suggestions = currentHashtagSuggestions
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("AI suggestions", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { hashtag in
                        Button {
                            addSuggestedHashtag(hashtag)
                        } label: {
                            Text("#\(hashtag)")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Add hashtag \(hashtag)")
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var currentHashtagSuggestions: [String] {
        ExploreHashtagSuggestionEngine.suggestions(
            for: hashtagSuggestionContext.updating(fieldNotes: fieldNotesText),
            selectedHashtags: normalizedHashtags
        )
    }

    private var normalizedHashtags: [String] {
        ExploreHashtagSuggestionEngine.normalizedInputTags(from: hashtagsText)
    }

    private func addSuggestedHashtag(_ hashtag: String) {
        guard let normalized = ExploreHashtagSuggestionEngine.normalizedTag(from: hashtag),
              normalizedHashtags.count < 5,
              !normalizedHashtags.contains(normalized) else { return }

        let trimmedText = hashtagsText.trimmingCharacters(in: .whitespacesAndNewlines)
        hashtagsText = trimmedText.isEmpty ? "#\(normalized)" : "\(trimmedText) #\(normalized)"
        HapticManager.shared.triggerSelectionPulse()
    }

    private func submit() {
        let trimmedNotes = fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(
            ExplorePostComposerDraft(
                fieldNotes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                fieldNotesArePublic: fieldNotesArePublic,
                hashtags: normalizedHashtags,
                locationSharing: locationSharing
            )
        )
    }
}
