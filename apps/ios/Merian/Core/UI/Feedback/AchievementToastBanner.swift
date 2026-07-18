import SwiftUI

struct MilestoneToastBanner: View {
    let item: MilestoneToastItem
    let onDismiss: () -> Void
    var onOpenAchievement: ((AwardPayload) -> Void)?
    var onOpenFieldTrip: ((CaptureGoalDestination) -> Void)?

    @State private var hasFiredPresentationEffects = false

    var body: some View {
        ToastBanner(onDismiss: dismissManually) {
            HStack(spacing: 14) {
                if fieldTripProgress == nil {
                    milestoneIcon
                }

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

                Spacer(minLength: 0)

                if let progress = fieldTripProgress {
                    GoalProgressRing(
                        completedCount: progress.completedCount,
                        targetCount: progress.targetCount,
                        lineWidth: 4.5,
                        labelFontSize: 10
                    )
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                open()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.height > 18 {
                        dismissManually()
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(display.accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(display.accessibilityIdentifier)
        .onChange(of: item.id, initial: true) { _, _ in
            hasFiredPresentationEffects = false
            firePresentationEffectsIfNeeded()
        }
        .task(id: item.id) {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissAutomatically()
            }
        }
    }

    private var milestoneIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(display.tintColor.opacity(0.12))

            Image(display.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
        }
        .frame(width: 58, height: 58)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(display.tintColor.opacity(0.25), lineWidth: 1.25)
        )
        .accessibilityHidden(true)
    }

    private var fieldTripProgress: FieldTripMilestonePayload? {
        guard case let .fieldTrip(progress) = item.payload else { return nil }
        return progress
    }

    private var accessibilityLabel: String {
        let text = [display.eyebrow, display.title, display.subtitle]
            .compactMap { $0 }
            .joined(separator: ", ")

        guard let progress = fieldTripProgress else { return text }
        return "\(text), \(progress.completedCount) of \(progress.targetCount) goals complete"
    }

    private var display: DisplayModel {
        switch item.payload {
        case .fieldTrip(let progress):
            DisplayModel(
                eyebrow: "Field trip progress",
                title: progress.message,
                subtitle: nil,
                imageName: "",
                tintColor: .blue,
                accessibilityIdentifier: "MilestoneToastBanner_FieldTrip",
                accessibilityHint: "Opens this Field trip."
            )
        case .achievement(let award):
            DisplayModel(
                eyebrow: "Achievement unlocked",
                title: award.title,
                subtitle: award.descriptionText,
                imageName: award.definition.imageName,
                tintColor: award.definition.tintToken.color,
                accessibilityIdentifier: "AchievementToastBanner_\(award.type.rawValue)",
                accessibilityHint: "Opens achievement details."
            )
        case .dictionary(let milestone):
            DisplayModel(
                eyebrow: "Field guide milestone",
                title: milestone.title,
                subtitle: milestone.subtitle,
                imageName: milestone.imageName,
                tintColor: .green,
                accessibilityIdentifier: "MilestoneToastBanner_NewToMerian",
                accessibilityHint: "Dismisses the notification."
            )
        }
    }

    private func firePresentationEffectsIfNeeded() {
        guard !hasFiredPresentationEffects else { return }

        hasFiredPresentationEffects = true
        HapticManager.shared.triggerSuccessPulse()

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: "\(display.eyebrow). \(display.title)"
            )
        }
    }

    private func dismissAutomatically() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            onDismiss()
        }
    }

    private func dismissManually() {
        HapticManager.shared.triggerLightImpact(intensity: 0.45)
        dismissAutomatically()
    }

    private func open() {
        HapticManager.shared.triggerSelectionPulse()

        switch item.payload {
        case .fieldTrip(let progress):
            onOpenFieldTrip?(progress.destination)
        case .achievement(let award):
            onOpenAchievement?(award)
        case .dictionary:
            break
        }

        dismissAutomatically()
    }

    private struct DisplayModel {
        let eyebrow: String
        let title: String
        let subtitle: String?
        let imageName: String
        let tintColor: Color
        let accessibilityIdentifier: String
        let accessibilityHint: String
    }
}

typealias AchievementToastBanner = MilestoneToastBanner
