@testable import Merian
import Testing

@Suite("ProfileViewModel Tests")
@MainActor
struct ProfileViewModelTests {
    
    @Test("Initialization defaults")
    func testInitializationDefaults() async throws {
        let viewModel = ProfileViewModel()
        // The default geoprivacy string configuration should strictly map to standard payload keys natively.
        #expect(viewModel.defaultGeoprivacy == "open")
    }

    @Test("Custom display name wins over generated alias")
    func testCustomDisplayNameResolution() async throws {
        let viewModel = ProfileViewModel()
        viewModel.publicAuthorName = "River Wren"
        viewModel.publicIdentitySource = "display_name"

        #expect(viewModel.displayName == "River Wren")
    }

    @Test("Guest accounts hide provider-derived names")
    func testGuestAccountHidesProviderName() async throws {
        let viewModel = ProfileViewModel()
        viewModel.publicAuthorName = "Provider Name"
        viewModel.publicIdentitySource = "oauth"

        #expect(viewModel.displayName == "Explorer")
    }

    @Test("Sign-out messaging distinguishes auth closure from purchase sync")
    func testSignOutPresentationPolicy() {
        #expect(
            SignOutPresentationPolicy.incompleteMessage(
                isAnonymousSession: true
            ) == "You're signed out. Purchase access is still syncing. Use Finish sign out on your profile to retry."
        )
        #expect(
            SignOutPresentationPolicy.incompleteMessage(
                isAnonymousSession: false
            ) == "Naturebook couldn't sign you out. Check your connection and try again."
        )
    }

    @Test("User-facing authentication copy does not expose internal session terminology")
    func testUserFacingAuthenticationCopy() {
        let messages = [
            SupabaseAuthTransitionError.guestMergeSessionChanged.errorDescription,
            SupabaseAuthTransitionError.guestMergeHandoffPersistenceFailed.errorDescription,
            "Your signed-out profile is still loading. Try again in a moment."
        ].compactMap { $0 }

        for message in messages {
            #expect(!message.localizedCaseInsensitiveContains("guest"))
            #expect(!message.localizedCaseInsensitiveContains("ghost"))
        }
    }

}
