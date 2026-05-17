import Foundation

public enum UserReviewState: String, Codable {
    case unreviewed
    case aiConfirmed = "ai_confirmed"
    case userOverridden = "user_overridden"
}
