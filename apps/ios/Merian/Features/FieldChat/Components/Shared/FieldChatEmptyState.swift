import SwiftUI

struct FieldChatEmptyState: View {
    let displayName: String
    let media: [FieldChatMedia]
    var isOnline = true
    var imageDependencies: FieldChatImageDependencies?
    var prompts: [String] = []
    var isLoadingPrompts = false
    var showsPrompts = true
    let onImageSelection: () -> Void
    var onPromptSelection: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 10) {
            FieldChatImageStack(
                media: media, isOnline: isOnline,
                dependencies: imageDependencies, onSelection: onImageSelection
            )
                .id(media.map(\.id))

            Text("What would you like to explore about \(displayName)?")
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .accessibilityAddTraits(.isHeader)

            FieldChatWelcomePrompts(
                candidates: prompts,
                isLoading: isLoadingPrompts,
                isVisible: showsPrompts,
                isOnline: isOnline,
                onSelection: onPromptSelection
            )

        }
        .padding(.top, 8)
        .padding(.bottom, 24)
    }
}

struct FieldChatImageStack: View {
    private let cardSize: CGFloat = 184
    let onSelection: () -> Void
    let isOnline: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var model: FieldChatImageStackModel
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.25)))
    private var dragOffset: CGFloat = 0
    @State private var outgoing: FieldChatMedia?
    @State private var outgoingImage: UIImage?
    @State private var exitDirection: CGFloat = -1
    @State private var isReturning = false
    @State private var isSwapping = false
    @State private var animationGeneration = UUID()
    @State private var swapTargetID: String?

    private struct LoadRequest: Equatable {
        let selectedID: String?
        let isOnline: Bool
    }

    @MainActor
    init(
        media: [FieldChatMedia],
        isOnline: Bool = true,
        dependencies: FieldChatImageDependencies? = nil,
        onSelection: @escaping () -> Void
    ) {
        self.onSelection = onSelection
        self.isOnline = isOnline
        _model = State(initialValue: FieldChatImageStackModel(media: media, dependencies: dependencies ?? .live))
    }

    var body: some View {
        VStack(spacing: 8) {
            if let selected = model.selectedMedia {
                cards(selected: selected)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20)
                            .updating($dragOffset) { value, state, _ in
                                guard !reduceMotion, !isSwapping, model.images[selected.id] != nil,
                                      model.availableMedia.count > 1,
                                      abs(value.translation.width) > abs(value.translation.height) else { return }
                                state = min(240, max(-240, value.translation.width))
                            }
                            .onEnded { value in
                                let translation = value.translation
                                guard let offset = FieldChatImageNavigation.swipeOffset(
                                    horizontal: Double(translation.width), vertical: Double(translation.height),
                                    isRightToLeft: layoutDirection == .rightToLeft
                                ) else { return }
                                move(by: offset)
                            }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(selected.accessibilityLabel)
                    .accessibilityValue("Image \(model.selectedIndex + 1) of \(model.availableMedia.count)")
                    .accessibilityHint(model.availableMedia.count > 1 ? "Swipe up or down to change image" : "")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: move(by: 1)
                        case .decrement: move(by: -1)
                        @unknown default: break
                        }
                    }
                    .accessibilityIdentifier("FieldChatImageStack")

                if let attribution = selected.attribution {
                    Text(attribution)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260)
                }
            } else {
                Image("sparkles")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("FieldChatImageFallback")
            }
        }
        .task(id: LoadRequest(selectedID: model.selectedID, isOnline: isOnline)) {
            await model.loadWindow(isOnline: isOnline)
        }
        .onDisappear { resetSwap() }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { resetSwap() }
        }
        .onChange(of: model.selectedID) { _, selectedID in
            // Loading can automatically replace a failed destination mid-swap.
            if isSwapping, selectedID != swapTargetID { resetSwap() }
        }
    }

    private func cards(selected: FieldChatMedia) -> some View {
        let deck = model.stackMedia.filter { $0.id == selected.id || model.images[$0.id] != nil }
        let translation = reduceMotion || isSwapping ? 0 : dragOffset
        let visible = deck + (outgoing.map { item in deck.contains(where: { $0.id == item.id }) ? [] : [item] } ?? [])
        return ZStack {
            ForEach(visible) { media in
                let depth = deck.firstIndex(where: { $0.id == media.id }) ?? 3
                let departing = outgoing?.id == media.id
                let returningDepth = max(1, depth)
                let restingDepth = departing && isReturning ? returningDepth : depth
                card(media)
                    .scaleEffect(departing && !isReturning ? 0.96 : 1 - CGFloat(restingDepth) * 0.04)
                    .rotationEffect(.degrees(departing && !isReturning ? Double(exitDirection * 18) :
                        media.id == selected.id ? Double(translation / 16) : (restingDepth.isMultiple(of: 2) ? 6 : -5)))
                    .offset(
                        x: departing && !isReturning ? exitDirection * (cardSize + 60) :
                            media.id == selected.id ? translation : (restingDepth.isMultiple(of: 2) ? 7 : -7),
                        y: departing && !isReturning ? 18 : CGFloat(restingDepth) * 5
                    )
                    .zIndex(departing && !isReturning ? 4 : Double(3 - depth))
                    .transition(reduceMotion ? .identity : .asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .offset(y: 18)),
                        removal: .identity
                    ))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: cardSize + 32, height: cardSize + 32)
    }

    private func card(_ media: FieldChatMedia) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground))
            .overlay {
                if let image = media.id == outgoing?.id ? outgoingImage : model.images[media.id] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if media.id == model.selectedID {
                    ProgressView()
                }
            }
            .frame(width: cardSize, height: cardSize)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
    }

    private func move(by offset: Int) {
        guard !isSwapping, model.availableMedia.count > 1,
              let selected = model.selectedMedia, model.images[selected.id] != nil else { return }
        guard !reduceMotion else {
            model.move(by: offset, onSelection: onSelection)
            return
        }
        let token = UUID()
        animationGeneration = token
        isSwapping = true
        exitDirection = (offset > 0) == (layoutDirection == .leftToRight) ? -1 : 1
        outgoingImage = model.images[selected.id]
        withAnimation(.easeOut(duration: 0.12), completionCriteria: .logicallyComplete) {
            outgoing = selected
            isReturning = false
            model.move(by: offset, onSelection: onSelection)
            swapTargetID = model.selectedID
        } completion: {
            guard animationGeneration == token else { return }
            // Lower the departing card behind the deck before sliding it back in.
            withAnimation(.easeInOut(duration: 0.16), completionCriteria: .logicallyComplete) {
                isReturning = true
            } completion: {
                guard animationGeneration == token else { return }
                resetSwap()
            }
        }
    }

    private func resetSwap() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            animationGeneration = UUID()
            outgoing = nil
            outgoingImage = nil
            swapTargetID = nil
            isSwapping = false
            isReturning = false
        }
    }
}
