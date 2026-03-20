import SwiftUI

struct TaxonomyNode: View {
    let level: String
    let name: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(level)
                .font(.system(.caption2, design: .serif))
                .bold()
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
            Text(name)
                .font(.system(.subheadline, design: .serif))
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}
