import SwiftUI
import UIKit

private struct CaptureGoalIndicatorCollapseButton: View {
    let accessibilityLabel: String
    let accessibilityHint: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .font(.body.weight(.semibold))
                .frame(
                    width: CaptureGoalIndicatorLayoutPolicy.expandedSize,
                    height: CaptureGoalIndicatorLayoutPolicy.expandedSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct CaptureGoalIndicator: View {
    let presentation: ActiveCaptureGoalPresentation
    @Binding var expansionState: CaptureGoalIndicatorExpansionState
    let onOpen: (CaptureGoalDestination) -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSelectionFeedback: (String) -> Void
    let onOpenFeedback: (String) -> Void

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .goal(let goal):
            ActiveCaptureGoalIndicator(
                goal: goal,
                expansionState: $expansionState,
                onOpen: { onOpen(goal.destination) },
                onNext: onNext,
                onPrevious: onPrevious,
                onSelectionFeedback: onSelectionFeedback,
                onOpenFeedback: onOpenFeedback
            )
        case .introduction(let introduction):
            CaptureGoalIntroductionIndicator(
                introduction: introduction,
                expansionState: $expansionState,
                onOpen: { onOpen(introduction.destination) },
                onSelectionFeedback: onSelectionFeedback,
                onOpenFeedback: onOpenFeedback
            )
        }
    }
}

private struct CaptureGoalIntroductionIndicator: View {
    private struct ArtworkRotationTaskID: Equatable {
        let introductionID: String
        let artworks: [CaptureGoalArtwork]
        let reduceMotion: Bool
    }

    let introduction: CaptureGoalIntroduction
    @Binding var expansionState: CaptureGoalIndicatorExpansionState
    let onOpen: () -> Void
    let onSelectionFeedback: (String) -> Void
    let onOpenFeedback: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkIndex = 0

    private var artworks: [CaptureGoalArtwork] {
        introduction.artworks.isEmpty
            ? [.systemSymbol(name: "binoculars.fill")]
            : introduction.artworks
    }

    private var displayedArtwork: CaptureGoalArtwork {
        CaptureGoalArtworkRotation.artwork(at: artworkIndex, in: artworks)
    }

    private var displayedArtworkID: String {
        switch displayedArtwork {
        case .bundledImage(let imageName):
            "bundled:\(imageName)"
        case .systemSymbol(let symbolName):
            "symbol:\(symbolName)"
        }
    }

    private var artworkRotationTaskID: ArtworkRotationTaskID {
        ArtworkRotationTaskID(
            introductionID: introduction.id,
            artworks: artworks,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        indicatorSurface
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("captureGoalIntroductionIndicator")
            .task(id: introduction.id) {
                AppTelemetry.trackCaptureGoalIndicator(
                    action: .zeroStateShown,
                    source: introduction.sourceKind
                )
            }
            .task(id: artworkRotationTaskID) {
                artworkIndex = 0
                let artworkCount = artworks.count
                guard !reduceMotion, artworkCount > 1 else { return }
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(3))
                    } catch {
                        return
                    }
                    artworkIndex = CaptureGoalArtworkRotation.nextIndex(
                        after: artworkIndex,
                        count: artworkCount
                    )
                }
            }
            // Expand only the alignment frame. The glass surface above remains
            // the sole hit-testing and gesture region over the camera.
            .frame(
                maxWidth: .infinity,
                alignment: expansionState.isExpanded ? .leading : .trailing
            )
    }

    private var indicatorSurface: some View {
        HStack(spacing: 0) {
            artworkButton

            if expansionState.isExpanded {
                HStack(spacing: 0) {
                    openButton
                    collapseButton
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .foregroundStyle(.primary)
        .frame(
            maxWidth: expansionState.isExpanded ? .infinity : nil,
            minHeight: CaptureGoalIndicatorLayoutPolicy.surfaceSize(
                isExpanded: expansionState.isExpanded
            ),
            alignment: .leading
        )
        .clipShape(Capsule())
        .modifier(ActiveCaptureGoalGlassModifier())
        .contentShape(Capsule())
    }

    private var artworkButton: some View {
        Button(action: toggleExpansion) {
            ZStack {
                // Keep one resting image in the live hierarchy instead of
                // depending on opacity-zero siblings during camera/glass redraws.
                CaptureGoalArtworkView(
                    artwork: displayedArtwork,
                    size: CaptureGoalIndicatorLayoutPolicy.artworkSize(
                        isExpanded: expansionState.isExpanded
                    )
                )
                .id(displayedArtworkID)
                .transition(.opacity)
            }
            .frame(
                width: CaptureGoalIndicatorLayoutPolicy.surfaceSize(
                    isExpanded: expansionState.isExpanded
                ),
                height: CaptureGoalIndicatorLayoutPolicy.surfaceSize(
                    isExpanded: expansionState.isExpanded
                )
            )
            .contentShape(Circle())
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.2),
                value: displayedArtworkID
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            expansionState.isExpanded
                ? CaptureGoalIndicatorAccessibilityCopy.introductionCollapseLabel
                : introduction.accessibilityLabel
        )
        .accessibilityValue(
            expansionState.isExpanded ? "" : introduction.accessibilityValue
        )
        .accessibilityHint(
            expansionState.isExpanded
                ? CaptureGoalIndicatorAccessibilityCopy.introductionCollapseHint
                : CaptureGoalIndicatorAccessibilityCopy.introductionExpandHint
        )
        .accessibilityIdentifier("captureGoalIntroductionArtworkToggle")
    }

    private var openButton: some View {
        Button {
            onOpenFeedback("capture.goalIntroduction.open")
            AppTelemetry.trackCaptureGoalIndicator(
                action: .zeroStateOpened,
                source: introduction.sourceKind
            )
            onOpen()
        } label: {
            VStack(alignment: .center, spacing: 2) {
                Text(introduction.headline)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)

                Text(introduction.subheadline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(introduction.accessibilityLabel)
        .accessibilityValue(introduction.accessibilityValue)
        .accessibilityHint(introduction.accessibilityHint)
        .accessibilityIdentifier("captureGoalIntroductionOpenButton")
    }

    private var collapseButton: some View {
        CaptureGoalIndicatorCollapseButton(
            accessibilityLabel: CaptureGoalIndicatorAccessibilityCopy
                .introductionCollapseLabel,
            accessibilityHint: CaptureGoalIndicatorAccessibilityCopy
                .introductionCollapseHint,
            accessibilityIdentifier: "captureGoalIntroductionCollapseButton",
            action: toggleExpansion
        )
    }

    private func toggleExpansion() {
        onSelectionFeedback("capture.goalIndicator.toggle")
        if reduceMotion {
            expansionState = expansionState.toggled
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                expansionState = expansionState.toggled
            }
        }
    }
}

private struct ActiveCaptureGoalIndicator: View {
    let goal: CaptureGoal
    @Binding var expansionState: CaptureGoalIndicatorExpansionState
    let onOpen: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSelectionFeedback: (String) -> Void
    let onOpenFeedback: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        indicatorSurface
            .highPriorityGesture(selectionGesture)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("activeCaptureGoalIndicator")
            .task(id: goal.id) {
                AppTelemetry.trackCaptureGoalIndicator(action: .shown, source: goal.source.kind)
            }
            // Expand only the alignment frame. The glass surface above remains
            // the sole hit-testing and gesture region over the camera.
            .frame(
                maxWidth: .infinity,
                alignment: expansionState.isExpanded ? .leading : .trailing
            )
    }

    private var indicatorSurface: some View {
        HStack(spacing: 0) {
            artworkButton

            if expansionState.isExpanded {
                HStack(spacing: 0) {
                    openButton
                    collapseButton
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .foregroundStyle(.primary)
        .frame(
            maxWidth: expansionState.isExpanded ? .infinity : nil,
            minHeight: CaptureGoalIndicatorLayoutPolicy.surfaceSize(
                isExpanded: expansionState.isExpanded
            ),
            alignment: .leading
        )
        .clipShape(Capsule())
        .modifier(ActiveCaptureGoalGlassModifier())
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var artworkButton: some View {
        if expansionState.isExpanded {
            baseArtworkButton
                .accessibilityLabel(
                    CaptureGoalIndicatorAccessibilityCopy.goalCollapseLabel
                )
                .accessibilityHint(
                    CaptureGoalIndicatorAccessibilityCopy.goalCollapseHint
                )
        } else {
            baseArtworkButton
                .accessibilityLabel(
                    ActiveCaptureGoalIndicatorCopy.accessibilityLabel(
                        for: goal.prompt
                    )
                )
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(
                    CaptureGoalIndicatorAccessibilityCopy.goalExpandHint
                )
                .accessibilityAdjustableAction(handleAccessibilityAdjustment)
        }
    }

    private var baseArtworkButton: some View {
        Button(action: toggleExpansion) {
            CaptureGoalArtworkView(
                artwork: goal.artwork,
                size: CaptureGoalIndicatorLayoutPolicy.artworkSize(
                    isExpanded: expansionState.isExpanded
                )
            )
            .frame(
                width: CaptureGoalIndicatorLayoutPolicy.surfaceSize(
                    isExpanded: expansionState.isExpanded
                ),
                height: CaptureGoalIndicatorLayoutPolicy.surfaceSize(
                    isExpanded: expansionState.isExpanded
                )
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activeCaptureGoalArtworkToggle")
    }

    private var openButton: some View {
        Button {
            onOpenFeedback("capture.activeGoal.open")
            AppTelemetry.trackCaptureGoalIndicator(action: .opened, source: goal.source.kind)
            onOpen()
        } label: {
            VStack(alignment: .center, spacing: 2) {
                Text(
                    ActiveCaptureGoalIndicatorCopy.instruction(for: goal.prompt)
                )
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)

                Text(goal.source.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(
            ActiveCaptureGoalIndicatorCopy.accessibilityLabel(for: goal.prompt)
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            CaptureGoalIndicatorAccessibilityCopy.goalOpenHint
        )
        .accessibilityIdentifier("activeCaptureGoalOpenButton")
        .accessibilityAdjustableAction(handleAccessibilityAdjustment)
    }

    private var collapseButton: some View {
        CaptureGoalIndicatorCollapseButton(
            accessibilityLabel: CaptureGoalIndicatorAccessibilityCopy.goalCollapseLabel,
            accessibilityHint: CaptureGoalIndicatorAccessibilityCopy.goalCollapseHint,
            accessibilityIdentifier: "activeCaptureGoalCollapseButton",
            action: toggleExpansion
        )
    }

    private var accessibilityValue: String {
        CaptureGoalIndicatorAccessibilityCopy.progressValue(
            sourceTitle: goal.source.title,
            completedCount: goal.progress.completedCount,
            targetCount: goal.progress.targetCount
        )
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard let direction = ActiveCaptureGoalSwipeDirection.resolve(
                    horizontal: value.translation.width,
                    vertical: value.translation.height
                ) else {
                    return
                }
                changeSelection(next: direction == .next)
            }
    }

    private func toggleExpansion() {
        onSelectionFeedback("capture.goalIndicator.toggle")
        if reduceMotion {
            expansionState = expansionState.toggled
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                expansionState = expansionState.toggled
            }
        }
    }

    private func handleAccessibilityAdjustment(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            changeSelection(next: true)
        case .decrement:
            changeSelection(next: false)
        @unknown default:
            break
        }
    }

    private func changeSelection(next: Bool) {
        onSelectionFeedback("capture.activeGoal")
        AppTelemetry.trackCaptureGoalIndicator(
            action: next ? .next : .previous,
            source: goal.source.kind
        )
        if reduceMotion {
            if next {
                onNext()
            } else {
                onPrevious()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                if next {
                    onNext()
                } else {
                    onPrevious()
                }
            }
        }
    }
}

private struct CaptureGoalArtworkView: View {
    let artwork: CaptureGoalArtwork
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        switch artwork {
        case .bundledImage(let imageName):
            if let image = UIImage(named: imageName) {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            } else {
                systemSymbol(named: "binoculars.fill")
            }
        case .systemSymbol(let symbolName):
            systemSymbol(named: symbolName)
        }
    }

    private func systemSymbol(named symbolName: String) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 19 / 36, weight: .semibold))
            .frame(width: size, height: size)
            .background(.primary.opacity(0.08), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct ActiveCaptureGoalGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }
}
