import Foundation
@testable import Merian
import Testing

@Suite("App URL routing")
struct AppURLRoutingTests {
    @Test func incomingURLsPreserveHandlerPrecedence() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/shared-photo.jpg")
        let deepLink = try #require(URL(
            string: "naturebook://scan/example"
        ))
        let universalLink = try #require(URL(
            string: "https://naturebook.earth/explore/post/example"
        ))
        let legacyDeepLink = try #require(URL(
            string: "merian://scan/example"
        ))
        let legacyUniversalLink = try #require(URL(
            string: "https://merian.earth/explore/post/example"
        ))
        let authURL = try #require(URL(
            string: "https://example.supabase.co/auth/v1/callback?code=abc"
        ))

        #expect(MerianOpenURLRoute.classify(
            authURL,
            googleHandled: true
        ) == .handledByGoogle)
        #expect(MerianOpenURLRoute.classify(
            deepLink,
            googleHandled: false
        ) == .merianDeepLink)
        #expect(MerianOpenURLRoute.classify(
            universalLink,
            googleHandled: false
        ) == .merianDeepLink)
        #expect(MerianOpenURLRoute.classify(
            legacyDeepLink,
            googleHandled: false
        ) == .merianDeepLink)
        #expect(MerianOpenURLRoute.classify(
            legacyUniversalLink,
            googleHandled: false
        ) == .merianDeepLink)
        #expect(MerianOpenURLRoute.classify(
            fileURL,
            googleHandled: false
        ) == .externalImageImport)
        #expect(MerianOpenURLRoute.classify(
            authURL,
            googleHandled: false
        ) == .supabaseAuthentication)
    }
}
