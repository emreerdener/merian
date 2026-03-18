import SwiftUI

struct DiagnosticComparisonView: View {
    let diagnosticData: DiagnosticComparison
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // 1. Diagnostics Header Breakdown
            Text("AI Uncertainty: \(diagnosticData.primaryMatchRationale)")
                .font(.headline)
                .foregroundColor(.orange)
                .accessibilityAddTraits(.isHeader)
            
            // 2. Visual Comparative Grid
            VStack(spacing: 0) {
                
                // A. Table Header
                HStack {
                    Text("Trait")
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Subject")
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(diagnosticData.confusingLookalikeName)
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                // VoiceOver ignores visual boundaries and natively announces table columns 
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Comparative Diagnostic Table for \(diagnosticData.confusingLookalikeName)")
                
                // B. Distinct Trait Rows
                ForEach(diagnosticData.keyDifferentiators) { diff in
                    HStack {
                        Text(diff.trait)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(diff.subjectValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(diff.lookalikeValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .border(Color.gray.opacity(0.1), width: 1)
                    
                    // C. Semantic Accessibility (Required) 
                    // Combines children elements together natively so VoiceOver cleanly states the array in sequence
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Trait: \(diff.trait). This subject: \(diff.subjectValue). Lookalike: \(diff.lookalikeValue).")
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
