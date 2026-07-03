import SwiftUI
import UniformTypeIdentifiers

enum ExplorePostComposerMode {
    case create
    case edit

    var title: String {
        switch self {
        case .create:
            return "Share with community"
        case .edit:
            return "Edit post"
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
            return "Show broad label and add to Explore Map."
        case .obscured:
            return "Show broad label and keep off Explore Map."
        case .privateLocation:
            return "Share this post without public location."
        }
    }
}

enum ExplorePostComposerMediaKind: String, Equatable {
    case image
    case video
}

struct ExplorePostMediaSelection: Equatable {
    let kind: ExplorePostComposerMediaKind
    let sourceMediaId: String?
    let sourceIndex: Int?
    let thumbnailSourceIndex: Int?
    let url: String?
    let thumbnailUrl: String?
    let orderIndex: Int

    var jsonObject: [String: Any] {
        var payload: [String: Any] = [
            "kind": kind.rawValue,
            "order_index": orderIndex
        ]

        if let sourceMediaId {
            payload["source_media_id"] = sourceMediaId
        }
        if let sourceIndex {
            payload["source_index"] = sourceIndex
        }
        if let thumbnailSourceIndex {
            payload["thumbnail_source_index"] = thumbnailSourceIndex
        }
        if let url {
            payload["url"] = url
        }
        if let thumbnailUrl {
            payload["thumbnail_url"] = thumbnailUrl
        }

        return payload
    }
}

struct ExplorePostComposerMediaDraft: Identifiable, Equatable {
    let id: String
    let kind: ExplorePostComposerMediaKind
    let previewPath: String
    let sourceMediaId: String?
    let sourceIndex: Int?
    let thumbnailSourceIndex: Int?
    let url: String?
    let thumbnailUrl: String?
    var isIncluded: Bool

    var isVideo: Bool {
        kind == .video
    }

    func selection(orderIndex: Int) -> ExplorePostMediaSelection {
        ExplorePostMediaSelection(
            kind: kind,
            sourceMediaId: sourceMediaId,
            sourceIndex: sourceIndex,
            thumbnailSourceIndex: thumbnailSourceIndex,
            url: url,
            thumbnailUrl: thumbnailUrl,
            orderIndex: orderIndex
        )
    }

    static func eligibleItems(from snapshot: CapturedMediaSnapshot, scanId: String? = nil) -> [ExplorePostComposerMediaDraft] {
        var drafts: [ExplorePostComposerMediaDraft] = []
        var imageIndex = 0
        var videoIndex = 0
        let items = snapshot.items

        for index in items.indices {
            switch items[index] {
            case .image(let reference):
                let isVideoPoster: Bool
                if items.indices.contains(index + 1),
                   case .video = items[index + 1] {
                    isVideoPoster = true
                } else {
                    isVideoPoster = false
                }

                if !isVideoPoster {
                    drafts.append(
                        ExplorePostComposerMediaDraft(
                            id: "image-\(imageIndex)-\(reference.serializedPath)",
                            kind: .image,
                            previewPath: reference.serializedPath,
                            sourceMediaId: scanId.map { "scan:\($0):image:\(imageIndex)" },
                            sourceIndex: imageIndex,
                            thumbnailSourceIndex: nil,
                            url: nil,
                            thumbnailUrl: nil,
                            isIncluded: true
                        )
                    )
                }

                imageIndex += 1

            case .video(let reference):
                let thumbnailIndex = previousImageIndex(before: index, in: items)
                let previewPath = thumbnailIndex.flatMap { imagePath(at: $0, in: items) } ?? ""
                guard let thumbnailIndex, !previewPath.isEmpty else {
                    videoIndex += 1
                    continue
                }

                drafts.append(
                    ExplorePostComposerMediaDraft(
                        id: "video-\(videoIndex)-\(reference.serializedPath)",
                        kind: .video,
                        previewPath: previewPath,
                        sourceMediaId: scanId.map { "scan:\($0):video:\(videoIndex)" },
                        sourceIndex: videoIndex,
                        thumbnailSourceIndex: thumbnailIndex,
                        url: nil,
                        thumbnailUrl: nil,
                        isIncluded: true
                    )
                )
                videoIndex += 1

            case .audio, .description:
                continue
            }
        }

        return drafts
    }

    static func existingPostItems(from mediaItems: [ExploreMediaItem]) -> [ExplorePostComposerMediaDraft] {
        mediaItems
            .sorted { $0.orderIndex < $1.orderIndex }
            .enumerated()
            .compactMap { offset, item in
                let previewPath = (item.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? item.thumbnailUrl!
                    : item.url
                let kind: ExplorePostComposerMediaKind
                switch item.kind {
                case .image:
                    kind = .image
                case .video:
                    kind = .video
                }

                let trimmedUrl = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedUrl.isEmpty else { return nil }

                return ExplorePostComposerMediaDraft(
                    id: "existing-\(offset)-\(trimmedUrl)",
                    kind: kind,
                    previewPath: previewPath,
                    sourceMediaId: nil,
                    sourceIndex: nil,
                    thumbnailSourceIndex: nil,
                    url: trimmedUrl,
                    thumbnailUrl: item.thumbnailUrl,
                    isIncluded: true
                )
            }
    }

    static func sourceItems(from mediaItems: [ExploreComposerMediaItem]) -> [ExplorePostComposerMediaDraft] {
        mediaItems
            .sorted { lhs, rhs in
                switch (lhs.selectionOrderIndex, rhs.selectionOrderIndex) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.orderIndex < rhs.orderIndex
                }
            }
            .map { item in
                let kind: ExplorePostComposerMediaKind = item.kind == .video ? .video : .image
                let previewPath = item.thumbnailUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? item.url
                    : item.thumbnailUrl

                return ExplorePostComposerMediaDraft(
                    id: item.sourceMediaId,
                    kind: kind,
                    previewPath: previewPath,
                    sourceMediaId: item.sourceMediaId,
                    sourceIndex: nil,
                    thumbnailSourceIndex: nil,
                    url: nil,
                    thumbnailUrl: item.thumbnailUrl,
                    isIncluded: item.isSelected ?? true
                )
            }
    }

    private static func previousImageIndex(before itemIndex: Int, in items: [SerializedMediaItem]) -> Int? {
        guard itemIndex > 0 else { return nil }
        var imageIndex = 0
        var mostRecentImageIndex: Int?

        for index in 0..<itemIndex {
            if case .image = items[index] {
                mostRecentImageIndex = imageIndex
                imageIndex += 1
            }
        }

        return mostRecentImageIndex
    }

    private static func imagePath(at targetImageIndex: Int, in items: [SerializedMediaItem]) -> String? {
        var imageIndex = 0
        for item in items {
            guard case .image(let reference) = item else { continue }
            if imageIndex == targetImageIndex {
                return reference.serializedPath
            }
            imageIndex += 1
        }
        return nil
    }
}

struct ExplorePostComposerDraft {
    let selectedCommonName: String
    let fieldNotes: String?
    let fieldNotesArePublic: Bool
    let hashtags: [String]
    let locationSharing: ExplorePostLocationSharing
    let mediaItems: [ExplorePostMediaSelection]?

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
    @State private var mediaItems: [ExplorePostComposerMediaDraft]
    @State private var draggedMediaItemId: String?
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

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isNotesFocused = false
                    }
                    .fontWeight(.semibold)
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
        .task(id: activeHeroImageUrl) {
            loadedImage = nil
            guard let activeHeroImageUrl else { return }
            loadedImage = await LocalImageLoader.shared.loadImage(fromPath: activeHeroImageUrl, fallbackUrl: nil, maxDimension: 124)
        }
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

private struct ExplorePostComposerMediaTile: View {
    let item: ExplorePostComposerMediaDraft
    let isCover: Bool
    let canDeselect: Bool
    let onToggle: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(uiColor: .tertiarySystemFill)
                            .overlay {
                                Image(systemName: item.isVideo ? "play.rectangle.fill" : "photo")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 94, height: 94)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(item.isIncluded ? 1 : 0.38)

                VStack(alignment: .trailing, spacing: 6) {
                    Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(item.isIncluded ? Color.white : Color.secondary, item.isIncluded ? Color.accentColor : Color.clear)
                        .shadow(color: .black.opacity(item.isIncluded ? 0.28 : 0), radius: 4, y: 1)

                    if item.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.58), in: Circle())
                    }
                }
                .padding(6)

                VStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .bold))
                        Text(isCover ? "Cover" : item.kind.rawValue.capitalized)
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.56))
                }
                .frame(width: 94, height: 94)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isCover ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isCover ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canDeselect && item.isIncluded)
        .accessibilityLabel(item.isVideo ? "Video media" : "Image media")
        .accessibilityHint(isCover ? "Selected as the cover. Drag to reorder." : "Tap to include or exclude. Drag to reorder.")
        .task(id: item.previewPath) {
            image = await LocalImageLoader.shared.loadImage(fromPath: item.previewPath, fallbackUrl: nil, maxDimension: 188)
        }
    }
}

private struct ExplorePostComposerMediaDropDelegate: DropDelegate {
    let targetItem: ExplorePostComposerMediaDraft
    @Binding var mediaItems: [ExplorePostComposerMediaDraft]
    @Binding var draggedMediaItemId: String?

    func dropEntered(info: DropInfo) {
        guard let draggedMediaItemId,
              draggedMediaItemId != targetItem.id,
              let fromIndex = mediaItems.firstIndex(where: { $0.id == draggedMediaItemId }),
              let toIndex = mediaItems.firstIndex(where: { $0.id == targetItem.id }) else {
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            mediaItems.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedMediaItemId = nil
        HapticManager.shared.triggerSelectionPulse()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
