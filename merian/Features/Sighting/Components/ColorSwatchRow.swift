import SwiftUI

struct ColorSwatchRow: View {
    @Binding var selection: Set<ObservationColor>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ObservationColor.allCases, id: \.self) { color in
                    let rgb = color.approximateColor
                    let swatchColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
                    let isSelected = selection.contains(color)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isSelected { selection.remove(color) } else { selection.insert(color) }
                        }
                        HapticManager.shared.triggerFocusSnap()
                    }) {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(swatchColor)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                isSelected ? Color.white : Color.white.opacity(0.2),
                                                lineWidth: isSelected ? 2 : 0.5
                                            )
                                    )

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(
                                            // Dark check on light swatches, white on dark
                                            (rgb.r + rgb.g + rgb.b) / 3 > 0.6 ? Color.black : Color.white
                                        )
                                }
                            }
                            Text(color.displayName)
                                .font(.caption2)
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }

    }
}
