import SwiftUI

struct AIReasoningCard: View {
    let diagnosticData: DiagnosticComparison
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header Row
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reasoning")
                                .font(.system(.headline))
                                .foregroundColor(.primary)
                            
                            Text("NEURAL ENGINE V4.2")
                                .font(.system(.caption2, design: .monospaced)) // sleek neon typography feel
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                    }
                    Spacer()
                }
                
                // Faint Watermark
                Image(systemName: "leaf.fill")
                    .font(.system(size: 44))
                    .foregroundColor(Color(UIColor.label).opacity(0.04))
                    .offset(x: 10, y: -10)
            }
            
            // Body: Primary Rationale
            Text(diagnosticData.primaryMatchRationale)
                .font(.system(.subheadline))
                .foregroundColor(.primary)
                .lineSpacing(4)
            
            // Lookalike Block
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 3)
                    .cornerRadius(1.5)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Potential Lookalike")
                        .font(.system(.caption))
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    
                    Text("This specimen shares strong morphological traits with \(diagnosticData.confusingLookalikeName).")
                        .font(.system(.footnote))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(UIColor.tertiarySystemFill))
            .cornerRadius(12)
            
            // Morphological Weighting (Key Differentiators)
            VStack(alignment: .leading, spacing: 12) {
                Text("MORPHOLOGICAL ANALYSIS")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                ForEach(Array(diagnosticData.keyDifferentiators.enumerated()), id: \.element) { index, diff in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.green.opacity(0.8))
                            .padding(.top, 2)
                        
                        Text(diff)
                            .font(.system(.subheadline))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 4)
        }
        .card()
    }
}
