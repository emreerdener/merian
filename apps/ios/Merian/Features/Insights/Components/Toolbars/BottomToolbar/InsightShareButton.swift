import SwiftUI

struct InsightShareButton: View {
    enum PendingAction {
        case externalShare
        case askCommunity
        case composeExplorePost
        case publishExploreAnyway
        case editExplorePost
        case viewCommunityRequest
        case viewInExplore
    }

    let shareExternally: () -> Void
    let onShareToExplore: ((ExplorePostComposerDraft) -> Void)?
    let onEditExplorePost: ((ExplorePostComposerDraft) -> Void)?
    let onAskCommunity: (() -> Void)?
    let isSharingToExplore: Bool
    let isUpdatingExplorePostContent: Bool
    let isUpdatingExploreFieldNotes: Bool
    let speciesName: String
    let scientificName: String
    var commonNameOptions: [String]
    var initialSelectedCommonName: String
    var heroImageUrl: String?
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
    var onUpdateFieldNotesVisibility: ((Bool) async -> FieldNotesVisibilityUpdateFeedback)?
    
    @Environment(\.colorScheme) var colorScheme
    @State var showingOptions = false
    @State var showingExploreComposer = false
    @State var showingExplorePublishConfirmation = false
    @State var pendingAction: PendingAction?
    @State var fieldNotesVisibilityFeedback: FieldNotesVisibilityUpdateFeedback?

    private var showsExploreAction: Bool {
        onShareToExplore != nil
            || onEditExplorePost != nil
            || onAskCommunity != nil
            || onViewCommunityRequest != nil
            || onViewInExplore != nil
    }

    var hasFieldNotesToShare: Bool {
        fieldNotesPreview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var fieldNotesExcerpt: String? {
        guard let preview = fieldNotesPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preview.isEmpty else {
            return nil
        }

        if preview.count <= 160 {
            return preview
        }

        return String(preview.prefix(157)) + "..."
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
            return "View request"
        case .communityResolvedNeedsPublish, .publishToExplore:
            return "Share discovery"
        }
    }

    var exploreDescription: String {
        if sharedExplorePostId != nil {
            return "This discovery is visible to the community."
        }

        switch shareRecommendation {
        case .askCommunity:
            return "This match is not strong yet. Make it public as an identification request before publishing it to Explore."
        case .communityPending:
            return "This scan is public in Identify while the community reviews the ID."
        case .communityResolvedNeedsPublish:
            return "The community identified this request. Publish it to Explore when you are ready."
        case .publishToExplore:
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
                showingExploreComposer = true
            }
        } message: {
            Text("This ID is not confirmed yet. Ask the community first when you want help preventing an incorrect discovery from appearing in Explore.")
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
                hashtagSuggestionContext: hashtagSuggestionContext.updating(fieldNotes: fieldNotesPreview),
                isSaving: sharedExplorePostId == nil ? isSharingToExplore : isUpdatingExplorePostContent,
                onSubmit: { draft in
                    if sharedExplorePostId == nil {
                        onShareToExplore?(draft)
                    } else {
                        onEditExplorePost?(draft)
                    }
                    showingExploreComposer = false
                }
            )
        }
        .task(id: fieldNotesVisibilityFeedback?.message) {
            guard fieldNotesVisibilityFeedback != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                fieldNotesVisibilityFeedback = nil
            }
        }
    }

}
