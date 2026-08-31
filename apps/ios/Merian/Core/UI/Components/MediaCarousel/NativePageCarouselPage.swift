import SwiftUI

/// Domain-neutral page value consumed by the shared native media pager.
/// `reuseKey` lets a feature preserve a mounted controller only while the
/// feature-owned content identity remains equivalent.
struct NativePageCarouselPage: Identifiable, Equatable {
    let id: String
    let reuseKey: AnyHashable
    let view: AnyView

    init(
        id: String,
        reuseKey: AnyHashable? = nil,
        view: AnyView
    ) {
        self.id = id
        self.reuseKey = reuseKey ?? AnyHashable(id)
        self.view = view
    }

    static func == (
        lhs: NativePageCarouselPage,
        rhs: NativePageCarouselPage
    ) -> Bool {
        lhs.id == rhs.id && lhs.reuseKey == rhs.reuseKey
    }
}
