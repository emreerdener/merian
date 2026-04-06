import SwiftUI

// MARK: - Candidate Swipe Modal

struct CandidateSwipeModal: View {
    
    // MARK: - Properties
    
    let originalCandidates: [IdentificationCandidate]
    let aiScientificName: String
    let confirmButtonTitle: String
    let onConfirmOriginal: () -> Void
    var onFlagIssue: (() -> Void)?

    // MARK: - Environment
    
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - State
    
    @State private var stack: [IdentificationCandidate]
    @State private var isGridMode = false
    @State private var topCardOffset: CGSize = .zero
    @State private var topCardIsDragging = false
    @State private var isDismissing = false
    @State private var confirmedCandidate: IdentificationCandidate?

    // MARK: - Constants
    
    private let swipeThreshold: CGFloat = 200

    // MARK: - Initialization
    
    init(candidates: [IdentificationCandidate], aiScientificName: String, confirmButtonTitle: String, onConfirmOriginal: @escaping () -> Void, onFlagIssue: (() -> Void)?) {
        self.originalCandidates = candidates
        self.aiScientificName = aiScientificName
        self.confirmButtonTitle = confirmButtonTitle
        self.onConfirmOriginal = onConfirmOriginal
        self.onFlagIssue = onFlagIssue
        self._stack = State(initialValue: candidates)
    }

    // MARK: - Computed Properties
    
    /// The normalized drag percentage (0.0 to 1.0) based on the swipe threshold.
    private var dragPercentage: Double {
        min(abs(topCardOffset.width) / swipeThreshold, 1.0)
    }

    private var isSwipingRight: Bool { topCardIsDragging && topCardOffset.width > 10 }
    private var isSwipingLeft: Bool { topCardIsDragging && topCardOffset.width < -10 }

    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if let confirmed = confirmedCandidate {
                    confirmedStateContent(candidate: confirmed)
                } else if stack.isEmpty && !isDismissing {
                    exhaustedStateContent
                } else if isGridMode {
                    gridContent
                } else {
                    cardStackContent
                }
            }
            .navigationTitle(confirmedCandidate != nil ? "Success" : (stack.isEmpty ? "Review alternatives" : "\(stack.count) alternative\(stack.count == 1 ? "" : "s")"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                   Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                
                if stack.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            HapticManager.shared.triggerSelectionPulse()
                            withAnimation(.spring(response: 0.3)) {
                                isGridMode.toggle()
                                topCardOffset = .zero
                                topCardIsDragging = false
                            }
                        } label: {
                            Image(systemName: isGridMode ? "square.stack.3d.up.fill" : "rectangle.grid.1x2")
                        }
                    }
                }
            }
        }
        .onDisappear {
            if stack.isEmpty && !isDismissing && confirmedCandidate == nil {
                inferenceEngine.markAlternativesExhausted()
            }
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
                    Array(stack.prefix(2).enumerated().reversed()),
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
                        isSwipingLeft: isTop ? isSwipingLeft : false
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
            if stack.count > 1 {
                Button(action: {
                    HapticManager.shared.triggerLightImpact()
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
            ForEach(stack, id: \.scientificName) { candidate in
                GridSwipeableCell(
                    candidate: candidate,
                    onConfirm: {
                        HapticManager.shared.triggerSuccessPulse()
                        withAnimation(.spring(response: 0.3)) {
                            confirmedCandidate = candidate
                        }
                        Task {
                            // 1. Pause to show the success state natively
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            
                            // 2. Trigger native dismissal
                            await MainActor.run {
                                isDismissing = true
                                dismiss()
                            }
                            
                            // 3. Defer structural data mutation to prevent SwiftUI destroying the host sheet anchor
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            await inferenceEngine.applyIdentificationOverride(
                                scientificName: candidate.scientificName,
                                modelContext: modelContext
                            )
                        }
                    },
                    onReject: {
                        HapticManager.shared.triggerLightImpact()
                        withAnimation(.spring(response: 0.25)) {
                            stack.removeAll { $0.scientificName == candidate.scientificName }
                        }
                    }
                )
            }
        }
        .padding(20)
    }

    // MARK: Post-Review States
    
    /// Displayed when the user has rejected all alternatives in the stack or grid.
    /// Acts as an escape hatch to either confirm the original match, flag for review, or start over.
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
                Button {
                    HapticManager.shared.triggerSuccessPulse()
                    isDismissing = true
                    onConfirmOriginal()
                    dismiss()
                } label: {
                    Text(confirmButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    HapticManager.shared.triggerErrorThump()
                    isDismissing = true
                    dismiss()
                    
                    // Delay triggering the sheet presentation to allow the dismiss
                    // animation to detach safely without SwiftUI presentation collisions.
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await MainActor.run { onFlagIssue?() }
                    }
                } label: {
                    Text("Flag for review")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button {
                    HapticManager.shared.triggerLightImpact()
                    withAnimation(.spring(response: 0.35)) {
                        stack = originalCandidates
                        topCardOffset = .zero
                        topCardIsDragging = false
                    }
                } label: {
                    Text("Start over")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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
            
            if let data = inferenceEngine.activeDisplayDatas.first ?? inferenceEngine.activeImageData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let path = inferenceEngine.validHistoricImagePaths.first {
                AsyncLocalImageView(
                    path: path,
                    fallbackImageUrl: nil,
                    onImageLoadFailed: {}
                )
            } else {
                Image(systemName: "photo.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 160, height: 160)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
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
                    HapticManager.shared.triggerLightImpact()
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
        HapticManager.shared.triggerMediumPulse()
        withAnimation(.easeInOut(duration: 0.3)) {
            topCardOffset = CGSize(width: targetX, height: 60)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            switch direction {
            case .right: confirmTopCard()
            case .left:  rejectTopCard()
            }
        }
    }

    private func confirmTopCard() {
        guard let top = stack.first else { return }
        let name = top.scientificName
        withAnimation(.spring(response: 0.3)) {
            confirmedCandidate = top
            stack.removeFirst()
            topCardOffset = .zero
            topCardIsDragging = false
        }
        Task {
            // 1. Pause to show the success state natively
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            // 2. Trigger native dismissal
            await MainActor.run {
                isDismissing = true
                dismiss()
            }
            
            // 3. Defer structural data mutation to prevent SwiftUI destroying the host sheet anchor
            try? await Task.sleep(nanoseconds: 300_000_000)
            await inferenceEngine.applyIdentificationOverride(
                scientificName: name,
                modelContext: modelContext
            )
        }
    }

    private func rejectTopCard() {
        guard !stack.isEmpty else { return }
        withAnimation(.spring(response: 0.25)) {
            stack.removeFirst()
            topCardOffset = .zero
            topCardIsDragging = false
        }
    }

    private func skipTopCard() {
        guard let top = stack.first, stack.count > 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            topCardOffset = .zero
            topCardIsDragging = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.35)) {
                stack.removeFirst()
                stack.append(top)
            }
        }
    }
}
