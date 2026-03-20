import SwiftUI

struct TaxonomyNode: View {
    let level: String
    let name: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(level)
                .font(.system(.caption2, design: .serif))
                .bold()
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(name)
                .font(.system(.subheadline, design: .serif))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color(UIColor.separator), lineWidth: 1)
        )
    }
}
