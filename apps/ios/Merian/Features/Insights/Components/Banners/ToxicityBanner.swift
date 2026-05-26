import SwiftUI

struct ToxicityBanner: View {
    @Environment(InferenceEngine.self) var inferenceEngine

    private let explicitHazardType: String?

    init(hazardType: String? = nil) {
        self.explicitHazardType = hazardType
    }

    private var hazardType: String {
        (explicitHazardType ?? inferenceEngine.speciesData?.insightData.hazardType ?? "none")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var bannerTitle: String {
        switch hazardType {
        case "venomous":   return "Venomous"
        case "allergenic": return "Allergenic"
        case "irritant":   return "Irritant"
        case "poisonous":  return "Toxic"
        default:           return "Toxic"
        }
    }

    private var bannerSubtitle: String {
        switch hazardType {
        case "venomous":   return "Can inject venom through bite or sting. Do not handle."
        case "allergenic": return "May trigger severe allergic reactions in some individuals."
        case "irritant":   return "May cause skin or eye irritation on contact."
        default:           return "This species may be harmful. Avoid physical contact."
        }
    }

    private var baseColor: Color {
        switch hazardType {
        case "venomous", "poisonous": return .red
        default:                      return .yellow
        }
    }

    var body: some View {
        if hazardType != "none" {

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
                    .fill(baseColor.opacity(0.9)) // Subsurface threat ambient tint
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [baseColor.opacity(0.8), baseColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .foregroundColor(.primary)
            // Accessibility: Explicitly anchor screen readers to the threat first
            .accessibilityAddTraits(.isHeader)
            .allowsHitTesting(false)
        }
    }
}
