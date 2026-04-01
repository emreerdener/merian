import SwiftUI

struct ConfidenceHeader: View {
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("AI Analysis")
                    .font(.system(.title, design: .serif).weight(.bold))
                    .foregroundStyle(.primary)
                
                Text("Merian evaluates your capture alongside GPS coordinates, topographic elevation, and weather conditions to power its reasoning models and calculate a precise confidence score.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineSpacing(4)
            }
        }
    }
}
