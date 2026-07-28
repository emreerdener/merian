import Foundation

/// Unified application error taxonomy for Merian.
public enum MerianError: LocalizedError, Equatable {
    
    // MARK: - Network
    case invalidURL
    case uploadFailed
    case invalidResponse
    case decodingFailed
    case payloadTooLarge
    case httpError(statusCode: Int, message: String)
    case edgeFunctionUnavailable
    case networkTimeout

    // MARK: - Subscriptions / Entitlements
    case proRequiredForOfflineTracking
    
    // MARK: - Hardware
    case hardwareUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "The required network URL is invalid or malformed.")
        case .uploadFailed:
            return String(localized: "Failed to upload image data to the edge storage bucket.")
        case .invalidResponse:
            return String(localized: "Received an invalid response from the server.")
        case .decodingFailed:
            return String(localized: "Failed to decode the response payload into the expected struct.")
        case .payloadTooLarge:
            return String(localized: "The combined size of the captured media is too large. Please remove a photo or audio recording and try again.")
        case .httpError(let statusCode, let message):
            return String(localized: "Network Error (\(statusCode)): \(message)")
        case .edgeFunctionUnavailable:
            return String(localized: "This service is temporarily unavailable. Please try again in a few minutes.")
        case .networkTimeout:
            return String(localized: "The network request timed out. Please check your connection and try again.")
        case .proRequiredForOfflineTracking:
            return String(localized: "Naturebook Pro is required to track captures offline.")
        case .hardwareUnavailable:
            return String(localized: "A required hardware component (like the LiDAR scanner or Camera) is unavailable.")
        }
    }
}
