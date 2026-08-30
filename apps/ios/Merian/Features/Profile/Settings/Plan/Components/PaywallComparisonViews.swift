import SwiftUI

struct PaywallComparisonRow: View {
    let comparison: PaywallFeatureComparison

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(comparison.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            PaywallComparisonValue(
                value: comparison.freeValue,
                tint: .secondary
            )

            PaywallComparisonValue(
                value: comparison.proValue,
                tint: .mint
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(comparison.title). Free: \(comparison.freeValue). Pro: \(comparison.proValue)."
        )
    }
}

private struct PaywallComparisonValue: View {
    let value: String
    let tint: Color

    var body: some View {
        Group {
            if value == "Included" {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(tint)
                    .accessibilityLabel("Included")
            } else if value == "-" {
                Image(systemName: "minus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.58))
                    .accessibilityLabel("Not included")
            } else {
                Text(value)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(tint)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 72)
        .frame(minHeight: 24)
    }
}
