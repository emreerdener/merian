import SwiftUI

struct ConfidenceHeader: View {
    let title: String
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(.title, design: .serif).weight(.bold))
                    .foregroundStyle(.primary)
                
                Text("Naturebook’s confidence score is the AI model’s estimate of how likely the identification is to be correct, based on the available identification evidence.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineSpacing(4)
            }
        }
    }
}
