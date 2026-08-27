import SwiftUI
import UniformTypeIdentifiers

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
    @State private var mediaItems: [ExplorePostComposerMediaDraft]
    @State private var draggedMediaItemId: String?
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
        mediaItems: [ExplorePostComposerMediaDraft] = [],
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
        _mediaItems = State(initialValue: mediaItems)
        _selectedCommonName = State(initialValue: selectedName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    discoveryPreview
                    if mediaItems.count > 1 {
                        mediaSelectionEditor
                    }
                    fieldNotesEditor
                    locationSharingEditor
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

            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                submitFooter
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

    private var activeHeroImageUrl: String? {
        mediaItems.first(where: \.isIncluded)?.previewPath ?? heroImageUrl
    }

    private var selectedMediaCount: Int {
        mediaItems.filter(\.isIncluded).count
    }

    private var canSubmit: Bool {
        !isSaving && (mediaItems.isEmpty || selectedMediaCount > 0)
    }

    private var discoveryPreview: some View {
        Button {
            guard commonNameOptions.count > 1 else { return }
            isNamePickerPresented = true
        } label: {
            HStack(spacing: 12) {
                ExplorePostComposerImageView(
                    path: activeHeroImageUrl,
                    maxDimension: 124,
                    placeholder: .discovery
                )
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
    }

    private var mediaSelectionEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Media", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)

                Spacer()

                Text("\(selectedMediaCount) selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(mediaItems) { item in
                        ExplorePostComposerMediaTile(
                            item: item,
                            isCover: item.id == mediaItems.first(where: \.isIncluded)?.id,
                            canDeselect: selectedMediaCount > 1 || !item.isIncluded,
                            onToggle: { toggleMediaItem(item.id) }
                        )
                        .onDrag {
                            draggedMediaItemId = item.id
                            HapticManager.shared.triggerSelectionPulse()
                            return NSItemProvider(object: item.id as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: ExplorePostComposerMediaDropDelegate(
                                targetItem: item,
                                mediaItems: $mediaItems,
                                draggedMediaItemId: $draggedMediaItemId
                            )
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)

            Text("The first selected item is the cover.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var fieldNotesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Field notes", systemImage: "square.and.pencil")
                .font(.headline)

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

    private var submitFooter: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: submit) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(isSaving ? mode.savingTitle : mode.actionTitle)
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
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1.0 : 0.7)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
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
                            ExploreHashtagPill(hashtag: hashtag)
                        }
                        .buttonStyle(.plain)
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
        guard mediaItems.isEmpty || selectedMediaCount > 0 else {
            HapticManager.shared.triggerErrorThump()
            return
        }

        let trimmedNotes = fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedMediaItems: [ExplorePostMediaSelection]? = mediaItems.isEmpty
            ? nil
            : mediaItems
                .filter(\.isIncluded)
                .enumerated()
                .map { orderIndex, item in item.selection(orderIndex: orderIndex) }

        onSubmit(
            ExplorePostComposerDraft(
                selectedCommonName: selectedCommonName,
                fieldNotes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                fieldNotesArePublic: fieldNotesArePublic,
                hashtags: normalizedHashtags,
                locationSharing: locationSharing,
                mediaItems: selectedMediaItems
            )
        )
    }

    private func toggleMediaItem(_ id: String) {
        guard let index = mediaItems.firstIndex(where: { $0.id == id }) else { return }
        if mediaItems[index].isIncluded && selectedMediaCount <= 1 {
            HapticManager.shared.triggerErrorThump()
            return
        }

        mediaItems[index].isIncluded.toggle()
        HapticManager.shared.triggerSelectionPulse()
    }

    private static func cleanedCommonName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
