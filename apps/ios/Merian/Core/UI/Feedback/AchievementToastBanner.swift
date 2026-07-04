import SwiftUI

struct AchievementToastBanner: View {
    let item: AchievementToastItem
    let onDismiss: () -> Void
    var onOpen: (() -> Void)?

    @State private var hasFiredPresentationEffects = false

    var body: some View {
        ToastBanner(onDismiss: dismissManually) {
            HStack(spacing: 14) {
                achievementIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text("Achievement unlocked")
                        .font(.caption)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    Text(item.award.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.award.descriptionText)
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
        .accessibilityLabel("Achievement unlocked, \(item.award.title), \(item.award.descriptionText)")
        .accessibilityHint(onOpen == nil ? "Dismisses automatically." : "Opens achievement details.")
        .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
        .accessibilityIdentifier("AchievementToastBanner_\(item.award.type.rawValue)")
        .onAppear(perform: firePresentationEffectsIfNeeded)
        .task(id: item.id) {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissAutomatically()
            }
        }
    }

    private var achievementIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(item.award.definition.tintToken.color.opacity(0.12))

            Image(item.award.definition.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
        }
        .frame(width: 58, height: 58)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(item.award.definition.tintToken.color.opacity(0.25), lineWidth: 1.25)
        )
        .accessibilityHidden(true)
    }

    private func firePresentationEffectsIfNeeded() {
        guard !hasFiredPresentationEffects else { return }

        hasFiredPresentationEffects = true
        HapticManager.shared.triggerSuccessPulse()

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Achievement unlocked. \(item.award.title)"
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
        guard let onOpen else { return }

        HapticManager.shared.triggerSelectionPulse()
        onOpen()
        dismissAutomatically()
    }
}
