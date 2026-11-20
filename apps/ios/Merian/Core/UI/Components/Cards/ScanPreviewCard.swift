import SwiftUI

/// Shared scan-card layout; feature callers own media, metadata, and actions.
struct ScanPreviewCard<Media: View, Header: View, Actions: View>: View {
    var usesGlassBackground = false
    var stacksImageAboveContent = true
    var openTitle = "View discovery"
    let onOpen: () -> Void
    @ViewBuilder let media: () -> Media
    @ViewBuilder let header: () -> Header
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if stacksImageAboveContent {
                media()
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
            header()
            actions()
            Button(action: onOpen) {
                Text(openTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
        }
        .modifier(ScanPreviewCardSurface(usesGlass: usesGlassBackground))
    }
}

private struct ScanPreviewCardSurface: ViewModifier {
    let usesGlass: Bool

    func body(content: Content) -> some View {
        if usesGlass, #available(iOS 26.0, *) {
            content
                .padding(20)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        } else {
            content.card()
        }
    }
}
