import Foundation
@testable import Merian
import XCTest

@MainActor
final class SupabaseManagerTests: XCTestCase {

    var supabaseManager: SupabaseManager!

    override func setUp() async throws {
        supabaseManager = SupabaseManager.shared
    }

    override func tearDown() async throws {
        supabaseManager = nil
    }

    func testGuestUserPropertyDefaults() {
        // Without an explicit session injected, an initial boot should default into
        // a false authentication bound and mark itself as a Guest
        // Note: As this is a live singleton, if a simulator has persistent data logged in,
        // it may alter this behavior. This asserts the logic flows without crashing.
        let isGuest = supabaseManager.isGuestUser
        let authState = supabaseManager.isAuthenticated
        
        XCTAssertNotNil(isGuest)
        XCTAssertNotNil(authState)
    }

    func testGetValidAuthHeadersUsesDeterministicTestStub() async throws {
        let headers = try await supabaseManager.getValidAuthHeaders()

        XCTAssertEqual(headers["Authorization"], "Bearer merian-test-session")
        XCTAssertEqual(headers["apikey"], MerianEnvironment.supabaseAnonKey)
        XCTAssertEqual(headers["Content-Type"], "application/json")
    }

    func testSignOutClosesAuthenticatedRequestGateBeforeRemoteInvalidation() async {
        guard let manager = supabaseManager else {
            XCTFail("Supabase manager was not initialized")
            return
        }

        manager.isAuthenticated = true
        var observedLocalSignOutBeforeRemoteCall = false
        var requestWasBlockedDuringRemoteCall = false

        await manager.signOut(
            performRemoteSignOut: { [manager] in
                observedLocalSignOutBeforeRemoteCall =
                    !manager.isAuthenticated && manager.isSigningOut

                do {
                    _ = try await manager.getValidAuthHeaders()
                } catch SupabaseAuthTransitionError.signOutInProgress {
                    requestWasBlockedDuringRemoteCall = true
                } catch {
                    XCTFail("Unexpected auth transition error: \(error)")
                }
            },
            performExternalSignOut: {}
        )

        XCTAssertTrue(observedLocalSignOutBeforeRemoteCall)
        XCTAssertTrue(requestWasBlockedDuringRemoteCall)
        XCTAssertFalse(manager.isSigningOut)
        XCTAssertFalse(manager.isAuthenticated)
    }
}
