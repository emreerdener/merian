import SwiftUI

struct ConfidenceBadge: View {
    let confidenceScore: Double?
    
    var body: some View {
        if let score = confidenceScore, score > 0 {
            Badge(
                text: "\(Int(score * 100))% confident",
                color: score >= 0.85 ? Color(red: 0.11, green: 0.52, blue: 0.28) : .orange,
                icon: "sparkles.2",
                isFilled: true
            )
        }
    }
}
