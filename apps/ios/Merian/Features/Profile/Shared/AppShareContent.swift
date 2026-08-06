import Foundation

enum AppShareContent {
    static let title = "Explore the living world with Naturebook"
    static let message =
        "Share Naturebook with someone who would love identifying what they find outside."

    // swiftlint:disable:next todo
    // TODO(app-store-launch): Replace this served website fallback with the
    // App Store Connect campaign link after the listing is publicly reachable.
    static let destinationURL = PublicBrand.websiteURL

    static var shareText: String {
        "\(title)\n\n\(message)"
    }

    static var activityItems: [Any] {
        [shareText, destinationURL]
    }

    @MainActor
    static func presentShareSheet() {
        ShareSheetUtility.present(items: activityItems)
    }
}
