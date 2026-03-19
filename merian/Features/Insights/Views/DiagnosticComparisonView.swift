import SwiftUI

struct DiagnosticComparisonView: View {
    let diagnosticData: DiagnosticComparison
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Uncertainty: \(diagnosticData.primaryMatchRationale)")
                .font(.headline)
                .foregroundColor(.orange)
                .accessibilityAddTraits(.isHeader)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Differentiating Traits against \(diagnosticData.confusingLookalikeName):")
                    .font(.subheadline)
                    .bold()
                
                ForEach(diagnosticData.keyDifferentiators, id: \.self) { diff in
                    HStack(alignment: .top) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.gray)
                            .padding(.top, 6)
                        Text(diff)
                            .font(.callout)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(diff)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
