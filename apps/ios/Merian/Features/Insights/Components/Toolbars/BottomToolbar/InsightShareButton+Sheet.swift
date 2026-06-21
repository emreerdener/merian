import SwiftUI

extension InsightShareButton {
    var shareOptionsSheet: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // EXPLORE FEATURE PANEL
                    exploreFeaturePanel

                    // SHARE TO EXTERNAL APPS
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            pendingAction = .externalShare
                            showingOptions = false
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

            if let fieldNotesVisibilityFeedback {
                ToastBanner(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.fieldNotesVisibilityFeedback = nil
                    }
                }) {
                    Text(fieldNotesVisibilityFeedback.message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
    }

// MARK: - Explore Feature Panel
    private var exploreFeaturePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 58, height: 58)

                    Image("identify")
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

            if sharedExplorePostId != nil, hasFieldNotesToShare {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        isOn: Binding(
                            get: { fieldNotesArePublicOnExplore },
                            set: { updateFieldNotesVisibility(isPublic: $0) }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show field notes on Explore")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(fieldNotesArePublicOnExplore ? "Visible on the published post." : "Private to this scan.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(isUpdatingExploreFieldNotes)

                    if fieldNotesArePublicOnExplore, let fieldNotesExcerpt {
                        Text(fieldNotesExcerpt)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                    }
                }
            }

            if sharedExplorePostId == nil {
                Button {
                    pendingAction = primaryExplorePanelAction
                    showingOptions = false
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
                            pendingAction = .editExplorePost
                            showingOptions = false
                        }
                    }

                    if onViewInExplore != nil {
                        exploreSecondaryActionButton(
                            title: "View post",
                            systemImage: "eye",
                            isDisabled: false
                        ) {
                            pendingAction = .viewInExplore
                            showingOptions = false
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

    @ViewBuilder
    private var secondaryCommunityActions: some View {
        switch shareRecommendation {
        case .askCommunity:
            if onShareToExplore != nil {
                exploreSecondaryActionButton(
                    title: "Publish anyway",
                    isDisabled: isSharingToExplore
                ) {
                    pendingAction = .publishExploreAnyway
                    showingOptions = false
                }
            }
        case .communityPending:
            EmptyView()
        case .communityResolvedNeedsPublish:
            if onViewCommunityRequest != nil {
                exploreSecondaryActionButton(
                    title: "View request",
                    systemImage: "person.crop.circle.badge.questionmark",
                    isDisabled: false
                ) {
                    pendingAction = .viewCommunityRequest
                    showingOptions = false
                }
            }
        case .publishToExplore:
            EmptyView()
        }
    }

    private var primaryExplorePanelAction: PendingAction {
        switch shareRecommendation {
        case .askCommunity:
            onAskCommunity == nil ? .composeExplorePost : .askCommunity
        case .communityPending:
            onViewCommunityRequest == nil ? .publishExploreAnyway : .viewCommunityRequest
        case .communityResolvedNeedsPublish, .publishToExplore:
            .composeExplorePost
        }
    }

    func handlePendingAction() {
        guard let pendingAction else { return }
        self.pendingAction = nil

        switch pendingAction {
        case .externalShare:
            shareExternally()
        case .askCommunity:
            onAskCommunity?()
        case .composeExplorePost:
            showingExploreComposer = true
        case .publishExploreAnyway:
            showingExplorePublishConfirmation = true
        case .editExplorePost:
            showingExploreComposer = true
        case .viewCommunityRequest:
            onViewCommunityRequest?()
        case .viewInExplore:
            onViewInExplore?()
        }
    }

    private func exploreSecondaryActionButton(
        title: String,
        systemImage: String? = nil,
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
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(primaryBlue.opacity(systemImage == "eye" ? 1 : 0.14))
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(systemImage == "eye" ? .white : primaryBlue)
        .disabled(isDisabled)
    }

    private func updateFieldNotesVisibility(isPublic: Bool) {
        guard let onUpdateFieldNotesVisibility else { return }

        fieldNotesVisibilityFeedback = nil
        Task {
            let feedback = await onUpdateFieldNotesVisibility(isPublic)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                fieldNotesVisibilityFeedback = feedback
            }
        }
    }
}
