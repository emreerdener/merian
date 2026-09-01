import SwiftUI

struct ToxicityBanner: View {
    let hazardType: String

    private var normalizedHazardType: String {
        hazardType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var bannerTitle: String {
        switch normalizedHazardType {
        case "venomous": "Venomous"
        case "allergenic": "Allergenic"
        case "irritant": "Irritant"
        case "poisonous": "Toxic"
        default: "Toxic"
        }
    }

    private var bannerSubtitle: String {
        switch normalizedHazardType {
        case "venomous":
            "Can inject venom through bite or sting. Do not handle."
        case "allergenic":
            "May trigger severe allergic reactions in some individuals."
        case "irritant":
            "May cause skin or eye irritation on contact."
        default:
            "This species may be harmful. Avoid physical contact."
        }
    }

    private var baseColor: Color {
        switch normalizedHazardType {
        case "venomous", "poisonous": .red
        default: .yellow
        }
    }

    var body: some View {
        if normalizedHazardType != "none" {
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(baseColor.opacity(0.8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("CAUTION")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(1)

                    Text(bannerTitle)
                        .font(.system(.title3))
                        .fontWeight(.bold)

                    Text(bannerSubtitle)
                        .font(.system(.footnote))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.regularMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(baseColor.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                baseColor.opacity(0.8),
                                baseColor.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .foregroundColor(.primary)
            .accessibilityAddTraits(.isHeader)
            .allowsHitTesting(false)
        }
    }
}
