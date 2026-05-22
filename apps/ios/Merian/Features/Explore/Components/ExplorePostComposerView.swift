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
    let hashtags: [String]
    let locationSharing: ExplorePostLocationSharing
}

struct ExplorePostComposerView: View {
    let mode: ExplorePostComposerMode
    let speciesName: String
    let scientificName: String
    let heroImageUrl: String?
    let publicLocationLabel: String?
    let initialFieldNotes: String?
    let initialHashtags: [String]
    let isSaving: Bool
    let onSubmit: (ExplorePostComposerDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNotesFocused: Bool
    @State private var fieldNotesText: String
    @State private var hashtagsText: String
    @State private var locationSharing = ExplorePostLocationSharing.obscured

    init(
        mode: ExplorePostComposerMode,
        speciesName: String,
        scientificName: String,
        heroImageUrl: String?,
        publicLocationLabel: String?,
        initialFieldNotes: String?,
        initialHashtags: [String],
        isSaving: Bool,
        onSubmit: @escaping (ExplorePostComposerDraft) -> Void
    ) {
        self.mode = mode
        self.speciesName = speciesName
        self.scientificName = scientificName
        self.heroImageUrl = heroImageUrl
        self.publicLocationLabel = publicLocationLabel
        self.initialFieldNotes = initialFieldNotes
        self.initialHashtags = initialHashtags
        self.isSaving = isSaving
        self.onSubmit = onSubmit
        _fieldNotesText = State(initialValue: initialFieldNotes ?? "")
        _hashtagsText = State(initialValue: initialHashtags.map { "#\($0)" }.joined(separator: " "))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    discoveryPreview
                    fieldNotesEditor
                    hashtagsEditor
                    locationSharingPicker
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
                        } else {
                            Text(mode.actionTitle)
                                .fontWeight(.semibold)
                        }
                    }
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
            AsyncImage(url: heroImageUrl.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
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

            Text("Use up to five hashtags separated by spaces or commas.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var locationSharingPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Location sharing", systemImage: "location")
                .font(.headline)

            if let publicLocationLabel, !publicLocationLabel.isEmpty {
                Text(publicLocationLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Picker("Location sharing", selection: $locationSharing) {
                ForEach(ExplorePostLocationSharing.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Label(locationSharing.detail, systemImage: locationSharing.systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var normalizedHashtags: [String] {
        var tags: [String] = []
        var seen = Set<String>()
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

        for token in hashtagsText.components(separatedBy: separators) {
            let cleaned = token
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .lowercased()
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { continue }
            tags.append(cleaned)
            if tags.count == 5 { break }
        }

        return tags
    }

    private func submit() {
        let trimmedNotes = fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(
            ExplorePostComposerDraft(
                fieldNotes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                hashtags: normalizedHashtags,
                locationSharing: locationSharing
            )
        )
    }
}
