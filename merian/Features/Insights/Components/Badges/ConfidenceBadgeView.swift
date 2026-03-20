import SwiftUI

struct ConfidenceBadgeView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    var body: some View {
        if let score = inferenceEngine.speciesData?.confidenceScore, score > 0 {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("\(Int(score * 100))% CONFIDENCE")
                    .font(.system(.caption))
                    .fontWeight(.bold)
                    .tracking(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(score >= 0.85 ? Color.green.opacity(0.9) : Color.orange.opacity(0.9))
            .background(score >= 0.85 ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(score >= 0.85 ? Color.green.opacity(0.5) : Color.orange.opacity(0.5), lineWidth: 0.5)
            )
        }
    }
}
