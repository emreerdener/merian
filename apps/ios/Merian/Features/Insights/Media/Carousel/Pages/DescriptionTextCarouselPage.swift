import SwiftUI

// MARK: - Description Overlay Component

/// Dedicated visual abstraction managing the abbreviated visual representation explicitly mapping
/// the textual node context dynamically anchored alongside photo assets within the timeline natively.
struct DescriptionTextCarouselPage: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let onTap: (() -> Void)?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: .systemBackground)
                    .opacity(0.95)
                
                Image("animals-background")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(Color.green)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.20)
                    .clipped()
                
                // Description card
                VStack(spacing: 16) {
                    Text(text)
                        .font(.system(size: 80, weight: .medium))
                        .lineLimit(6)
                        .minimumScaleFactor(0.3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(28)
                .frame(width: max(0, geo.size.width - 48), height: max(0, geo.size.height - 216))
                .background(
                    colorScheme == .light 
                        ? AnyShapeStyle(Color.white.opacity(0.8)) 
                        : AnyShapeStyle(.ultraThinMaterial.opacity(0.75)), 
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(colorScheme == .light ? Color.black.opacity(0.1) : Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .offset(y: 24)
                
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
        }
    }
}
