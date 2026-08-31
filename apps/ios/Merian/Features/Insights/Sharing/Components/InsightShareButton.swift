import SwiftUI

struct InsightShareButton: View {
    let shareExternally: () -> Void
    let onShareToExplore: ((ExplorePostComposerDraft) async -> Bool)?
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
    var presentationGeneration: UInt64
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
    var dependencies: InsightShareButtonDependencies = .live

    @Environment(\.colorScheme) var colorScheme
    @State var showingOptions = false
    @State var showingExploreComposer = false
    @State var showingExplorePublishConfirmation = false
    @State private var isAwaitingExploreShareResult = false
    @State private var showingExploreShareFailure = false
    @State var pendingAction: InsightSharePendingAction?
    @State var actionScanId: String?
    @State var actionPresentationGeneration: UInt64?
    @State var actionGeneration: UInt64 = 0
    @State var optionsActionGeneration: UInt64?
    @State var composerActionGeneration: UInt64?
    @State var publishConfirmationActionGeneration: UInt64?
    @State var shareFailureActionGeneration: UInt64?
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

    var sharePresentation: InsightSharePresentation {
        InsightSharePresentation(
            sharedExplorePostID: sharedExplorePostId,
            recommendation: shareRecommendation
        )
    }

    var exploreHeadline: String {
        sharePresentation.headline
    }

    // BUTTONS TEXT
    var exploreActionTitle: String {
        sharePresentation.actionTitle
    }

    var exploreActionSystemImage: String {
        sharePresentation.actionSystemImage
    }

    var exploreDescription: String {
        sharePresentation.description
    }

    var pendingCommunityPublishDisclaimer: String {
        InsightSharePresentation.pendingCommunityPublishDisclaimer
    }

    var explorePublishConfirmationMessage: String {
        sharePresentation.publishConfirmationMessage
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
        let expectedActionScanId = actionScanId
        let expectedOptionsGeneration = optionsActionGeneration
        let expectedComposerGeneration = composerActionGeneration
        let expectedConfirmationGeneration =
            publishConfirmationActionGeneration
        let expectedFailureGeneration = shareFailureActionGeneration

        return Button(action: {
            actionGeneration &+= 1
            actionScanId = scanId
            actionPresentationGeneration = presentationGeneration
            if showsExploreAction {
                optionsActionGeneration = actionGeneration
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
        .accessibilityIdentifier("InsightShareButton")
        .sheet(
            isPresented: optionsPresentedBinding(
                expectedScanId: expectedActionScanId,
                expectedGeneration: expectedOptionsGeneration
            ),
            onDismiss: {
                handlePendingAction(
                    expectedScanId: expectedActionScanId,
                    expectedGeneration: expectedOptionsGeneration
                )
            }
        ) {
            shareOptionsSheet
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "Publish to Explore anyway?",
            isPresented: publishConfirmationPresentedBinding(
                expectedScanId: expectedActionScanId,
                expectedGeneration: expectedConfirmationGeneration
            )
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Publish anyway") {
                openExploreComposer(
                    expectedScanId: expectedActionScanId,
                    expectedGeneration: expectedConfirmationGeneration
                )
            }
        } message: {
            Text(explorePublishConfirmationMessage)
        }
        .sheet(
            isPresented: composerPresentedBinding(
                expectedScanId: expectedActionScanId,
                expectedGeneration: expectedComposerGeneration
            )
        ) {
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
                isSaving: sharedExplorePostId == nil
                    ? isSharingToExplore || isAwaitingExploreShareResult
                    : isUpdatingExplorePostContent,
                onSubmit: { draft in
                    guard composerActionGeneration == actionGeneration,
                          isActionSubjectCurrent(actionScanId) else {
                        return
                    }
                    if sharedExplorePostId == nil {
                        guard !isAwaitingExploreShareResult else { return }
                        isAwaitingExploreShareResult = true
                        let submittedScanId = actionScanId
                        let submittedGeneration = actionGeneration
                        let submitAction = onShareToExplore
                        Task { @MainActor in
                            let didShare = await submitAction?(draft) ?? false
                            guard isActionPresentationCurrent(
                                submittedScanId,
                                generation: submittedGeneration
                            ) else {
                                return
                            }
                            isAwaitingExploreShareResult = false
                            if didShare {
                                dismissComposer(
                                    expectedScanId: submittedScanId,
                                    expectedGeneration: submittedGeneration
                                )
                            } else {
                                shareFailureActionGeneration =
                                    submittedGeneration
                                showingExploreShareFailure = true
                            }
                        }
                    } else {
                        let editGeneration = actionGeneration
                        let editScanId = actionScanId
                        onEditExplorePost?(draft)
                        dismissComposer(
                            expectedScanId: editScanId,
                            expectedGeneration: editGeneration
                        )
                    }
                }
            )
            .interactiveDismissDisabled(
                isSharingToExplore || isAwaitingExploreShareResult
            )
            .alert(
                "Couldn’t share to Explore",
                isPresented: shareFailurePresentedBinding(
                    expectedScanId: expectedActionScanId,
                    expectedGeneration: expectedFailureGeneration
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your draft is still here. Check your connection and try sharing again.")
            }
        }
        .task(id: "\(scanId ?? ""):\(presentationGeneration)") {
            await loadChallengeEventHashtags(
                expectedScanId: scanId,
                expectedPresentationGeneration: presentationGeneration
            )
        }
        .onChange(of: scanId) {
            actionGeneration &+= 1
            showingOptions = false
            showingExploreComposer = false
            showingExplorePublishConfirmation = false
            isAwaitingExploreShareResult = false
            showingExploreShareFailure = false
            pendingAction = nil
            actionScanId = nil
            actionPresentationGeneration = nil
            optionsActionGeneration = nil
            composerActionGeneration = nil
            publishConfirmationActionGeneration = nil
            shareFailureActionGeneration = nil
            composerMediaItems = nil
            challengeEventHashtags = []
        }
        .onChange(of: presentationGeneration) {
            actionGeneration &+= 1
            showingOptions = false
            showingExploreComposer = false
            showingExplorePublishConfirmation = false
            isAwaitingExploreShareResult = false
            showingExploreShareFailure = false
            pendingAction = nil
            actionScanId = nil
            actionPresentationGeneration = nil
            optionsActionGeneration = nil
            composerActionGeneration = nil
            publishConfirmationActionGeneration = nil
            shareFailureActionGeneration = nil
            composerMediaItems = nil
            challengeEventHashtags = []
        }
    }

    private func optionsPresentedBinding(
        expectedScanId: String?,
        expectedGeneration: UInt64?
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard showingOptions,
                      let expectedGeneration,
                      optionsActionGeneration == expectedGeneration else {
                    return false
                }
                return isActionPresentationCurrent(
                    expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { isPresented in
                guard !isPresented,
                      let expectedGeneration,
                      optionsActionGeneration == expectedGeneration,
                      isActionPresentationCurrent(
                          expectedScanId,
                          generation: expectedGeneration
                      ) else {
                    return
                }
                // Keep the token until onDismiss consumes the action selected
                // by this exact options presentation.
                showingOptions = false
            }
        )
    }

    private func publishConfirmationPresentedBinding(
        expectedScanId: String?,
        expectedGeneration: UInt64?
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard showingExplorePublishConfirmation,
                      let expectedGeneration,
                      publishConfirmationActionGeneration ==
                        expectedGeneration else {
                    return false
                }
                return isActionPresentationCurrent(
                    expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { isPresented in
                guard !isPresented,
                      let expectedGeneration,
                      publishConfirmationActionGeneration ==
                        expectedGeneration,
                      isActionPresentationCurrent(
                          expectedScanId,
                          generation: expectedGeneration
                      ) else {
                    return
                }
                showingExplorePublishConfirmation = false
                publishConfirmationActionGeneration = nil
            }
        )
    }

    private func composerPresentedBinding(
        expectedScanId: String?,
        expectedGeneration: UInt64?
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard showingExploreComposer,
                      let expectedGeneration,
                      composerActionGeneration == expectedGeneration else {
                    return false
                }
                return isActionPresentationCurrent(
                    expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { isPresented in
                guard !isPresented else { return }
                dismissComposer(
                    expectedScanId: expectedScanId,
                    expectedGeneration: expectedGeneration
                )
            }
        )
    }

    private func shareFailurePresentedBinding(
        expectedScanId: String?,
        expectedGeneration: UInt64?
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard showingExploreShareFailure,
                      let expectedGeneration,
                      shareFailureActionGeneration == expectedGeneration else {
                    return false
                }
                return isActionPresentationCurrent(
                    expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { isPresented in
                guard !isPresented,
                      let expectedGeneration,
                      shareFailureActionGeneration == expectedGeneration,
                      isActionPresentationCurrent(
                          expectedScanId,
                          generation: expectedGeneration
                      ) else {
                    return
                }
                showingExploreShareFailure = false
                shareFailureActionGeneration = nil
            }
        )
    }

    private func dismissComposer(
        expectedScanId: String?,
        expectedGeneration: UInt64?
    ) {
        guard let expectedGeneration,
              composerActionGeneration == expectedGeneration,
              isActionPresentationCurrent(
                  expectedScanId,
                  generation: expectedGeneration
              ) else {
            return
        }
        showingExploreComposer = false
        composerActionGeneration = nil
        showingExploreShareFailure = false
        shareFailureActionGeneration = nil
    }

    private func loadChallengeEventHashtags(
        expectedScanId: String?,
        expectedPresentationGeneration: UInt64
    ) async {
        guard let scanId = expectedScanId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !scanId.isEmpty else {
            challengeEventHashtags = []
            return
        }

        do {
            let hashtags = try await dependencies
                .loadChallengeEventHashtags(scanId)
            guard !Task.isCancelled,
                  presentationGeneration == expectedPresentationGeneration,
                  self.scanId?.caseInsensitiveCompare(scanId) == .orderedSame else {
                return
            }
            challengeEventHashtags = hashtags
        } catch {
            if !Task.isCancelled,
               presentationGeneration == expectedPresentationGeneration,
               self.scanId?.caseInsensitiveCompare(scanId) == .orderedSame {
                challengeEventHashtags = []
            }
        }
    }

    func isActionSubjectCurrent(_ expectedScanId: String?) -> Bool {
        guard actionPresentationGeneration == presentationGeneration else {
            return false
        }
        switch (expectedScanId, actionScanId) {
        case (nil, nil):
            break
        case (.some(let expected), .some(let captured)):
            guard expected.caseInsensitiveCompare(captured) == .orderedSame else {
                return false
            }
        default:
            return false
        }
        switch (expectedScanId, scanId) {
        case (nil, nil):
            return true
        case (.some(let expected), .some(let current)):
            return expected.caseInsensitiveCompare(current) == .orderedSame
        default:
            return false
        }
    }

    func isActionPresentationCurrent(
        _ expectedScanId: String?,
        generation: UInt64
    ) -> Bool {
        generation == actionGeneration &&
            isActionSubjectCurrent(expectedScanId)
    }
}
