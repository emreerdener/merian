import SwiftUI

struct MapGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

struct MapNavigationToolbar: View {
    let appearance: MapAppearance
    let isLocating: Bool
    let identifierPrefix: String
    let onToggleStyle: () -> Void
    let onSearch: () -> Void
    let onLocate: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleStyle) {
                Image(systemName: appearance == .satellite ? "map" : "globe.americas.fill")
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(appearance == .satellite ? "Show standard map" : "Show satellite map")
            .accessibilityValue(appearance == .satellite ? "Satellite" : "Standard")
            .accessibilityIdentifier(identifierPrefix + "Style")

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass").frame(width: 48, height: 48)
            }
            .accessibilityLabel("Search locations")
            .accessibilityIdentifier(identifierPrefix + "Search")

            Button(action: onLocate) {
                Group {
                    if isLocating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "location")
                    }
                }
                .frame(width: 48, height: 48)
            }
            .disabled(isLocating)
            .accessibilityLabel("Locate me")
            .accessibilityIdentifier(identifierPrefix + "Locate")
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .modifier(MapGlassCapsule())
    }
}

struct MapCountPillLabel: View {
    let fullLabel: String
    let compactLabel: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pill(fullLabel)
            pill(compactLabel)
        }
        .accessibilityLabel(fullLabel)
    }

    private func pill(_ label: String) -> some View {
        Text(label)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .modifier(MapGlassCapsule())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MapBottomControlRow<Count: View, Controls: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let count: () -> Count
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .trailing, spacing: 8) {
                count().frame(maxWidth: .infinity, alignment: .leading)
                controls()
            }
        } else {
            HStack(spacing: 8) {
                count()
                Spacer(minLength: 0)
                controls().fixedSize()
            }
        }
    }
}
