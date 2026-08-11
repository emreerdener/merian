import SwiftUI

enum MilestoneToastDismissalAxis: Equatable {
    case horizontal
    case vertical
}

enum MilestoneToastDismissalGesture {
    static let commitDistance: CGFloat = 84
    static let projectedCommitDistance: CGFloat = 180
    static let offscreenDistance: CGFloat = 1_800

    static func distance(for translation: CGSize) -> CGFloat {
        hypot(translation.width, translation.height)
    }

    static func hasReachedCommitDistance(_ translation: CGSize) -> Bool {
        distance(for: translation) >= commitDistance
    }

    static func axis(for translation: CGSize) -> MilestoneToastDismissalAxis {
        abs(translation.width) >= abs(translation.height) ? .horizontal : .vertical
    }

    static func constrainedTranslation(
        _ translation: CGSize,
        to axis: MilestoneToastDismissalAxis
    ) -> CGSize {
        switch axis {
        case .horizontal:
            CGSize(width: translation.width, height: 0)
        case .vertical:
            CGSize(width: 0, height: translation.height)
        }
    }

    static func shouldDismiss(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        hasReachedCommitDistance(translation)
            || distance(for: predictedEndTranslation) >= projectedCommitDistance
    }

    static func offscreenOffset(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> CGSize {
        let translationDistance = distance(for: translation)
        let predictedDistance = distance(for: predictedEndTranslation)
        let direction = predictedDistance > translationDistance
            ? predictedEndTranslation
            : translation
        let directionDistance = max(distance(for: direction), 1)
        let scale = offscreenDistance / directionDistance

        return CGSize(
            width: direction.width * scale,
            height: direction.height * scale
        )
    }
}

struct MilestoneToastBanner: View {
    let item: MilestoneToastItem
    var pendingItemCount = 0
    var isActive = true
    let clock: any MilestoneToastClock
    let onClaimPresentationEffects: (UUID, Date) -> Bool
    let automaticDismissInterval: (UUID, Date) -> TimeInterval?
    let onDismiss: () -> Void
    var onOpenAchievement: ((AwardPayload) -> Void)?
    var onOpenFieldTrip: ((CaptureGoalDestination) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasFiredPresentationEffects = false
    @State private var dragOffset = CGSize.zero
    @State private var dismissalOpacity = 1.0
    @State private var dragAxis: MilestoneToastDismissalAxis?
    @State private var hasReachedDismissThreshold = false
    @State private var isInteracting = false
    @State private var isDismissing = false

    var body: some View {
        ToastBanner(
            onDismiss: dismissManually,
            pendingItemCount: pendingItemCount,
            foregroundTransform: ToastBannerForegroundTransform(
                offset: dragOffset,
                scale: dragScale,
                opacity: dragOpacity * dismissalOpacity
            )
        ) {
            HStack(spacing: 14) {
                milestoneIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(display.eyebrow)
                        .font(.caption)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    Text(display.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = display.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                open()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged(handleDragChanged)
                .onEnded(handleDragEnded)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(display.accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(display.accessibilityIdentifier)
        .accessibilityHidden(!isActive)
        .accessibilityAction(named: "Dismiss notification") {
            dismissManually()
        }
        .allowsHitTesting(isActive)
        .onChange(
            of: PresentationContext(itemID: item.id, isActive: isActive),
            initial: true
        ) { _, _ in
            hasFiredPresentationEffects = false
            dragOffset = .zero
            dismissalOpacity = 1
            dragAxis = nil
            hasReachedDismissThreshold = false
            isInteracting = false
            isDismissing = false
            if isActive {
                firePresentationEffectsIfNeeded()
            }
        }
        .task(
            id: AutomaticDismissContext(
                itemID: item.id,
                isActive: isActive,
                isInteracting: isInteracting
            )
        ) {
            guard isActive, !isInteracting else { return }
            guard let interval = automaticDismissInterval(item.id, clock.now()) else {
                return
            }
            do {
                try await clock.sleep(for: interval)
            } catch {
                return
            }
            guard !Task.isCancelled, isActive, !isInteracting else { return }
            dismissAutomatically()
        }
    }

    private var milestoneIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(display.tintColor.opacity(0.12))

            milestoneArtwork
        }
        .frame(width: 58, height: 58)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(display.tintColor.opacity(0.25), lineWidth: 1.25)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var milestoneArtwork: some View {
        switch display.artwork {
        case .bundledImage(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
        case .systemSymbol(let name):
            Image(systemName: name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(display.tintColor)
                .frame(width: 40, height: 40)
        }
    }

    private var accessibilityLabel: String {
        var components = [display.eyebrow, display.title, display.subtitle]
            .compactMap { $0 }

        if pendingItemCount > 0 {
            components.append(pendingNotificationDescription)
        }

        return components.joined(separator: ", ")
    }

    private var pendingNotificationDescription: String {
        pendingItemCount == 1
            ? "1 more notification"
            : "\(pendingItemCount) more notifications"
    }

    private var dragDistance: CGFloat {
        MilestoneToastDismissalGesture.distance(for: dragOffset)
    }

    private var dragOpacity: Double {
        1 - Double(min(dragDistance / 420, 1)) * 0.42
    }

    private var dragScale: CGFloat {
        1 - min(dragDistance / 2_400, 0.04)
    }

    private var display: DisplayModel {
        switch item.payload {
        case .fieldTrip(let progress):
            DisplayModel(
                eyebrow: "Field trip progress",
                title: progress.title,
                subtitle: progress.tripTitle,
                artwork: progress.artwork,
                tintColor: .green,
                accessibilityIdentifier: "MilestoneToastBanner_FieldTrip",
                accessibilityHint: "Opens this Field trip. Swipe horizontally or vertically to dismiss."
            )
        case .achievement(let award):
            DisplayModel(
                eyebrow: "Achievement unlocked",
                title: award.title,
                subtitle: award.descriptionText,
                artwork: .bundledImage(name: award.definition.imageName),
                tintColor: award.definition.tintToken.color,
                accessibilityIdentifier: "AchievementToastBanner_\(award.type.rawValue)",
                accessibilityHint: award.destination == nil
                    ? "Opens achievement details. Swipe horizontally or vertically to dismiss."
                    : "Opens the completed Field trip. Swipe horizontally or vertically to dismiss."
            )
        case .dictionary(let milestone):
            DisplayModel(
                eyebrow: "Field guide milestone",
                title: milestone.title,
                subtitle: milestone.subtitle,
                artwork: .bundledImage(name: milestone.imageName),
                tintColor: .green,
                accessibilityIdentifier: "MilestoneToastBanner_NewToMerian",
                accessibilityHint: "Swipe horizontally or vertically to dismiss."
            )
        }
    }

    private func firePresentationEffectsIfNeeded() {
        guard isActive, !hasFiredPresentationEffects else { return }

        hasFiredPresentationEffects = true
        guard onClaimPresentationEffects(item.id, clock.now()) else { return }
        HapticManager.shared.triggerSuccessPulse()

        if UIAccessibility.isVoiceOverRunning {
            let queueAnnouncement = pendingItemCount > 0
                ? ". \(pendingNotificationDescription)"
                : ""
            UIAccessibility.post(
                notification: .announcement,
                argument: "\(display.eyebrow). \(display.title)\(queueAnnouncement)"
            )
        }
    }

    private func dismissAutomatically() {
        guard isActive, !isDismissing else { return }
        isDismissing = true
        onDismiss()
    }

    private func dismissManually() {
        guard isActive, !isDismissing else { return }

        HapticManager.shared.triggerLightImpact(
            intensity: 0.45,
            source: "milestoneToast.dismiss.button"
        )
        dismissAutomatically()
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard isActive, !isDismissing else { return }

        if !isInteracting {
            isInteracting = true
        }

        let resolvedAxis = dragAxis ?? MilestoneToastDismissalGesture.axis(for: value.translation)
        dragAxis = resolvedAxis
        let constrainedTranslation = MilestoneToastDismissalGesture.constrainedTranslation(
            value.translation,
            to: resolvedAxis
        )
        dragOffset = constrainedTranslation
        let hasReachedThreshold = MilestoneToastDismissalGesture.hasReachedCommitDistance(
            constrainedTranslation
        )

        if hasReachedThreshold && !hasReachedDismissThreshold {
            HapticManager.shared.triggerSelectionPulse(source: "milestoneToast.dismiss.threshold")
        }
        hasReachedDismissThreshold = hasReachedThreshold
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        guard isActive, !isDismissing else { return }

        let resolvedAxis = dragAxis ?? MilestoneToastDismissalGesture.axis(for: value.translation)
        let translation = MilestoneToastDismissalGesture.constrainedTranslation(
            value.translation,
            to: resolvedAxis
        )
        let predictedEndTranslation = MilestoneToastDismissalGesture.constrainedTranslation(
            value.predictedEndTranslation,
            to: resolvedAxis
        )

        if MilestoneToastDismissalGesture.shouldDismiss(
            translation: translation,
            predictedEndTranslation: predictedEndTranslation
        ) {
            dismissByDrag(
                translation: translation,
                predictedEndTranslation: predictedEndTranslation
            )
        } else {
            resetDrag()
        }
    }

    private func dismissByDrag(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) {
        isDismissing = true
        HapticManager.shared.triggerLightImpact(
            intensity: 0.72,
            source: "milestoneToast.dismiss.drag"
        )

        let offscreenOffset = MilestoneToastDismissalGesture.offscreenOffset(
            translation: translation,
            predictedEndTranslation: predictedEndTranslation
        )

        guard !reduceMotion else {
            dragOffset = offscreenOffset
            dismissalOpacity = 0
            onDismiss()
            return
        }

        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = offscreenOffset
            dismissalOpacity = 0
        } completion: {
            onDismiss()
        }
    }

    private func resetDrag() {
        dragAxis = nil
        hasReachedDismissThreshold = false
        isInteracting = false

        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.84)) {
            dragOffset = .zero
            dismissalOpacity = 1
        }
    }

    private func open() {
        guard isActive, !isDismissing else { return }

        HapticManager.shared.triggerSelectionPulse()

        switch item.payload {
        case .fieldTrip(let progress):
            onOpenFieldTrip?(progress.destination)
        case .achievement(let award):
            if let destination = award.destination {
                onOpenFieldTrip?(destination)
            } else {
                onOpenAchievement?(award)
            }
        case .dictionary:
            break
        }

        dismissAutomatically()
    }

    private struct DisplayModel {
        let eyebrow: String
        let title: String
        let subtitle: String?
        let artwork: CaptureGoalArtwork
        let tintColor: Color
        let accessibilityIdentifier: String
        let accessibilityHint: String
    }

    private struct PresentationContext: Equatable {
        let itemID: UUID
        let isActive: Bool
    }

    private struct AutomaticDismissContext: Equatable {
        let itemID: UUID
        let isActive: Bool
        let isInteracting: Bool
    }
}

struct MilestoneToastStack: View {
    let items: [MilestoneToastItem]
    let clock: any MilestoneToastClock
    let onClaimPresentationEffects: (UUID, Date) -> Bool
    let automaticDismissInterval: (UUID, Date) -> TimeInterval?
    let onDismiss: (UUID) -> Void
    var onOpenAchievement: ((AwardPayload) -> Void)?
    var onOpenFieldTrip: ((CaptureGoalDestination) -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            // Keep queued payload subtrees unmounted. ToastBanner already draws
            // up to two lightweight decorative backplates from pendingItemCount;
            // mounting queued cards as well would duplicate material layers and
            // allow their text/control planes to collide behind the active card.
            if let presentation = MilestoneToastStackPresentation.resolve(items) {
                MilestoneToastBanner(
                    item: presentation.activeItem,
                    pendingItemCount: presentation.pendingItemCount,
                    isActive: true,
                    clock: clock,
                    onClaimPresentationEffects: onClaimPresentationEffects,
                    automaticDismissInterval: automaticDismissInterval,
                    onDismiss: {
                        onDismiss(presentation.activeItem.id)
                    },
                    onOpenAchievement: onOpenAchievement,
                    onOpenFieldTrip: onOpenFieldTrip
                )
                .id(presentation.activeItem.id)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(
            .spring(response: 0.36, dampingFraction: 0.86),
            value: items.first?.id
        )
    }
}

struct MilestoneToastStackPresentation: Equatable {
    let activeItem: MilestoneToastItem
    let pendingItemCount: Int

    static func resolve(_ items: [MilestoneToastItem]) -> MilestoneToastStackPresentation? {
        guard let activeItem = items.first else { return nil }
        return MilestoneToastStackPresentation(
            activeItem: activeItem,
            pendingItemCount: max(
                items.count - ToastStackPresentation.maximumMountedPayloadCount,
                0
            )
        )
    }
}

typealias AchievementToastBanner = MilestoneToastBanner
