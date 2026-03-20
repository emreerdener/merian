import SwiftUI

struct ConfidenceBadgeView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    var body: some View {
        if let score = inferenceEngine.speciesData?.confidenceScore, score > 0 {
            HStack(spacing: 4) {
                Text("\(Int(score * 100))% CONFIDENCE")
                    .font(.system(.caption))
                    .fontWeight(.bold)
                    .tracking(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(.white)
            .background(score >= 0.85 ? Color.green : Color.orange)
            .clipShape(Capsule())
        }
    }
}
