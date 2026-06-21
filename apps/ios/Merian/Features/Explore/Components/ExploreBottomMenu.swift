import SwiftUI

struct ExploreDictionarySearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search species", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    HapticManager.shared.triggerLightImpact(intensity: 0.4)
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(isFocused ? 0.56 : 0.32), lineWidth: 0.5)
        )
        .frame(maxWidth: 560)
        .padding(.horizontal, 18)
        .accessibilityIdentifier("ExploreDictionarySearchBar")
    }
}
