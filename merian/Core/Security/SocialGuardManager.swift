import Foundation
import Combine
import SwiftUI
import Observation

// MARK: - Core Trust & Safety Engine
@MainActor
@Observable final class SocialGuardManager {
    // MARK: - Singleton Architecture
    static let shared = SocialGuardManager()
    private init() {}
    
    // MARK: - State Management
    var blockedUserIds: Set<String> = []
    
    // MARK: - Environment Keys
    private let supabaseUrl = MerianEnvironment.supabaseUrl
    private let supabaseAnonKey = MerianEnvironment.supabaseAnonKey
    
    // MARK: - Public Moderation Actions
    func blockUser(targetUserId: String) async {
        // Step 1: Execute Optimistic Insertion so UI bounds immediately react
        blockedUserIds.insert(targetUserId)
        
        // Step 2: Trigger heavy haptic thump via the HapticManager
        HapticManager.shared.triggerErrorThump()
        
        // Step 3: Call Private Edge Sync
        let success = await syncBlockWithBackend(targetUserId: targetUserId)
        
        if !success {
            // Revert Optimistic Render back down to standard configurations 
            blockedUserIds.remove(targetUserId)
            print("SocialGuard: Failed to establish strict backend boundary. Optimistic Block Reversed.")
        } else {
            print("SocialGuard: Block successful against User \(targetUserId)")
        }
    }
    
    // MARK: - Private API Sync Logic
    private func syncBlockWithBackend(targetUserId: String) async -> Bool {
        do {
            try await MerianNetworkClient.shared.blockUser(targetUserId: targetUserId)
            return true
        } catch {
            return false
        }
    }
}
