import SwiftUI

struct DiagnosticComparisonCard: View {
    let diagnosticData: DiagnosticComparison
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // MARK: - Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Differential Diagnosis")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Rule-out logic & lookalikes")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // MARK: - Primary Subject Traits
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Subject Morphology")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                }
                
                Text(diagnosticData.primaryMatchRationale)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
            
            // MARK: - Lookalike Target
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Common Lookalike")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.orange)
                        .textCase(.uppercase)
                }
                
                Text(diagnosticData.confusingLookalikeName)
                    .font(.body.italic())
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.15), lineWidth: 1)
            )
            
            // MARK: - Key Discrepancies
            VStack(alignment: .leading, spacing: 14) {
                Text("Key Discrepancies")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.top, 4)
                
                ForEach(diagnosticData.keyDifferentiators, id: \.self) { diff in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "minus.square.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange.opacity(0.6))
                            .padding(.top, 2)
                        
                        Text(diff)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    }
                }
            }
        }
        .card()
    }
}
