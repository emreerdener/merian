import SwiftUI

enum InsightTopMenuCommunityAction: Equatable {
    case askCommunity
    case viewCommunityRequest

    var title: String {
        switch self {
        case .askCommunity:
            return "Ask the community"
        case .viewCommunityRequest:
            return "View community request"
        }
    }

    var systemImage: String {
        switch self {
        case .askCommunity:
            return "person.crop.badge.magnifyingglass"
        case .viewCommunityRequest:
            return "person.crop.circle.badge.questionmark"
        }
    }
}

struct InsightTopMenuState: Equatable {
    let showsExplorePostSection: Bool
    let communityAction: InsightTopMenuCommunityAction?

    init(
        sharedExplorePostId: String?,
        sharedCommunityIdentificationRequestId: String?,
        canEditExplorePost: Bool,
        canViewExplorePost: Bool,
        canAskCommunity: Bool,
        canViewCommunityRequest: Bool
    ) {
        let hasPublishedPost = sharedExplorePostId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasCommunityRequest = sharedCommunityIdentificationRequestId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false

        showsExplorePostSection = hasPublishedPost && (canEditExplorePost || canViewExplorePost)

        if hasCommunityRequest, canViewCommunityRequest {
            communityAction = .viewCommunityRequest
        } else if canAskCommunity {
            communityAction = .askCommunity
        } else {
            communityAction = nil
        }
    }
}

struct TopToolbar: ToolbarContent {
    enum LeadingControl {
        case close
        case back

        var systemImage: String {
            switch self {
            case .close:
                return "xmark"
            case .back:
                return "chevron.left"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .close:
                return "Close"
            case .back:
                return "Back"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .close:
                return "InsightSheetCloseButton"
            case .back:
                return "InsightSheetBackButton"
            }
        }
    }

    @Environment(\.dismiss) var dismiss
    
    let commonName: String
    let isCommonNameScrolledPast: Bool
    @Binding var isSavingMedia: Bool
    @Binding var showDeleteConfirmation: Bool
    let hasUserMedia: Bool
    var leadingControl: LeadingControl = .close
    let onSaveMedia: () -> Void
    let allowsFieldNotes: Bool
    let hasFieldNotes: Bool
    let onFieldNotes: () -> Void
    let allowsCollectionActions: Bool
    let collections: [ScanCollection]
    let selectedCollectionIds: Set<String>
    let toggleScanInCollection: (ScanCollection) -> Void
    @Binding var showNewCollectionAlert: Bool
    let hasCollectionScanId: Bool
    var onReanalyze: (() -> Void)?
    var onReviewAlternatives: (() -> Void)?
    var onConfirmIdentification: (() -> Void)?
    var onAskCommunity: (() -> Void)?
    var sharedExplorePostId: String?
    var sharedCommunityIdentificationRequestId: String?
    var onEditExplorePost: (() -> Void)?
    var onViewExplorePost: (() -> Void)?
    var onViewCommunityRequest: (() -> Void)?
    var audioBoostEnabled: Binding<Bool>?
    var onAudioBoostEnableRequested: (() -> Void)?
    let showsQueuedDeleteAction: Bool
    let isAnalyzing: Bool
    let isProActive: Bool

    init(
        commonName: String,
        isCommonNameScrolledPast: Bool,
        isSavingMedia: Binding<Bool>,
        showDeleteConfirmation: Binding<Bool>,
        hasUserMedia: Bool,
        leadingControl: LeadingControl = .close,
        onSaveMedia: @escaping () -> Void,
        allowsFieldNotes: Bool = true,
        hasFieldNotes: Bool,
        onFieldNotes: @escaping () -> Void,
        allowsCollectionActions: Bool = true,
        collections: [ScanCollection],
        selectedCollectionIds: Set<String>,
        toggleScanInCollection: @escaping (ScanCollection) -> Void,
        showNewCollectionAlert: Binding<Bool>,
        hasCollectionScanId: Bool,
        onReanalyze: (() -> Void)? = nil,
        onReviewAlternatives: (() -> Void)? = nil,
        onConfirmIdentification: (() -> Void)? = nil,
        onAskCommunity: (() -> Void)? = nil,
        sharedExplorePostId: String? = nil,
        sharedCommunityIdentificationRequestId: String? = nil,
        onEditExplorePost: (() -> Void)? = nil,
        onViewExplorePost: (() -> Void)? = nil,
        onViewCommunityRequest: (() -> Void)? = nil,
        audioBoostEnabled: Binding<Bool>? = nil,
        onAudioBoostEnableRequested: (() -> Void)? = nil,
        showsQueuedDeleteAction: Bool = false,
        isAnalyzing: Bool,
        isProActive: Bool
    ) {
        self.commonName = commonName
        self.isCommonNameScrolledPast = isCommonNameScrolledPast
        self._isSavingMedia = isSavingMedia
        self._showDeleteConfirmation = showDeleteConfirmation
        self.hasUserMedia = hasUserMedia
        self.leadingControl = leadingControl
        self.onSaveMedia = onSaveMedia
        self.allowsFieldNotes = allowsFieldNotes
        self.hasFieldNotes = hasFieldNotes
        self.onFieldNotes = onFieldNotes
        self.allowsCollectionActions = allowsCollectionActions
        self.collections = collections
        self.selectedCollectionIds = selectedCollectionIds
        self.toggleScanInCollection = toggleScanInCollection
        self._showNewCollectionAlert = showNewCollectionAlert
        self.hasCollectionScanId = hasCollectionScanId
        self.onReanalyze = onReanalyze
        self.onReviewAlternatives = onReviewAlternatives
        self.onConfirmIdentification = onConfirmIdentification
        self.onAskCommunity = onAskCommunity
        self.sharedExplorePostId = sharedExplorePostId
        self.sharedCommunityIdentificationRequestId = sharedCommunityIdentificationRequestId
        self.onEditExplorePost = onEditExplorePost
        self.onViewExplorePost = onViewExplorePost
        self.onViewCommunityRequest = onViewCommunityRequest
        self.audioBoostEnabled = audioBoostEnabled
        self.onAudioBoostEnableRequested = onAudioBoostEnableRequested
        self.showsQueuedDeleteAction = showsQueuedDeleteAction
        self.isAnalyzing = isAnalyzing
        self.isProActive = isProActive
    }
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
                toolbarIcon(leadingControl.systemImage)
                    .imageOverlayToolbarIconChrome(isFallbackActive: shouldUseContainedToolbarChrome)
            }
            .accessibilityLabel(leadingControl.accessibilityLabel)
            .accessibilityIdentifier(leadingControl.accessibilityIdentifier)
            .imageOverlayToolbarButtonChrome(isFallbackActive: shouldUseContainedToolbarChrome)
        }
        
        ToolbarItem(placement: .principal) {
            ScrollAwareToolbarTitleBadge(
                title: commonName,
                isVisible: isCommonNameScrolledPast
            )
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            ZStack {
                queuedDeleteButton
                    .opacity(showsQueuedDeleteAction ? 1 : 0)
                    .disabled(!showsQueuedDeleteAction)
                    .accessibilityHidden(!showsQueuedDeleteAction)
                    .accessibilityIdentifier(
                        showsQueuedDeleteAction
                            ? "InsightQueuedDeleteButton"
                            : ""
                    )

                if !isAnalyzing && !showsQueuedDeleteAction {
                    Menu {
                        actionMenuContent
                    } label: {
                        toolbarIcon("ellipsis")
                            .imageOverlayToolbarIconChrome(isFallbackActive: shouldUseContainedToolbarChrome)
                    }
                    .accessibilityIdentifier("InsightTopMenu")
                    .accessibilityLabel("Scan actions")
                    .imageOverlayToolbarButtonChrome(isFallbackActive: shouldUseContainedToolbarChrome)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showsQueuedDeleteAction)
        }
    }

    private var shouldUseContainedToolbarChrome: Bool {
        ImageOverlayToolbarChrome.shouldUseContainedBackground
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .bold))
    }

    private var queuedDeleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            toolbarIcon("trash")
                .imageOverlayToolbarIconChrome(
                    isFallbackActive: shouldUseContainedToolbarChrome,
                    foregroundColor: .red
                )
        }
        .tint(.red)
        .accessibilityLabel("Delete scan")
        .imageOverlayToolbarButtonChrome(
            isFallbackActive: shouldUseContainedToolbarChrome
        )
    }

    private var menuState: InsightTopMenuState {
        InsightTopMenuState(
            sharedExplorePostId: sharedExplorePostId,
            sharedCommunityIdentificationRequestId: sharedCommunityIdentificationRequestId,
            canEditExplorePost: onEditExplorePost != nil,
            canViewExplorePost: onViewExplorePost != nil,
            canAskCommunity: onAskCommunity != nil,
            canViewCommunityRequest: onViewCommunityRequest != nil
        )
    }

    @ViewBuilder
    private var actionMenuContent: some View {
        if let audioBoostEnabled {
            Button {
                let wasEnabled = audioBoostEnabled.wrappedValue
                if !wasEnabled {
                    onAudioBoostEnableRequested?()
                }
                audioBoostEnabled.wrappedValue.toggle()
                let isEnabled = audioBoostEnabled.wrappedValue
                guard isEnabled != wasEnabled else { return }
                if isEnabled {
                    HapticManager.shared.triggerMediumPulse(source: "media.insight.audioBoost.enabled")
                } else {
                    HapticManager.shared.triggerLightImpact(
                        intensity: 0.5,
                        source: "media.insight.audioBoost.disabled"
                    )
                }
            } label: {
                Label(
                    audioBoostEnabled.wrappedValue ? "Turn off audio boost" : "Boost audio",
                    systemImage: audioBoostEnabled.wrappedValue ? "speaker.wave.2" : "speaker.wave.3"
                )
            }
        }

        if hasUserMedia {
            Button(action: { onSaveMedia() }) {
                Label("Download scan", systemImage: "arrow.down.circle")
            }
        }

        if allowsFieldNotes {
            Button(action: onFieldNotes) {
                Label(hasFieldNotes ? "Edit field notes" : "Add field notes", systemImage: "square.and.pencil")
            }
        }

        if allowsCollectionActions {
            AddCollectionTopMenu(
                collections: collections,
                selectedCollectionIds: selectedCollectionIds,
                toggleScanInCollection: toggleScanInCollection,
                showNewCollectionAlert: $showNewCollectionAlert,
                hasScanId: hasCollectionScanId
            )
        }

        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
            Label("Delete scan", systemImage: "trash")
        }

        if menuState.showsExplorePostSection {
            Section("Explore post") {
                if let onEditExplorePost {
                    Button(action: onEditExplorePost) {
                        Label("Edit post", systemImage: "square.and.pencil")
                    }
                }

                if let onViewExplorePost {
                    Button(action: onViewExplorePost) {
                        Label("View post", systemImage: "eye")
                    }
                }
            }
        }
        
        Section("Identification") {
            if let onConfirmIdentification = onConfirmIdentification {
                Button(action: onConfirmIdentification) {
                    Label("Confirm species", systemImage: "checkmark.circle")
                }
            }
            if let onReviewAlternatives = onReviewAlternatives {
                Button(action: onReviewAlternatives) {
                    Label("Review alternatives", systemImage: "person.fill.checkmark.and.xmark")
                }
            }
            if let onReanalyze = onReanalyze {
                Button(action: onReanalyze) {
                    if isProActive {
                        Label("Reanalyze species", systemImage: "arrow.2.circlepath")
                    } else {
                        Label("Reanalyze species", systemImage: "lock.fill")
                    }
                }
            }
            if let communityAction = menuState.communityAction {
                Button(action: {
                    switch communityAction {
                    case .askCommunity:
                        onAskCommunity?()
                    case .viewCommunityRequest:
                        onViewCommunityRequest?()
                    }
                }) {
                    Label(communityAction.title, systemImage: communityAction.systemImage)
                }
            }
        }
        
    }
}

// MARK: - Isolated Header Component
struct ScrollAwareToolbarTitleBadge: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let title: String
    let isVisible: Bool

    private var maximumWidth: CGFloat {
        horizontalSizeClass == .regular ? 320 : 200
    }
    
    var body: some View {
        ZStack {
            if !title.isEmpty {
                Text(title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: maximumWidth)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .accessibilityLabel(title)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.85)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .accessibilityHidden(!isVisible || title.isEmpty)
    }
}
