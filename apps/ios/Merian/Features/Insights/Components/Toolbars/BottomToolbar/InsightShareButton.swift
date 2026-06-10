import SwiftUI

struct InsightShareButton: View {
    enum PendingAction {
        case externalShare
        case composeExplorePost
        case editExplorePost
        case viewInExplore
    }

    let shareExternally: () -> Void
    let onShareToExplore: ((ExplorePostComposerDraft) -> Void)?
    let onEditExplorePost: ((ExplorePostComposerDraft) -> Void)?
    let isSharingToExplore: Bool
    let isUpdatingExplorePostContent: Bool
    let isUpdatingExploreFieldNotes: Bool
    let speciesName: String
    let scientificName: String
    var heroImageUrl: String?
    var publicLocationLabel: String?
    var fieldNotesPreview: String?
    var hashtagSuggestionContext: ExploreHashtagSuggestionContext
    var sharedExploreHashtags: [String]
    var sharedExplorePostId: String?
    var fieldNotesArePublicOnExplore: Bool
    var onViewInExplore: (() -> Void)?
    var onUpdateFieldNotesVisibility: ((Bool) async -> FieldNotesVisibilityUpdateFeedback)?
    
    @Environment(\.colorScheme) var colorScheme
    @State var showingOptions = false
    @State var showingExploreComposer = false
    @State var pendingAction: PendingAction?
    @State var fieldNotesVisibilityFeedback: FieldNotesVisibilityUpdateFeedback?

    private var showsExploreAction: Bool {
        onShareToExplore != nil || onEditExplorePost != nil || onViewInExplore != nil
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
        sharedExplorePostId != nil ? "Published" : "Share with community"
    }

    // BUTTONS TEXT
    var exploreActionTitle: String {
        sharedExplorePostId != nil ? "View post" : "Share discovery"
    }

    var exploreDescription: String {
        if sharedExplorePostId != nil {
            return "This discovery is visible to the community."
        }
        return "Publish this discovery so others can learn and explore."
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
        .sheet(isPresented: $showingExploreComposer) {
            ExplorePostComposerView(
                mode: sharedExplorePostId == nil ? .create : .edit,
                speciesName: speciesName,
                scientificName: scientificName,
                heroImageUrl: heroImageUrl,
                publicLocationLabel: publicLocationLabel,
                initialFieldNotes: fieldNotesPreview,
                initialFieldNotesArePublic: sharedExplorePostId == nil ? true : fieldNotesArePublicOnExplore,
                initialHashtags: sharedExplorePostId == nil ? [] : sharedExploreHashtags,
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
