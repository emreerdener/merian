import Foundation
@testable import Merian
import Testing

@MainActor
struct CapturedMediaResolutionTests {
    @Test func storedMediaReferenceResolvesOnlyHTTPSForRemoteStorage() {
        let secure = StoredMediaReference.remoteURL(
            "https://cdn.example.com/image.webp"
        )
        let cleartext = StoredMediaReference.remoteURL(
            "http://cdn.example.com/image.webp"
        )

        #expect(secure.resolvedURL?.scheme == "https")
        #expect(cleartext.resolvedURL == nil)
        #expect(
            StoredMediaReference.absolutePath(
                "file:///tmp/image.webp"
            ).resolvedURL?.isFileURL == true
        )
    }
}
