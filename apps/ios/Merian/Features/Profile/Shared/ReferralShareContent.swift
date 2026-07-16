import Foundation

enum ReferralShareContent {
    static let title = "Explore the living world with Naturebook"
    static let message = "Share Naturebook with someone who would love identifying what they find outside."

    // swiftlint:disable:next todo
    // TODO(referral): Replace this placeholder with the real referral/deep-link URL before launch tracking is enabled.
    static let url = PublicBrand.websiteURL(path: "invite")

    static var shareText: String {
        "\(title)\n\n\(message)"
    }

    static var activityItems: [Any] {
        [shareText, url]
    }

    @MainActor
    static func presentShareSheet() {
        ShareSheetUtility.present(items: activityItems)
    }
}
