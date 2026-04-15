import SwiftUI

struct OrganismClassGrid: View {
    @Binding var selection: OrganismClass?

    private let columns = [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(OrganismClass.allCases, id: \.self) { cls in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = selection == cls ? nil : cls
                    }
                    HapticManager.shared.triggerFocusSnap()
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: cls.systemImage)
                            .font(.system(size: 22))
                        Text(cls.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == cls ? .black : .white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selection == cls ? Color.white : Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                selection == cls ? Color.clear : Color.white.opacity(0.12),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
    }
}
