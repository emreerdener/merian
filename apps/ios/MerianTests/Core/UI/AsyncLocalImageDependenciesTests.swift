import Testing
import UIKit

@testable import Merian

@Suite("Async local image dependencies")
struct AsyncLocalImageDependenciesTests {
    @Test @MainActor func injectedLoaderReceivesTheRequestedSources() async {
        var receivedPath: String?
        var receivedFallbackURL: String?
        var receivedMaxDimension: Int?
        let expectedImage = UIImage()
        let dependencies = AsyncLocalImageDependencies(
            loadImage: { path, fallbackURL, maxDimension in
                receivedPath = path
                receivedFallbackURL = fallbackURL
                receivedMaxDimension = maxDimension
                return expectedImage
            }
        )

        let image = await dependencies.loadImage(
            "/tmp/local.webp",
            "https://example.com/fallback.webp",
            2_048
        )

        #expect(image === expectedImage)
        #expect(receivedPath == "/tmp/local.webp")
        #expect(receivedFallbackURL == "https://example.com/fallback.webp")
        #expect(receivedMaxDimension == 2_048)
    }
}
