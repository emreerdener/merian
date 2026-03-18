import SwiftUI

struct TaxonomyNode: View {
    let level: String
    let name: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(level)
                .font(.caption2)
                .bold()
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
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
