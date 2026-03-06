import Foundation
import Combine
import SwiftUI

/// Mocked Manager assumed available globally within Merian Architecture
final class HapticManager {
    static let shared = HapticManager()
    private init() {}
    
    func triggerErrorThump() {
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
}

/// Automates Frontend Blocking capabilities syncing Optimistic Renders directly to TS Edges
@MainActor
final class SocialGuardManager: ObservableObject {
    static let shared = SocialGuardManager()
    
    @Published var blockedUserIds: Set<String> = []
    
    private let supabaseUrl = MerianEnvironment.supabaseUrl
    private let supabaseAnonKey = MerianEnvironment.supabaseAnonKey
    
    private init() {}
    
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
    
    private func syncBlockWithBackend(targetUserId: String) async -> Bool {
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/user_blocks") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        // Using mock user for sync pipeline assumption
        let mockBlockerId = "current-merian-user-uuid" 
        
        let payload: [String: String] = [
            "blocker_id": mockBlockerId,
            "blocked_id": targetUserId
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }
}
