import SwiftUI

struct ToxicityBanner: View {
    @Environment(InferenceEngine.self) var inferenceEngine

    private var hazardType: String {
        inferenceEngine.speciesData?.insightData.hazardType ?? "none"
    }

    private var bannerTitle: String {
        switch hazardType {
        case "venomous":   return "Caution: Venomous"
        case "allergenic": return "Caution: Allergenic"
        case "irritant":   return "Caution: Irritant"
        case "poisonous":  return "Caution: Toxic"
        default:           return "Caution: Toxic"
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

    var body: some View {
        if hazardType != "none" {
            HStack {
                Image(systemName: "exclamationmark.circle")
                    .font(.title)
                VStack(alignment: .leading) {
                    Text(bannerTitle)
                        .font(.system(.headline))
                    Text(bannerSubtitle)
                        .font(.system(.subheadline))
                }
                Spacer()
            }
            .padding()
            .background(Color.yellow.opacity(0.8))
            .foregroundColor(.black)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
            )
            // Accessibility: Explicitly anchor screen readers to the threat first
            .accessibilityAddTraits(.isHeader)
            .allowsHitTesting(false)
        }
    }
}
