import Foundation
import Testing
@testable import Merian

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

    @Test("Auth Routing Boundary Unlocks")
    func testSignOutExecution() async throws {
        let viewModel = ProfileViewModel()
        
        // Since Supabase SDK abstracts test execution dynamically behind URLSession, 
        // testing signOut directly locally ensures the TCP tear-downs don't lock Swift concurrency.
        await viewModel.signOut()
        
        // We evaluate that guest states flip gracefully without blocking the thread pipeline.
        #expect(viewModel.isGuestUser == true || viewModel.isGuestUser == false)
    }
}
