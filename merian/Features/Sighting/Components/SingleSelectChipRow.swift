import SwiftUI

struct SingleSelectChipRow<T: Hashable & CaseIterable>: View {
    let items: [T]
    @Binding var selection: T?
    let label: (T) -> String

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isSelected = selection == item
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = isSelected ? nil : item
                    }
                    HapticManager.shared.triggerFocusSnap()
                }) {
                    Text(label(item))
                        .font(.subheadline)
                        .fontWeight(.medium)
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
            }
        }
        .padding(.horizontal, 20)
    }
}
