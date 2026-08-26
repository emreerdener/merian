import SwiftUI

extension ExploreMapView {
    var resolvedSelectedPost: ExplorePost? {
        resolvedPost(for: viewModel.selectedPost)
    }

    var activePreviewCenterMapPost: ExploreMapPost? {
        if let previewCarouselAnchorPostId,
           let anchoredPost = viewModel.visiblePosts.first(where: {
               $0.id == previewCarouselAnchorPostId
           }) {
            return anchoredPost
        }

        return viewModel.selectedPost
    }

    var activePreviewCenterPost: ExplorePost? {
        resolvedPost(for: activePreviewCenterMapPost)
    }

    var previousPreviewPost: ExplorePost? {
        guard let anchorPostId = activePreviewCenterMapPost?.id else { return nil }
        return resolvedPost(for: viewModel.post(relativeTo: anchorPostId, by: -1))
    }

    var nextPreviewPost: ExplorePost? {
        guard let anchorPostId = activePreviewCenterMapPost?.id else { return nil }
        return resolvedPost(for: viewModel.post(relativeTo: anchorPostId, by: 1))
    }

    @ViewBuilder
    var previewCarousel: some View {
        if let centerPreviewPost = activePreviewCenterPost {
            let previousPreviewPost = previousPreviewPost
            let nextPreviewPost = nextPreviewPost
            let mainCardHorizontalInset: CGFloat = 16
            let cardSpacing: CGFloat = 8

            previewCard(for: centerPreviewPost, isInteractive: false)
                .padding(.horizontal, mainCardHorizontalInset)
                .frame(maxWidth: .infinity)
                .hidden()
                .overlay {
                    GeometryReader { geometry in
                        let availableWidth = geometry.size.width
                        let cardWidth = max(
                            availableWidth
                                - (mainCardHorizontalInset * 2)
                                - (cardSpacing * 2),
                            0
                        )
                        let stepWidth = cardWidth + cardSpacing

                        HStack(spacing: cardSpacing) {
                            if let previousPreviewPost {
                                previewCard(
                                    for: previousPreviewPost,
                                    isInteractive: false
                                )
                                .frame(width: cardWidth)
                            }

                            previewCard(
                                for: centerPreviewPost,
                                isInteractive: true
                            )
                            .frame(width: cardWidth)

                            if let nextPreviewPost {
                                previewCard(
                                    for: nextPreviewPost,
                                    isInteractive: false
                                )
                                .frame(width: cardWidth)
                            }
                        }
                        .offset(x: cardDragOffset.width)
                        .frame(
                            width: availableWidth,
                            height: geometry.size.height,
                            alignment: .center
                        )
                        .clipped()
                        .onAppear {
                            updatePreviewCarouselStepWidth(stepWidth)
                        }
                        .onChange(of: stepWidth) { _, newValue in
                            updatePreviewCarouselStepWidth(newValue)
                        }
                    }
                }
                .padding(.bottom, 10)
                .offset(y: max(0, cardDragOffset.height))
                .contentShape(Rectangle())
                .gesture(previewCardDragGesture)
                .accessibilityElement(children: .contain)
        }
    }

    private var previewCardDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged(handlePreviewCardDragChanged)
            .onEnded(handlePreviewCardDragEnded)
    }

    private func handlePreviewCardDragChanged(_ value: DragGesture.Value) {
        let horizontalMagnitude = abs(value.translation.width)
        let verticalMagnitude = abs(value.translation.height)

        if activeCardDragAxis == nil,
           horizontalMagnitude > 6 || verticalMagnitude > 6 {
            activeCardDragAxis = horizontalMagnitude > verticalMagnitude
                ? .horizontal
                : .vertical
        }

        switch activeCardDragAxis {
        case .horizontal:
            let maxHorizontalTravel = max(previewCarouselStepWidth, 180) * 0.92
            let clampedWidth = min(
                max(value.translation.width, -maxHorizontalTravel),
                maxHorizontalTravel
            )
            cardDragOffset = CGSize(width: clampedWidth, height: 0)
        case .vertical:
            cardDragOffset = CGSize(
                width: 0,
                height: max(0, value.translation.height)
            )
        case nil:
            break
        }
    }

    private func handlePreviewCardDragEnded(_ value: DragGesture.Value) {
        defer { activeCardDragAxis = nil }

        switch activeCardDragAxis {
        case .horizontal:
            handlePreviewCardHorizontalSwipeEnded(value)
        case .vertical:
            handlePreviewCardVerticalDragEnded(value)
        case nil:
            resetPreviewCardPosition()
        }
    }

    private func handlePreviewCardHorizontalSwipeEnded(_ value: DragGesture.Value) {
        let swipeThreshold = min(max(previewCarouselStepWidth * 0.24, 56), 96)
        let didRequestNextPost = value.translation.width < -swipeThreshold
            || value.velocity.width < -360
        let didRequestPreviousPost = value.translation.width > swipeThreshold
            || value.velocity.width > 360

        if didRequestNextPost,
           viewModel.post(relativeToSelectedBy: 1) != nil {
            animatePreviewSelection(by: 1)
            return
        }

        if didRequestPreviousPost,
           viewModel.post(relativeToSelectedBy: -1) != nil {
            animatePreviewSelection(by: -1)
            return
        }

        resetPreviewCardPosition()
    }

    private func handlePreviewCardVerticalDragEnded(_ value: DragGesture.Value) {
        if value.translation.height > 60 || value.velocity.height > 300 {
            dismissSelectedPostIfNeeded()
        } else {
            resetPreviewCardPosition()
        }
    }

    private func resetPreviewCardPosition() {
        previewSwipeCommitGeneration += 1
        previewCarouselAnchorPostId = nil

        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            cardDragOffset = .zero
        }
    }

    private func animatePreviewSelection(by offset: Int) {
        previewCarouselAnchorPostId = viewModel.selectedPostId
        previewSwipeCommitGeneration += 1
        let commitGeneration = previewSwipeCommitGeneration
        let stepWidth = max(previewCarouselStepWidth, 1)
        let targetOffset = CGFloat(offset) * -stepWidth

        withAnimation(
            .spring(response: 0.24, dampingFraction: 0.9),
            completionCriteria: .logicallyComplete
        ) {
            cardDragOffset = CGSize(width: targetOffset, height: 0)
        } completion: {
            guard previewSwipeCommitGeneration == commitGeneration else { return }

            var transaction = Transaction()
            transaction.animation = nil

            isCommittingPreviewSelection = true
            withTransaction(transaction) {
                _ = viewModel.selectAdjacentPost(by: offset)
                cardDragOffset = .zero
                previewCarouselAnchorPostId = nil
            }

            HapticManager.shared.triggerLightImpact(intensity: 0.45)
        }
    }

    private func updatePreviewCarouselStepWidth(_ newValue: CGFloat) {
        guard newValue.isFinite, newValue > 0 else { return }
        guard abs(previewCarouselStepWidth - newValue) > 0.5 else { return }
        previewCarouselStepWidth = newValue
    }

    private func previewCard(
        for post: ExplorePost,
        isInteractive: Bool
    ) -> some View {
        ExploreMapPreviewCard(
            post: post,
            speciesDisplayName: feedViewModel.resolvedSpeciesCommonName(for: post),
            mediaReloadGeneration: feedViewModel.mediaReloadGeneration,
            onOpen: { openPost(post, focusCommentComposer: false) },
            onComments: { openPost(post, focusCommentComposer: true) },
            onLike: { Task { await toggleLike(for: post) } },
            onShare: { feedViewModel.share(post) },
            onUnshare: { Task { await unshare(post) } },
            onBlock: { Task { await blockAuthor(of: post) } },
            onReport: { Task { await report(post) } }
        )
        .allowsHitTesting(isInteractive)
        .accessibilityHidden(!isInteractive)
    }

    private func resolvedPost(for mapPost: ExploreMapPost?) -> ExplorePost? {
        mapPost?.asExplorePost
    }
}
