import SwiftUI

struct SectionLabel: View {
    let title: String
    var isRequired: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.7))
            if isRequired {
                Text("required")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}
