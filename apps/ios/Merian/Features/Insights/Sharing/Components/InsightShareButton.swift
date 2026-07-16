import SwiftUI

struct InsightShareButton: View {
    enum PendingAction {
        case externalShare
        case askCommunity
        case composeExplorePost
        case publishExploreAnyway
        case editExplorePost
        case editCommunityRequest
        case viewCommunityRequest
        case viewInExplore
    }

    let shareExternally: () -> Void
    let onShareToExplore: ((ExplorePostComposerDraft) -> Void)?
    let onEditExplorePost: ((ExplorePostComposerDraft) -> Void)?
    let onAskCommunity: (() -> Void)?
    let onEditCommunityRequest: (() -> Void)?
    let isSharingToExplore: Bool
    let isUpdatingExplorePostContent: Bool
    let speciesName: String
    let scientificName: String
    var commonNameOptions: [String]
    var initialSelectedCommonName: String
    var heroImageUrl: String?
    var scanId: String?
    var mediaItems: [ExplorePostComposerMediaDraft] = []
    var publicLocationLabel: String?
    var fieldNotesPreview: String?
    var hashtagSuggestionContext: ExploreHashtagSuggestionContext
    var sharedExploreHashtags: [String]
    var sharedExplorePostId: String?
    var shareRecommendation: InsightShareRecommendation
    var initialLocationSharing: ExplorePostLocationSharing
    var fieldNotesArePublicOnExplore: Bool
    var onViewInExplore: (() -> Void)?
    var onViewCommunityRequest: (() -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @State var showingOptions = false
    @State var showingExploreComposer = false
    @State var showingExplorePublishConfirmation = false
    @State private var isAwaitingExploreShareResult = false
    @State var pendingAction: PendingAction?
    @State var composerMediaItems: [ExplorePostComposerMediaDraft]?
    @State var challengeEventHashtags: [String] = []

    private var showsExploreAction: Bool {
        onShareToExplore != nil
            || onEditExplorePost != nil
            || onAskCommunity != nil
            || onEditCommunityRequest != nil
            || onViewCommunityRequest != nil
            || onViewInExplore != nil
    }

    var exploreHeadline: String {
        if sharedExplorePostId != nil {
            return "Published"
        }

        switch shareRecommendation {
        case .askCommunity:
            return "Ask the community"
        case .communityPending:
            return "Identify request"
        case .communityResolvedNeedsPublish:
            return "Ready to publish"
        case .publishToExplore:
            return "Share with community"
        }
    }

    // BUTTONS TEXT
    var exploreActionTitle: String {
        if sharedExplorePostId != nil {
            return "View post"
        }

        switch shareRecommendation {
        case .askCommunity:
            return "Ask for ID"
        case .communityPending:
            return "Edit request"
        case .communityResolvedNeedsPublish, .publishToExplore:
            return "Share discovery"
        }
    }

    var exploreActionSystemImage: String {
        switch shareRecommendation {
        case .askCommunity:
            return "person.crop.badge.magnifyingglass"
        case .communityPending:
            return "square.and.pencil"
        case .communityResolvedNeedsPublish, .publishToExplore:
            return "safari"
        }
    }

    var exploreDescription: String {
        if sharedExplorePostId != nil {
            return "This discovery is visible to the community."
        }

        switch shareRecommendation {
        case .askCommunity:
            return "Get help from other Naturebook explorers before adding this discovery to Explore observations."
        case .communityPending:
            return "This scan is public in Identify while the community reviews the ID."
        case .communityResolvedNeedsPublish:
            return "The community identified this request. Publish it to Explore when you are ready."
        case .publishToExplore:
            return "Publish this discovery so others can learn and explore."
        }
    }

    var pendingCommunityPublishDisclaimer: String {
        "The community is still reviewing this ID. Publish only if you are comfortable making it visible in Explore now."
    }

    var explorePublishConfirmationMessage: String {
        switch shareRecommendation {
        case .communityPending:
            return pendingCommunityPublishDisclaimer
        case .askCommunity:
            return "This ID has not been confirmed yet. Ask the community first if you want help verifying it before publishing."
        case .communityResolvedNeedsPublish, .publishToExplore:
            return "Publish this discovery so others can learn and explore."
        }
    }

    var primaryBlue: Color {
        Color.accentColor
    }

    var exploreActionFillColor: Color {
        sharedExplorePostId == nil ? (colorScheme == .dark ? .white : .black) : primaryBlue
    }

    var exploreActionForegroundColor: Color {
        sharedExplorePostId == nil ? Color(uiColor: .systemBackground) : .white
    }

    // MARK: - Body
    var body: some View {
        Button(action: {
            if showsExploreAction {
                showingOptions = true
            } else {
                shareExternally()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                Text("Share")
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(primaryBlue)
        .sheet(isPresented: $showingOptions, onDismiss: handlePendingAction) {
            shareOptionsSheet
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Publish to Explore anyway?", isPresented: $showingExplorePublishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Publish anyway") {
                openExploreComposer()
            }
        } message: {
            Text(explorePublishConfirmationMessage)
        }
        .sheet(isPresented: $showingExploreComposer) {
            ExplorePostComposerView(
                mode: sharedExplorePostId == nil ? .create : .edit,
                speciesName: speciesName,
                scientificName: scientificName,
                heroImageUrl: heroImageUrl,
                publicLocationLabel: publicLocationLabel,
                commonNameOptions: commonNameOptions,
                initialSelectedCommonName: initialSelectedCommonName,
                initialFieldNotes: fieldNotesPreview,
                initialFieldNotesArePublic: sharedExplorePostId == nil ? true : fieldNotesArePublicOnExplore,
                initialHashtags: sharedExplorePostId == nil ? [] : sharedExploreHashtags,
                initialLocationSharing: initialLocationSharing,
                mediaItems: composerMediaItems ?? mediaItems,
                hashtagSuggestionContext: hashtagSuggestionContext
                    .updating(fieldNotes: fieldNotesPreview)
                    .updating(eventHashtags: challengeEventHashtags),
                isSaving: sharedExplorePostId == nil ? isSharingToExplore : isUpdatingExplorePostContent,
                onSubmit: { draft in
                    if sharedExplorePostId == nil {
                        isAwaitingExploreShareResult = true
                        onShareToExplore?(draft)
                    } else {
                        onEditExplorePost?(draft)
                        showingExploreComposer = false
                    }
                }
            )
            .interactiveDismissDisabled(isSharingToExplore)
        }
        .onChange(of: isSharingToExplore) { wasSharing, isSharing in
            guard isAwaitingExploreShareResult, wasSharing, !isSharing else { return }
            isAwaitingExploreShareResult = false
            showingExploreComposer = false
        }
        .task(id: scanId) {
            await loadChallengeEventHashtags()
        }
    }

    private func loadChallengeEventHashtags() async {
        guard let scanId = scanId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scanId.isEmpty else {
            challengeEventHashtags = []
            return
        }

        do {
            challengeEventHashtags = try await MerianNetworkClient.shared.getFieldTripChallengeHashtags(scanId: scanId)
        } catch {
            challengeEventHashtags = []
        }
    }
}
