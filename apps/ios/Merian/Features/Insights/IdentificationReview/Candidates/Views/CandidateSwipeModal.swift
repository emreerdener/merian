import SwiftUI

// MARK: - Candidate Swipe Modal

struct CandidateSwipeModal: View {
    
    // MARK: - Properties
    
    let scanId: String
    let presentationGeneration: UInt64
    let confirmButtonTitle: String
    let allowsAskCommunity: Bool
    let allowsRefinement: Bool
    let onRequestDismissalAction: (CandidateSwipeDismissalRequest) -> Void

    // MARK: - Environment
    
    @Environment(InferenceEngine.self) private var inferenceEngine

    // Explicit binding instead of @Environment(\.dismiss) — the dismiss environment value
    // leaks up through nested sheets in SwiftUI and can erroneously close the outer
    // InsightSheetView instead of only this modal.
    @Binding var isPresented: Bool

    // MARK: - State
    
    @State private var session: CandidateSwipeSession
    @State private var isGridMode = true
    @State private var topCardOffset: CGSize = .zero
    @State private var topCardIsDragging = false
    @State private var isDismissing = false
    @State private var showPaywall = false
    @State private var delayedDismissalAction: CandidateSwipeDismissalAction?
    @State private var viewModel: CandidateReviewViewModel

    // MARK: - Constants
    
    private let swipeThreshold: CGFloat = 200

    // MARK: - Initialization
    
    init(
        isPresented: Binding<Bool>,
        scanId: String,
        presentationGeneration: UInt64,
        candidates: [IdentificationCandidate],
        confirmButtonTitle: String,
        allowsAskCommunity: Bool,
        allowsRefinement: Bool,
        onRequestDismissalAction: @escaping (CandidateSwipeDismissalRequest) -> Void,
        dependencies: CandidateReviewDependencies = .live
    ) {
        self._isPresented = isPresented
        self.scanId = scanId
        self.presentationGeneration = presentationGeneration
        self.confirmButtonTitle = confirmButtonTitle
        self.allowsAskCommunity = allowsAskCommunity
        self.allowsRefinement = allowsRefinement
        self.onRequestDismissalAction = onRequestDismissalAction
        self._session = State(initialValue: CandidateSwipeSession(candidates: candidates))
        self._viewModel = State(
            initialValue: CandidateReviewViewModel(dependencies: dependencies)
        )
    }

    // MARK: - Computed Properties
    
    /// The normalized drag percentage (0.0 to 1.0) based on the swipe threshold.
    private var dragPercentage: Double {
        min(abs(topCardOffset.width) / swipeThreshold, 1.0)
    }

    private var isSwipingRight: Bool { topCardIsDragging && topCardOffset.width > 10 }
    private var isSwipingLeft: Bool { topCardIsDragging && topCardOffset.width < -10 }
    private var subject: IdentificationReviewSubject {
        IdentificationReviewSubject(
            scanId: scanId,
            presentationGeneration: presentationGeneration
        )
    }
    private var isSubjectPresentationCurrent: Bool {
        viewModel.isCurrent(subject, in: inferenceEngine)
    }

    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if let confirmed = session.confirmedCandidate {
                    confirmedStateContent(candidate: confirmed)
                } else if session.isExhausted && !isDismissing {
                    exhaustedStateContent
                } else if isGridMode {
                    gridContent
                } else {
                    cardStackContent
                }
            }
            .navigationTitle(session.confirmedCandidate != nil ? "Success" : (session.remainingCandidates.isEmpty ? "Alternatives" : "\(session.remainingCandidates.count) alternative\(session.remainingCandidates.count == 1 ? "" : "s")"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                   Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                
                if session.remainingCandidates.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.feedback.selection()
                            withAnimation(.spring(response: 0.3)) {
                                isGridMode.toggle()
                                topCardOffset = .zero
                                topCardIsDragging = false
                            }
                        } label: {
                            Image(systemName: isGridMode ? "square.stack.3d.up.fill" : "rectangle.grid.1x2")
                        }
                    }
                } else if session.isExhausted && !isDismissing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Restart") {
                            viewModel.feedback.lightImpact()
                            withAnimation(.spring(response: 0.35)) {
                                session.restart()
                                topCardOffset = .zero
                                topCardIsDragging = false
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            if session.isExhausted,
               !isDismissing,
               isSubjectPresentationCurrent {
                viewModel.markAlternativesExhausted(
                    subject: subject,
                    inferenceEngine: inferenceEngine
                )
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .task(id: delayedDismissalAction) {
            guard let delayedDismissalAction else { return }
            do {
                try await Task.sleep(for: .milliseconds(1_500))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  self.delayedDismissalAction == delayedDismissalAction else {
                return
            }
            requestDismissal(action: delayedDismissalAction)
        }
    }
}

// MARK: - View Components

extension CandidateSwipeModal {
    
    // MARK: Card Stack Content
    
    /// Displays the tinder-like stack of SwipeableCandidateCards.
    private var cardStackContent: some View {
        VStack(spacing: 16) {
            Spacer()

            // Card Stack
            ZStack {
                ForEach(
                    Array(session.remainingCandidates.prefix(2).enumerated().reversed()),
                    id: \.element.scientificName
                ) { index, candidate in
                    let isTop = index == 0
                    let dragPct = CGFloat(dragPercentage)
                    
                    let scaleTarget = 1.0 - CGFloat(index) * 0.06
                    let scaleNext = 1.0 - CGFloat(max(0, index - 1)) * 0.06
                    let currentScale = isTop ? 1.0 : scaleTarget + (scaleNext - scaleTarget) * dragPct
                    
                    let yOffsetTarget = CGFloat(index) * 32.0
                    let yOffsetNext = CGFloat(max(0, index - 1)) * 32.0
                    let currentYOffset = isTop 
                        ? topCardOffset.height * 0.15 
                        : yOffsetTarget + (yOffsetNext - yOffsetTarget) * dragPct

                    SwipeableCandidateCard(
                        candidate: candidate,
                        isDragging: isTop ? topCardIsDragging : false,
                        dragPercentage: isTop ? dragPercentage : 0,
                        isSwipingRight: isTop ? isSwipingRight : false,
                        isSwipingLeft: isTop ? isSwipingLeft : false,
                        imageDependencies: viewModel.imageDependencies,
                        feedback: viewModel.feedback
                    )
                    .scaleEffect(currentScale)
                    .offset(
                        x: isTop ? topCardOffset.width : 0,
                        y: currentYOffset
                    )
                    .rotationEffect(isTop ? .degrees(Double(topCardOffset.width) / 25.0) : .degrees(0))
                    .zIndex(-Double(index))
                    .gesture(isTop ? mainDragGesture : nil)
                    .allowsHitTesting(isTop)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 460)
            .padding(.horizontal, 20)

            // Skip Button
            if session.remainingCandidates.count > 1 {
                Button(action: {
                    viewModel.feedback.lightImpact()
                    skipTopCard()
                }) {
                    Text("Skip")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
                .transition(.opacity)
            }

            Spacer()

            CandidateActionBar(
                onReject: { animateSwipe(.left) },
                onConfirm: { animateSwipe(.right) }
            )
            .padding(.bottom, 32)
        }
    }

    // MARK: Grid Content
    
    /// Displays all remaining candidates in a vertical grid layout for quick assessment.
    private var gridContent: some View {
        VStack(spacing: 20) {
            ForEach(session.remainingCandidates, id: \.scientificName) { candidate in
                GridSwipeableCell(
                    candidate: candidate,
                    imageDependencies: viewModel.imageDependencies,
                    feedback: viewModel.feedback,
                    onConfirm: {
                        viewModel.feedback.successPulse()
                        withAnimation(.spring(response: 0.3)) {
                            session.confirm(candidate)
                        }
                        delayedDismissalAction = .applyOverride(
                            scientificName: candidate.scientificName
                        )
                    },
                    onReject: {
                        viewModel.feedback.lightImpact()
                        withAnimation(.spring(response: 0.25)) {
                            session.reject(scientificName: candidate.scientificName)
                        }
                    }
                )
            }
        }
        .padding(20)
    }

    // MARK: Post-Review States
    
    /// Displayed when the user has rejected all alternatives in the stack or grid.
    /// Acts as an escape hatch to either confirm the original match, ask the community, or start over.
    private var exhaustedStateContent: some View {
        VStack(spacing: 32) {
            originalScanThumbnail
            
            VStack(spacing: 8) {
                Text("No other alternatives")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                Text("You've reviewed all available alternative species.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            
            VStack(spacing: 12) {
                if allowsRefinement {
                    SlideToConfirm(
                        label: "Reanalyze species",
                        onConfirm: {
                            if viewModel.isProActive {
                                requestDismissal(action: .refineScan)
                            } else {
                                showPaywall = true
                            }
                        },
                        color: .orange
                    )
                }

                if allowsAskCommunity {
                    SlideToConfirm(label: "Ask the community", onConfirm: {
                        requestDismissal(action: .askCommunity)
                    }, color: .blue)
                }

                SlideToConfirm(label: confirmButtonTitle, onConfirm: {
                    requestDismissal(action: .confirmOriginal)
                })
            }
            .padding(.horizontal, 24)
        }
    }

    /// The inline success state shown for 1.5 seconds immediately after a candidate is confirmed.
    private func confirmedStateContent(candidate: IdentificationCandidate) -> some View {
        let commonStr = candidate.commonName ?? ""
        let isCommonEmpty = commonStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let displayName = isCommonEmpty ? candidate.scientificName : commonStr.capitalized

        return VStack(spacing: 32) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                Text("Match confirmed")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                Text("You've successfully updated the identification to \(displayName).")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .transition(.scale.combined(with: .opacity))
    }

    /// Attempts to render the primary image of the current scan (live or historical)
    /// into a circular thumbnail, falling back to a placeholder if unavailable.
    @ViewBuilder
    private var originalScanThumbnail: some View {
        ZStack {
            Color(.secondarySystemBackground)
            
            if let data = inferenceEngine.activeMedia.liveImageData {
                CandidateSwipeLiveThumbnail(imageData: data)
            } else if let path = inferenceEngine.activeMedia.imagePathsForUpload.first {
                AsyncLocalImageView(
                    path: path,
                    fallbackImageUrl: nil,
                    onImageLoadFailed: {}
                )
            } else {
                Image(systemName: "photo.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 240, height: 240)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
    }
}

// MARK: - Gestures & Actions

extension CandidateSwipeModal {
    
    // MARK: Gestures
    
    private var mainDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                topCardOffset = value.translation
                topCardIsDragging = true
            }
            .onEnded { value in
                if abs(value.translation.width) >= swipeThreshold {
                    animateSwipe(value.translation.width > 0 ? .right : .left)
                } else {
                    viewModel.feedback.lightImpact()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                        topCardOffset = .zero
                        topCardIsDragging = false
                    }
                }
            }
    }

    // MARK: Action Handlers
    
    /// Triggers a programmatic swipe animation off-screen to the given direction.
    private func animateSwipe(_ direction: CandidateSwipeDirection) {
        let targetX: CGFloat = direction == .right ? 700 : -700
        viewModel.feedback.mediumPulse()
        withAnimation(.easeInOut(duration: 0.3)) {
            topCardOffset = CGSize(width: targetX, height: 60)
        } completion: {
            switch direction {
            case .right: confirmTopCard()
            case .left:  rejectTopCard()
            }
        }
    }

    private func confirmTopCard() {
        guard let top = session.topCandidate else { return }
        let name = top.scientificName
        withAnimation(.spring(response: 0.3)) {
            session.confirm(top)
            topCardOffset = .zero
            topCardIsDragging = false
        }
        delayedDismissalAction = .applyOverride(scientificName: name)
    }

    private func rejectTopCard() {
        guard session.topCandidate != nil else { return }
        withAnimation(.spring(response: 0.25)) {
            session.rejectTopCandidate()
            topCardOffset = .zero
            topCardIsDragging = false
        }
    }

    private func skipTopCard() {
        guard session.remainingCandidates.count > 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            topCardOffset = .zero
            topCardIsDragging = false
        } completion: {
            withAnimation(.spring(response: 0.35)) {
                session.skipTopCandidate()
            }
        }
    }

    private func requestDismissal(action: CandidateSwipeDismissalAction) {
        guard !isDismissing, isSubjectPresentationCurrent else { return }
        isDismissing = true
        onRequestDismissalAction(CandidateSwipeDismissalRequest(
            action: action,
            scanId: scanId,
            presentationGeneration: presentationGeneration
        ))
        isPresented = false
    }
}
