import SwiftUI

struct ChipGrid<T: Hashable & CaseIterable>: View {
    let items: [T]
    @Binding var selection: Set<T>
    let label: (T) -> String
    let icon: ((T) -> String)?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isSelected = selection.contains(item)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isSelected { selection.remove(item) } else { selection.insert(item) }
                    }
                    HapticManager.shared.triggerFocusSnap()
                }) {
                    HStack(spacing: 5) {
                        if let iconFn = icon {
                            Image(systemName: iconFn(item))
                                .font(.caption)
                        }
                        Text(label(item))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isSelected ? Color.clear : Color.white.opacity(0.15),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isSelected ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: isSelected)
            }
        }
        .padding(.horizontal, 20)
    }
}
