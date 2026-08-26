import SwiftUI

struct FieldTripOutingLevelHeaderSkeleton: View {
    enum TrailingAccessory {
        case progressRing
        case lockedRing
    }

    let trailingAccessory: TrailingAccessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color.secondary.opacity(0.12))
                .frame(
                    width: FieldTripLevelHeaderLayout.accessorySize,
                    height: FieldTripLevelHeaderLayout.accessorySize
                )

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 112, height: 28)

            Spacer(minLength: 0)

            trailingAccessoryView
        }
    }

    @ViewBuilder
    private var trailingAccessoryView: some View {
        switch trailingAccessory {
        case .progressRing:
            ZStack {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.2),
                        lineWidth: FieldTripLevelHeaderLayout.ringLineWidth
                    )

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 30, height: 14)
            }
            .frame(
                width: FieldTripLevelHeaderLayout.accessorySize,
                height: FieldTripLevelHeaderLayout.accessorySize
            )
        case .lockedRing:
            ZStack {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.2),
                        lineWidth: FieldTripLevelHeaderLayout.ringLineWidth
                    )

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 14, height: 18)
            }
            .frame(
                width: FieldTripLevelHeaderLayout.accessorySize,
                height: FieldTripLevelHeaderLayout.accessorySize
            )
        }
    }
}

struct FieldTripLevelHeaderSkeleton: View {
    enum TrailingAccessory {
        case progressRing
        case lockedRing
        case balancedSpacer
        case completionLabel
    }

    let trailingAccessory: TrailingAccessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color.secondary.opacity(0.12))
                .frame(
                    width: FieldTripLevelHeaderLayout.accessorySize,
                    height: FieldTripLevelHeaderLayout.accessorySize
                )

            VStack(alignment: .center, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 112, height: 20)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: 164)
                    .frame(height: 11)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            trailingAccessoryView
        }
    }

    @ViewBuilder
    private var trailingAccessoryView: some View {
        switch trailingAccessory {
        case .progressRing:
            ZStack {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.2),
                        lineWidth: FieldTripLevelHeaderLayout.ringLineWidth
                    )

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 30, height: 14)
            }
            .frame(
                width: FieldTripLevelHeaderLayout.accessorySize,
                height: FieldTripLevelHeaderLayout.accessorySize
            )

        case .lockedRing:
            ZStack {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.2),
                        lineWidth: FieldTripLevelHeaderLayout.ringLineWidth
                    )

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 14, height: 18)
            }
            .frame(
                width: FieldTripLevelHeaderLayout.accessorySize,
                height: FieldTripLevelHeaderLayout.accessorySize
            )

        case .balancedSpacer:
            Color.clear
                .frame(
                    width: FieldTripLevelHeaderLayout.accessorySize,
                    height: FieldTripLevelHeaderLayout.accessorySize
                )

        case .completionLabel:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 48, height: 12)
                .frame(
                    width: FieldTripLevelHeaderLayout.accessorySize,
                    height: FieldTripLevelHeaderLayout.accessorySize
                )
        }
    }
}
