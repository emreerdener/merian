import SwiftUI

extension InsightShareButton {
    var shareOptionsSheet: some View {
        let expectedActionScanId = actionScanId
        let expectedOptionsGeneration = optionsActionGeneration
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // EXPLORE FEATURE PANEL
                exploreFeaturePanel

                // SHARE TO EXTERNAL APPS
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        selectPendingAction(
                            .externalShare,
                            expectedScanId: expectedActionScanId,
                            expectedGeneration: expectedOptionsGeneration
                        )
                    } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("More ways to share")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)

                                Text("Send via Messages, social media, or copy the link.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 12)

                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 96)
        }
    }

// MARK: - Explore Feature Panel
    private var exploreFeaturePanel: some View {
        let expectedActionScanId = actionScanId
        let expectedOptionsGeneration = optionsActionGeneration
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 58, height: 58)

                    Image("bird-magnifier")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(exploreHeadline)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if sharedExplorePostId != nil {
                            Text("LIVE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(colorScheme == .dark ? .white : .black)
                                )
                        }
                    }

                    Text(exploreDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if sharedExplorePostId == nil, shareRecommendation == .communityPending {
                pendingCommunityRequestActions
            } else if sharedExplorePostId == nil {
                Button {
                    selectPendingAction(
                        primaryExplorePanelAction,
                        expectedScanId: expectedActionScanId,
                        expectedGeneration: expectedOptionsGeneration
                    )
                } label: {
                    HStack(alignment: .center) {
                        Label(
                            isSharingToExplore
                                ? "Sharing..."
                                : exploreActionTitle,
                            systemImage: exploreActionSystemImage
                        )
                        .font(.headline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        Capsule(style: .continuous)
                            .fill(exploreActionFillColor)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(exploreActionForegroundColor)
                .disabled(isSharingToExplore)

                secondaryCommunityActions
            } else {
                HStack(spacing: 10) {
                    if onEditExplorePost != nil {
                        exploreSecondaryActionButton(
                            title: isUpdatingExplorePostContent ? "Saving..." : "Edit post",
                            systemImage: "square.and.pencil",
                            isDisabled: isUpdatingExplorePostContent
                        ) {
                            selectPendingAction(
                                .editExplorePost,
                                expectedScanId: expectedActionScanId,
                                expectedGeneration: expectedOptionsGeneration
                            )
                        }
                    }

                    if onViewInExplore != nil {
                        exploreSecondaryActionButton(
                            title: "View post",
                            systemImage: "eye",
                            isDisabled: false
                        ) {
                            selectPendingAction(
                                .viewInExplore,
                                expectedScanId: expectedActionScanId,
                                expectedGeneration: expectedOptionsGeneration
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.primary.opacity(0.02))
            }
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var pendingCommunityRequestActions: some View {
        let expectedActionScanId = actionScanId
        let expectedOptionsGeneration = optionsActionGeneration
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if onEditCommunityRequest != nil {
                    exploreSecondaryActionButton(
                        title: "Edit",
                        systemImage: "square.and.pencil",
                        isProminent: true,
                        isDisabled: false
                    ) {
                        selectPendingAction(
                            .editCommunityRequest,
                            expectedScanId: expectedActionScanId,
                            expectedGeneration: expectedOptionsGeneration
                        )
                    }
                }

                if onViewCommunityRequest != nil {
                    exploreSecondaryActionButton(
                        title: "View",
                        systemImage: "person.crop.circle.badge.questionmark",
                        isDisabled: false
                    ) {
                        selectPendingAction(
                            .viewCommunityRequest,
                            expectedScanId: expectedActionScanId,
                            expectedGeneration: expectedOptionsGeneration
                        )
                    }
                }
            }

            if onShareToExplore != nil {
                Button {
                    selectPendingAction(
                        .publishExploreAnyway,
                        expectedScanId: expectedActionScanId,
                        expectedGeneration: expectedOptionsGeneration
                    )
                } label: {
                    Label("Publish to Explore", systemImage: "safari")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(
                            Capsule(style: .continuous)
                                .fill(primaryBlue)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(isSharingToExplore)

                Text(pendingCommunityPublishDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var secondaryCommunityActions: some View {
        let expectedActionScanId = actionScanId
        let expectedOptionsGeneration = optionsActionGeneration
        switch shareRecommendation {
        case .askCommunity:
            if onShareToExplore != nil {
                exploreSecondaryActionButton(
                    title: "Publish anyway",
                    isDisabled: isSharingToExplore
                ) {
                    selectPendingAction(
                        .publishExploreAnyway,
                        expectedScanId: expectedActionScanId,
                        expectedGeneration: expectedOptionsGeneration
                    )
                }
            }
        case .communityPending:
            if onViewCommunityRequest != nil {
                exploreSecondaryActionButton(
                    title: "View request",
                    systemImage: "person.crop.circle.badge.questionmark",
                    isDisabled: false
                ) {
                    selectPendingAction(
                        .viewCommunityRequest,
                        expectedScanId: expectedActionScanId,
                        expectedGeneration: expectedOptionsGeneration
                    )
                }
            }
        case .communityResolvedNeedsPublish:
            if onViewCommunityRequest != nil {
                exploreSecondaryActionButton(
                    title: "View request",
                    systemImage: "person.crop.circle.badge.questionmark",
                    isDisabled: false
                ) {
                    selectPendingAction(
                        .viewCommunityRequest,
                        expectedScanId: expectedActionScanId,
                        expectedGeneration: expectedOptionsGeneration
                    )
                }
            }
        case .publishToExplore:
            EmptyView()
        }
    }

    private var primaryExplorePanelAction: InsightSharePendingAction {
        sharePresentation.primaryAction(
            canAskCommunity: onAskCommunity != nil,
            canEditCommunityRequest: onEditCommunityRequest != nil
        )
    }

    private func selectPendingAction(
        _ action: InsightSharePendingAction,
        expectedScanId: String?,
        expectedGeneration: UInt64?
    ) {
        guard showingOptions,
              let expectedGeneration,
              optionsActionGeneration == expectedGeneration,
              isActionPresentationCurrent(
                  expectedScanId,
                  generation: expectedGeneration
              ) else {
            return
        }
        pendingAction = action
        showingOptions = false
    }

    func handlePendingAction(
        expectedScanId: String?,
        expectedGeneration: UInt64?
    ) {
        guard !showingOptions,
              let expectedGeneration,
              optionsActionGeneration == expectedGeneration,
              isActionPresentationCurrent(
                  expectedScanId,
                  generation: expectedGeneration
              ) else {
            return
        }
        optionsActionGeneration = nil
        guard let pendingAction else { return }
        self.pendingAction = nil

        switch pendingAction {
        case .externalShare:
            shareExternally()
        case .askCommunity:
            onAskCommunity?()
        case .composeExplorePost:
            openExploreComposer(
                expectedScanId: expectedScanId,
                expectedGeneration: expectedGeneration
            )
        case .publishExploreAnyway:
            publishConfirmationActionGeneration = expectedGeneration
            showingExplorePublishConfirmation = true
        case .editExplorePost:
            openExploreComposer(
                expectedScanId: expectedScanId,
                expectedGeneration: expectedGeneration
            )
        case .editCommunityRequest:
            onEditCommunityRequest?()
        case .viewCommunityRequest:
            onViewCommunityRequest?()
        case .viewInExplore:
            onViewInExplore?()
        }
    }

    func openExploreComposer(
        expectedScanId: String? = nil,
        expectedGeneration: UInt64? = nil
    ) {
        let targetGeneration = expectedGeneration ?? actionGeneration
        let targetScanId = expectedGeneration == nil
            ? actionScanId
            : expectedScanId
        guard isActionPresentationCurrent(
            targetScanId,
            generation: targetGeneration
        ) else {
            return
        }
        composerMediaItems = nil
        composerActionGeneration = targetGeneration
        guard let targetScanId else {
            showingExploreComposer = true
            return
        }

        Task {
            let serverItems: [ExplorePostComposerMediaDraft]?
            do {
                serverItems = try await dependencies
                    .loadComposerMedia(targetScanId)
            } catch {
                serverItems = nil
            }

            await MainActor.run {
                guard isActionPresentationCurrent(
                    targetScanId,
                    generation: targetGeneration
                ) else {
                    return
                }
                if let serverItems, !serverItems.isEmpty {
                    let localHasVideo = mediaItems.contains { $0.kind == .video }
                    let serverHasVideo = serverItems.contains { $0.kind == .video }
                    composerMediaItems = localHasVideo && !serverHasVideo
                        ? mediaItems
                        : serverItems
                }
                showingExploreComposer = true
            }
        }
    }

    private func exploreSecondaryActionButton(
        title: String,
        systemImage: String? = nil,
        isProminent: Bool = false,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }

                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
            .background(
                Capsule(style: .continuous)
                    .fill(secondaryActionFillColor(isProminent: isProminent, systemImage: systemImage))
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(secondaryActionForegroundColor(isProminent: isProminent, systemImage: systemImage))
        .disabled(isDisabled)
    }

    private func secondaryActionFillColor(isProminent: Bool, systemImage: String?) -> Color {
        if isProminent {
            return colorScheme == .dark ? .white : .black
        }
        return systemImage == "eye" ? primaryBlue : primaryBlue.opacity(0.14)
    }

    private func secondaryActionForegroundColor(isProminent: Bool, systemImage: String?) -> Color {
        if isProminent {
            return Color(uiColor: .systemBackground)
        }
        return systemImage == "eye" ? .white : primaryBlue
    }

}
