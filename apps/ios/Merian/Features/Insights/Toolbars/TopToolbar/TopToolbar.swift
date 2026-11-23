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

    @State private var showsIncorrectConfirmation = false
    @State private var pendingIncorrectAction: (() -> Void)?
    @State private var pendingConfirmationUndo: (() -> Void)?

    @Environment(\.dismiss) var dismiss

    let commonName: String
    let isCommonNameScrolledPast: Bool
    let onDismiss: (() -> Void)?
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
    var onIdentification: (() -> Void)?
    var onIdentificationHistory: (() -> Void)?
    var onReanalysisStatus: (() -> Void)?
    var onReanalyze: (() -> Void)?
    let reanalysisRequiresPro: Bool
    var onReviewAlternatives: (() -> Void)?
    var onConfirmIdentification: (() -> Void)?
    var confirmationTitle: String
    var onRetryReviewSave: (() -> Void)?
    var onUndoIncorrect: (() -> Void)?
    var onUndoConfirmation: (() -> Void)?
    var undoConfirmationRequiresPrompt: Bool
    var confirmationUndoReason: String?
    var reviewUnavailableReason: String?
    var onMarkIncorrect: (() -> Void)?
    var onAskCommunity: (() -> Void)?
    var sharedExplorePostId: String?
    var sharedCommunityIdentificationRequestId: String?
    var onEditExplorePost: (() -> Void)?
    var onViewExplorePost: (() -> Void)?
    var onViewCommunityRequest: (() -> Void)?
    var audioBoostEnabled: Binding<Bool>?
    var onAudioBoostEnableRequested: (() -> Void)?
    var onAudioBoostChanged: ((Bool) -> Void)?
    let showsQueuedDeleteAction: Bool
    let isAnalyzing: Bool
    let isProActive: Bool

    init(
        commonName: String,
        isCommonNameScrolledPast: Bool,
        onDismiss: (() -> Void)? = nil,
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
        onIdentification: (() -> Void)? = nil,
        onIdentificationHistory: (() -> Void)? = nil,
        onReanalysisStatus: (() -> Void)? = nil,
        onReanalyze: (() -> Void)? = nil,
        reanalysisRequiresPro: Bool? = nil,
        onReviewAlternatives: (() -> Void)? = nil,
        onConfirmIdentification: (() -> Void)? = nil,
        confirmationTitle: String = "Confirm species",
        onRetryReviewSave: (() -> Void)? = nil,
        onUndoIncorrect: (() -> Void)? = nil,
        onUndoConfirmation: (() -> Void)? = nil,
        undoConfirmationRequiresPrompt: Bool = false,
        confirmationUndoReason: String? = nil,
        reviewUnavailableReason: String? = nil,
        onMarkIncorrect: (() -> Void)? = nil,
        onAskCommunity: (() -> Void)? = nil,
        sharedExplorePostId: String? = nil,
        sharedCommunityIdentificationRequestId: String? = nil,
        onEditExplorePost: (() -> Void)? = nil,
        onViewExplorePost: (() -> Void)? = nil,
        onViewCommunityRequest: (() -> Void)? = nil,
        audioBoostEnabled: Binding<Bool>? = nil,
        onAudioBoostEnableRequested: (() -> Void)? = nil,
        onAudioBoostChanged: ((Bool) -> Void)? = nil,
        showsQueuedDeleteAction: Bool = false,
        isAnalyzing: Bool,
        isProActive: Bool
    ) {
        self.commonName = commonName
        self.isCommonNameScrolledPast = isCommonNameScrolledPast
        self.onDismiss = onDismiss
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
        self.onIdentification = onIdentification
        self.onIdentificationHistory = onIdentificationHistory
        self.onReanalysisStatus = onReanalysisStatus
        self.onReanalyze = onReanalyze
        self.reanalysisRequiresPro = reanalysisRequiresPro ?? !isProActive
        self.onReviewAlternatives = onReviewAlternatives
        self.onConfirmIdentification = onConfirmIdentification
        self.confirmationTitle = confirmationTitle
        self.onRetryReviewSave = onRetryReviewSave
        self.onUndoIncorrect = onUndoIncorrect
        self.onUndoConfirmation = onUndoConfirmation
        self.undoConfirmationRequiresPrompt = undoConfirmationRequiresPrompt
        self.confirmationUndoReason = confirmationUndoReason
        self.reviewUnavailableReason = reviewUnavailableReason
        self.onMarkIncorrect = onMarkIncorrect
        self.onAskCommunity = onAskCommunity
        self.sharedExplorePostId = sharedExplorePostId
        self.sharedCommunityIdentificationRequestId = sharedCommunityIdentificationRequestId
        self.onEditExplorePost = onEditExplorePost
        self.onViewExplorePost = onViewExplorePost
        self.onViewCommunityRequest = onViewCommunityRequest
        self.audioBoostEnabled = audioBoostEnabled
        self.onAudioBoostEnableRequested = onAudioBoostEnableRequested
        self.onAudioBoostChanged = onAudioBoostChanged
        self.showsQueuedDeleteAction = showsQueuedDeleteAction
        self.isAnalyzing = isAnalyzing
        self.isProActive = isProActive
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            } label: {
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

        trailingToolbarItem
    }

    private var showsTrailingToolbarControl: Bool {
        showsQueuedDeleteAction || !isAnalyzing
    }

    @ToolbarContentBuilder
    private var trailingToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            // A clear toolbar item still receives Liquid Glass on iOS 26.
            // Hide only that background while no real control is present.
            baseTrailingToolbarItem
                .sharedBackgroundVisibility(
                    showsTrailingToolbarControl ? .automatic : .hidden
                )
        } else {
            baseTrailingToolbarItem
        }
    }

    private var baseTrailingToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Group {
                if showsQueuedDeleteAction {
                    queuedDeleteButton
                        .accessibilityIdentifier(
                            "InsightQueuedDeleteButton"
                        )
                        .transition(.opacity)
                } else if !isAnalyzing {
                    trailingActionMenu
                        .transition(.opacity)
                } else {
                    // Keep the item stable without presenting a control.
                    Color.clear
                        .frame(width: 44, height: 44)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(
                .easeInOut(duration: 0.2),
                value: showsTrailingToolbarControl
            )
        }
    }

    private var trailingActionMenu: some View {
        Menu {
            actionMenuContent
        } label: {
            toolbarIcon("ellipsis")
                .imageOverlayToolbarIconChrome(
                    isFallbackActive: shouldUseContainedToolbarChrome
                )
        }
        .confirmationUndoPrompt(action: $pendingConfirmationUndo)
        .alert("Mark identification as incorrect?", isPresented: $showsIncorrectConfirmation) {
            Button("Mark as incorrect", role: .destructive) {
                let action = pendingIncorrectAction
                pendingIncorrectAction = nil
                action?()
            }
            Button("Cancel", role: .cancel) {
                pendingIncorrectAction = nil
            }
        } message: {
            Text("Your scan, photos, and notes will be kept.")
        }
        .accessibilityIdentifier("InsightTopMenu")
        .accessibilityLabel("Scan actions")
        .buttonBorderShape(.circle)
        .imageOverlayToolbarButtonChrome(
            isFallbackActive: shouldUseContainedToolbarChrome
        )
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
        .buttonBorderShape(.circle)
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

    private var identificationMenuSymbol: String {
        if #available(iOS 26.0, *) { return "sparkle.text.clipboard" }
        return "list.clipboard"
    }

    private var fieldNotesMenuSymbol: String {
        if #available(iOS 18.4, *) { return "long.text.page.and.pencil" }
        return "square.and.pencil"
    }

    @ViewBuilder
    private var actionMenuContent: some View {
        ControlGroup {
            if let onIdentification {
                Button(action: onIdentification) {
                    Label("Identification", systemImage: identificationMenuSymbol)
                }
                .accessibilityIdentifier("IdentificationMenu")
            }
            if allowsFieldNotes {
                Button(action: onFieldNotes) {
                    Label("Field notes", systemImage: fieldNotesMenuSymbol)
                }
            }
        }
        .labelStyle(.titleAndIcon)
        Divider()

        if allowsCollectionActions {
            AddCollectionTopMenu(
                collections: collections,
                selectedCollectionIds: selectedCollectionIds,
                toggleScanInCollection: toggleScanInCollection,
                showNewCollectionAlert: $showNewCollectionAlert,
                hasScanId: hasCollectionScanId
            )
        }

        if hasUserMedia {
            Button(action: onSaveMedia) {
                Label("Download media", systemImage: "square.and.arrow.down")
            }
            .disabled(isSavingMedia)
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

        Divider()
        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
            Label("Delete scan", systemImage: "trash")
        }
    }
}
