import SwiftUI

struct ConfidenceHeader: View {
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Confidence score")
                    .font(.system(.title, design: .serif).weight(.bold))
                    .foregroundStyle(.primary)
                
                Text("Merian's AI calculates a confidence score out of 100 by analyzing your images alongside GPS location, elevation level, weather data, and more to maximize accuracy.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineSpacing(4)
            }
        }
    }
}
