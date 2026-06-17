import SwiftUI

enum ExplorePostComposerMode {
    case create
    case edit

    var title: String {
        switch self {
        case .create:
            return "Share"
        case .edit:
            return "Edit"
        }
    }

    var actionTitle: String {
        switch self {
        case .create:
            return "Share discovery"
        case .edit:
            return "Save"
        }
    }
}

enum ExplorePostLocationSharing: String, CaseIterable, Identifiable, Decodable, Equatable {
    case open
    case obscured
    case privateLocation = "private"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        switch rawValue {
        case "open":
            self = .open
        case "obscured":
            self = .obscured
        case "private", "hidden":
            self = .privateLocation
        default:
            self = .obscured
        }
    }

    var title: String {
        switch self {
        case .open:
            return "Open"
        case .obscured:
            return "Obscured"
        case .privateLocation:
            return "Private"
        }
    }

    var systemImage: String {
        switch self {
        case .open:
            return "mappin.and.ellipse"
        case .obscured:
            return "location.viewfinder"
        case .privateLocation:
            return "location.slash"
        }
    }

    var detail: String {
        switch self {
        case .open:
            return "Use the discovery location on Explore Map when safe."
        case .obscured:
            return "Show a broad public label; keep it off Explore Map."
        case .privateLocation:
            return "Share this post without public location."
        }
    }
}

struct ExplorePostComposerDraft {
    let selectedCommonName: String
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
    let scientificName: String
    let heroImageUrl: String?
    let publicLocationLabel: String?
    let commonNameOptions: [String]
    let initialFieldNotes: String?
    let initialFieldNotesArePublic: Bool
    let initialHashtags: [String]
    let initialLocationSharing: ExplorePostLocationSharing
    let hashtagSuggestionContext: ExploreHashtagSuggestionContext
    let isSaving: Bool
    let onSubmit: (ExplorePostComposerDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNotesFocused: Bool
    @State private var fieldNotesText: String
    @State private var fieldNotesArePublic: Bool
    @State private var hashtagsText: String
    @State private var locationSharing: ExplorePostLocationSharing
    @State private var loadedImage: UIImage?
    @State private var selectedCommonName: String
    @State private var isNamePickerPresented = false

    init(
        mode: ExplorePostComposerMode,
        speciesName: String,
        scientificName: String,
        heroImageUrl: String?,
        publicLocationLabel: String?,
        commonNameOptions: [String] = [],
        initialSelectedCommonName: String? = nil,
        initialFieldNotes: String?,
        initialFieldNotesArePublic: Bool = true,
        initialHashtags: [String],
        initialLocationSharing: ExplorePostLocationSharing = .obscured,
        hashtagSuggestionContext: ExploreHashtagSuggestionContext? = nil,
        isSaving: Bool,
        onSubmit: @escaping (ExplorePostComposerDraft) -> Void
    ) {
        self.mode = mode
        self.scientificName = scientificName
        self.heroImageUrl = heroImageUrl
        self.publicLocationLabel = publicLocationLabel
        let selectedName = Self.cleanedCommonName(initialSelectedCommonName) ?? Self.cleanedCommonName(speciesName) ?? scientificName
        let options = ([selectedName, speciesName] + commonNameOptions)
            .compactMap(Self.cleanedCommonName)
            .removingFuzzyDuplicateNames()
        self.commonNameOptions = options.isEmpty ? [selectedName] : options
        self.initialFieldNotes = initialFieldNotes
        self.initialFieldNotesArePublic = initialFieldNotesArePublic
        self.initialHashtags = initialHashtags
        self.initialLocationSharing = initialLocationSharing
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
        _locationSharing = State(initialValue: initialLocationSharing)
        _selectedCommonName = State(initialValue: selectedName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    discoveryPreview
                    locationSharingEditor
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
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
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
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    
                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(mode.actionTitle)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .systemBlue))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                    .opacity(isSaving ? 0.7 : 1.0)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $isNamePickerPresented) {
            NamePickerSheet(
                allNames: commonNameOptions,
                activeName: selectedCommonName,
                title: "Post name",
                footerText: "Your selection updates this post and your preferred name for this species.",
                onSelect: { name in
                    selectedCommonName = name
                    isNamePickerPresented = false
                    HapticManager.shared.triggerSelectionPulse()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var discoveryPreview: some View {
        Button {
            guard commonNameOptions.count > 1 else { return }
            isNamePickerPresented = true
        } label: {
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
                    Text(selectedCommonName)
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

                if commonNameOptions.count > 1 {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(commonNameOptions.count > 1 ? "Choose which common name appears on the Explore post" : "")
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

            Text("Use up to five hashtags separated by spaces or commas.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            suggestedHashtagChips
        }
    }

    private var locationSharingEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Location", systemImage: "location")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(ExplorePostLocationSharing.allCases) { option in
                    Button {
                        locationSharing = option
                        HapticManager.shared.triggerSelectionPulse()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(locationSharing == option ? Color.accentColor : .secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(option.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer(minLength: 8)

                            if locationSharing == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    locationSharing == option ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var suggestedHashtagChips: some View {
        let suggestions = currentHashtagSuggestions
        if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
        }
    }

    private var currentHashtagSuggestions: [String] {
        var context = hashtagSuggestionContext.updating(fieldNotes: fieldNotesText)
        context.speciesName = selectedCommonName
        return ExploreHashtagSuggestionEngine.suggestions(
            for: context,
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
                selectedCommonName: selectedCommonName,
                fieldNotes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                fieldNotesArePublic: fieldNotesArePublic,
                hashtags: normalizedHashtags,
                locationSharing: locationSharing
            )
        )
    }

    private static func cleanedCommonName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
