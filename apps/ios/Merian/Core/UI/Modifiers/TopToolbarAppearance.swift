import SwiftUI

extension View {
    /// Apply directly to a ScrollView, List, or Form. Navigation and sheet
    /// hosts can reset the scroll-edge configuration inherited from an ancestor.
    func transparentTopToolbar() -> some View {
        modifier(TransparentTopToolbarModifier())
    }
}

private struct TransparentTopToolbarModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectHidden(true, for: .top)
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            content.toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
