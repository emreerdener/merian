import SwiftUI

struct MilestoneToastBanner: View {
    let item: MilestoneToastItem
    var pendingItemCount = 0
    let onDismiss: () -> Void
    var onOpenAchievement: ((AwardPayload) -> Void)?
    var onOpenFieldTrip: ((CaptureGoalDestination) -> Void)?

    @State private var hasFiredPresentationEffects = false

    var body: some View {
        ToastBanner(
            onDismiss: dismissManually,
            pendingItemCount: pendingItemCount
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
                accessibilityHint: "Opens this Field trip."
            )
        case .achievement(let award):
            DisplayModel(
                eyebrow: "Achievement unlocked",
                title: award.title,
                subtitle: award.descriptionText,
                artwork: .bundledImage(name: award.definition.imageName),
                tintColor: award.definition.tintToken.color,
                accessibilityIdentifier: "AchievementToastBanner_\(award.type.rawValue)",
                accessibilityHint: "Opens achievement details."
            )
        case .dictionary(let milestone):
            DisplayModel(
                eyebrow: "Field guide milestone",
                title: milestone.title,
                subtitle: milestone.subtitle,
                artwork: .bundledImage(name: milestone.imageName),
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
        let artwork: CaptureGoalArtwork
        let tintColor: Color
        let accessibilityIdentifier: String
        let accessibilityHint: String
    }
}

typealias AchievementToastBanner = MilestoneToastBanner
