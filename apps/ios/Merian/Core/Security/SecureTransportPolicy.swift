import Foundation

/// The application-level counterpart to App Transport Security.
///
/// ATS remains the final platform backstop. These helpers reject insecure or
/// ambiguous remote references before they reach URLSession, AVFoundation, or
/// SwiftUI image loading, which also keeps malformed backend media from being
/// treated as a local path.
enum SecureTransportPolicy {
    static func httpsURL(from rawValue: String?) -> URL? {
        guard let trimmed = rawValue?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !trimmed.isEmpty,
        var components = URLComponents(string: trimmed),
        components.scheme?.lowercased() == "https",
        let host = components.host?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !host.isEmpty,
        components.user == nil,
        components.password == nil else {
            return nil
        }

        components.scheme = "https"
        return components.url
    }

    static func isSecureRemoteURL(_ url: URL) -> Bool {
        httpsURL(from: url.absoluteString) != nil
    }

    /// Resolves app-owned local media while admitting only HTTPS for a remote
    /// reference. Any other explicit scheme is rejected.
    static func localFileOrHTTPSURL(from rawValue: String?) -> URL? {
        guard let trimmed = rawValue?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        if let parsed = URL(string: trimmed), parsed.scheme != nil {
            if parsed.isFileURL {
                return parsed
            }
            return httpsURL(from: trimmed)
        }
        return URL(fileURLWithPath: trimmed)
    }
}
