import SwiftUI

struct SpeciesSearchEntry: View {
    var body: some View {
        NavigationLink(value: SpeciesSearchRoute()) {
            if #available(iOS 26.0, *) {
                entryContent
                    .glassEffect(.regular.interactive(), in: Capsule())
            } else {
                entryContent
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .rainbowCapsuleAccent()
        .accessibilityLabel("Search or ask Naturebook")
        .accessibilityHint("Search species and public community sightings")
        .accessibilityIdentifier("SpeciesSearchEntry")
    }

    private var entryContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .accessibilityHidden(true)
            Text("Search or ask Naturebook")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .contentShape(Capsule())
    }
}
