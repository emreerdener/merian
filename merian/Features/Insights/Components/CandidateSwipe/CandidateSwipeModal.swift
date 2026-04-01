import SwiftUI

// MARK: - Candidate Swipe Modal

struct CandidateSwipeModal: View {
    let originalCandidates: [IdentificationCandidate]
    let aiScientificName: String
    var onFlagIssue: (() -> Void)?

    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var stack: [IdentificationCandidate]
    @State private var isGridMode = false
    @State private var topCardOffset: CGSize = .zero
    @State private var topCardIsDragging = false
    @State private var isDismissing = false

    private let swipeThreshold: CGFloat = 200

    init(candidates: [IdentificationCandidate], aiScientificName: String, onFlagIssue: (() -> Void)?) {
        self.originalCandidates = candidates
        self.aiScientificName = aiScientificName
        self.onFlagIssue = onFlagIssue
        self._stack = State(initialValue: candidates)
    }

    private var dragPercentage: Double {
        min(abs(topCardOffset.width) / swipeThreshold, 1.0)
    }

    private var isSwipingRight: Bool { topCardIsDragging && topCardOffset.width > 10 }
    private var isSwipingLeft: Bool { topCardIsDragging && topCardOffset.width < -10 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if stack.isEmpty && !isDismissing {
                    exhaustedStateContent
                } else if isGridMode {
                    gridContent
                } else {
                    cardStackContent
                }
            }
            .navigationTitle(stack.isEmpty ? "Review alternatives" : "\(stack.count) alternative\(stack.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                   Button(action: { dismiss() }) {
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
            if stack.isEmpty {
                Task { await inferenceEngine.flagAIIdentification(modelContext: modelContext) }
            }
        }
    }
}

// MARK: - Layout Extensions

extension CandidateSwipeModal {
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

    private var gridContent: some View {
        VStack(spacing: 20) {
            ForEach(stack, id: \.scientificName) { candidate in
                GridSwipeableCell(
                    candidate: candidate,
                    onConfirm: {
                        isDismissing = true
                        Task {
                            await inferenceEngine.applyIdentificationOverride(
                                scientificName: candidate.scientificName,
                                modelContext: modelContext
                            )
                            dismiss()
                        }
                    },
                    onReject: {
                        withAnimation(.spring(response: 0.25)) {
                            stack.removeAll { $0.scientificName == candidate.scientificName }
                        }
                    }
                )
            }
        }
        .padding(20)
    }

    private var exhaustedStateContent: some View {
        VStack(spacing: 32) {
            Image(systemName: "sparkle.2")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No other alternatives")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                Text("You've reviewed all available alternative species, but none of them matched your observation.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            
            VStack(spacing: 12) {
                Button {
                    HapticManager.shared.triggerErrorThump()
                    Task { await inferenceEngine.flagAIIdentification(modelContext: modelContext) }
                    dismiss()
                    onFlagIssue?()
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
}

// MARK: - Gesture & Action Extensions

extension CandidateSwipeModal {
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
        isDismissing = true
        withAnimation(.spring(response: 0.25)) {
            stack.removeFirst()
            topCardOffset = .zero
            topCardIsDragging = false
        }
        Task {
            await inferenceEngine.applyIdentificationOverride(
                scientificName: name,
                modelContext: modelContext
            )
            dismiss()
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
