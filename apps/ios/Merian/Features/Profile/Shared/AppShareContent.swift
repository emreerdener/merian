import Foundation

enum AppShareContent {
    static let title = "Explore the living world with Naturebook"

    // swiftlint:disable:next todo
    // TODO(app-store-launch): Replace this served website fallback with the
    // App Store Connect campaign link after the listing is publicly reachable.
    static let destinationURL = PublicBrand.websiteURL

    @MainActor
    static var activityItems: [Any] {
        [LinkShareItemSource(url: destinationURL, title: title)]
    }

    @MainActor
    static func presentShareSheet() {
        ShareSheetPresenter.present(items: activityItems)
    }
}
