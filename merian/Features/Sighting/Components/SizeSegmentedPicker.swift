import SwiftUI

struct SizeSegmentedPicker: View {
    @Binding var selection: ObservationSize?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ObservationSize.allCases, id: \.self) { size in
                    let isSelected = selection == size
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = isSelected ? nil : size
                        }
                        HapticManager.shared.triggerFocusSnap()
                    }) {
                        Text(size.shortLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if let s = selection {
                Text(s.displayName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}
