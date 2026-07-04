import SwiftUI

struct MilestoneToastBanner: View {
    let item: MilestoneToastItem
    let onDismiss: () -> Void
    var onOpenAchievement: ((AwardPayload) -> Void)?

    @State private var hasFiredPresentationEffects = false

    var body: some View {
        ToastBanner(onDismiss: dismissManually) {
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

                    Text(display.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                open()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.height < -18 {
                        dismissManually()
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(display.eyebrow), \(display.title), \(display.subtitle)")
        .accessibilityHint(display.opensDetails ? "Opens achievement details." : "Dismisses the notification.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(display.accessibilityIdentifier)
        .onAppear(perform: firePresentationEffectsIfNeeded)
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

    private var display: DisplayModel {
        switch item.payload {
        case .achievement(let award):
            DisplayModel(
                eyebrow: "Achievement unlocked",
                title: award.title,
                subtitle: award.descriptionText,
                imageName: award.definition.imageName,
                tintColor: award.definition.tintToken.color,
                accessibilityIdentifier: "AchievementToastBanner_\(award.type.rawValue)",
                opensDetails: true
            )
        case .dictionary(let milestone):
            DisplayModel(
                eyebrow: "Field guide milestone",
                title: milestone.title,
                subtitle: milestone.subtitle,
                imageName: milestone.imageName,
                tintColor: .green,
                accessibilityIdentifier: "MilestoneToastBanner_NewToMerian",
                opensDetails: false
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

        if case let .achievement(award) = item.payload {
            onOpenAchievement?(award)
        }

        dismissAutomatically()
    }

    private struct DisplayModel {
        let eyebrow: String
        let title: String
        let subtitle: String
        let imageName: String
        let tintColor: Color
        let accessibilityIdentifier: String
        let opensDetails: Bool
    }
}

typealias AchievementToastBanner = MilestoneToastBanner
