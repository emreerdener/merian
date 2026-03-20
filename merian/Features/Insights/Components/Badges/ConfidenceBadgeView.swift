import SwiftUI

struct ConfidenceBadgeView: View {
    let confidenceScore: Double?
    
    var body: some View {
        if let score = confidenceScore, score > 0 {
            BadgeView(
                text: "\(Int(score * 100))% confidence",
                color: score >= 0.85 ? .green : .orange,
                icon: "sparkles.2",
                isFilled: true
            )
        }
    }
}
