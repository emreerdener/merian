import SwiftUI

struct DictionaryTopEdgeModifier: ViewModifier {
    let isHidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(isHidden, for: .top)
        } else {
            content
        }
    }
}

struct DictionaryHeroContentSheetModifier: ViewModifier {
    private let contentTopSpacing: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .padding(.top, contentTopSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius:
                        SpeciesDictionaryHeroLayout.contentOverlap,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius:
                        SpeciesDictionaryHeroLayout.contentOverlap
                )
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                .padding(.bottom, -1000)
            )
            .offset(y: -SpeciesDictionaryHeroLayout.contentOverlap)
            .padding(.bottom, -SpeciesDictionaryHeroLayout.contentOverlap)
            .zIndex(1)
    }
}
